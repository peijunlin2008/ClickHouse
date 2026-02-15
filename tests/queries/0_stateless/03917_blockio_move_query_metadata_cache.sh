#!/usr/bin/env bash
# Tags: long

# Regression test for https://github.com/ClickHouse/ClickHouse/issues/95742
#
# BlockIO::operator= was not moving query_metadata_cache, causing premature
# destruction of cached StorageSnapshots. When combined with concurrent
# DETACH/ATTACH, the storage could be freed while parts still reference it,
# leading to SEGFAULT in clearCaches.
#
# The bug is triggered on every query through both TCP and HTTP paths:
#   executeQuery(String, ...): res = executeQueryImpl(...)
# The operator= moves the pipeline but not the cache. The temp BlockIO is
# destroyed immediately, destroying the cache while the pipeline lives on.
# For mutation validation queries (ALTER TABLE ... UPDATE), the validation
# pipeline is created and destroyed inside MutationsInterpreter::validate(),
# leaving the cache entry as the ONLY remaining StorageSnapshotPtr.

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

TABLE="test_cache_race_${CLICKHOUSE_DATABASE}"

$CLICKHOUSE_CLIENT --query "DROP TABLE IF EXISTS ${TABLE}"
$CLICKHOUSE_CLIENT --query "
    CREATE TABLE ${TABLE} (key UInt64, value String)
    ENGINE = MergeTree ORDER BY key
"

# Create multiple parts so snapshots have non-trivial data
for i in $(seq 1 20); do
    $CLICKHOUSE_CLIENT --query "INSERT INTO ${TABLE} SELECT number, toString(number) FROM numbers($((i * 100)), 100)"
done

function mutation_thread()
{
    local TIMELIMIT=$((SECONDS+$1))
    while [ $SECONDS -lt "$TIMELIMIT" ]; do
        # ALTER TABLE ... UPDATE goes through MutationsInterpreter::validate()
        # which caches a StorageSnapshot in QueryMetadataCache, then destroys
        # the validation pipeline. The cache entry becomes the only ref.
        $CLICKHOUSE_CLIENT --query \
            "ALTER TABLE ${TABLE} UPDATE value = 'x' WHERE key > $RANDOM SETTINGS mutations_sync = 0" \
            2>/dev/null
        sleep 0.0$RANDOM
    done
}

function detach_attach_thread()
{
    local TIMELIMIT=$((SECONDS+$1))
    while [ $SECONDS -lt "$TIMELIMIT" ]; do
        # DETACH removes the storage from the database, dropping its StoragePtr.
        # If the cache snapshot holds the last ref, destroying the cache will
        # free the storage while parts still exist in shared_ranges_in_parts.
        $CLICKHOUSE_CLIENT --query "DETACH TABLE ${TABLE}" 2>/dev/null
        sleep 0.0$RANDOM
        $CLICKHOUSE_CLIENT --query "ATTACH TABLE ${TABLE}" 2>/dev/null
        sleep 0.0$RANDOM
    done
}

function select_thread()
{
    local TIMELIMIT=$((SECONDS+$1))
    while [ $SECONDS -lt "$TIMELIMIT" ]; do
        # Subquery on the same table exercises snapshot cache sharing:
        # both the outer and inner query hit getStorageSnapshot, and the
        # second call returns the cached snapshot.
        $CLICKHOUSE_CLIENT --query \
            "SELECT count() FROM ${TABLE} WHERE value IN (SELECT value FROM ${TABLE} WHERE key > $RANDOM)" \
            2>/dev/null
        sleep 0.0$RANDOM
    done
}

TIMEOUT=15

mutation_thread $TIMEOUT &
mutation_thread $TIMEOUT &
select_thread $TIMEOUT &
select_thread $TIMEOUT &
detach_attach_thread $TIMEOUT &

wait

# Re-attach in case the table was left detached
$CLICKHOUSE_CLIENT --query "ATTACH TABLE ${TABLE}" 2>/dev/null

# Verify the server is still alive (the original bug caused SEGFAULT)
$CLICKHOUSE_CLIENT --query "SELECT 1"

$CLICKHOUSE_CLIENT --query "DROP TABLE IF EXISTS ${TABLE}"
