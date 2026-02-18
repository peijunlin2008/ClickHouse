#!/usr/bin/env bash
# Tags: zookeeper

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

# Test that replication_lag metric in system.clusters works for Replicated databases.
#
# The initiator replica (replica1) is guaranteed to have zero lag after executing a DDL,
# because tryEnqueueAndExecuteEntry commits the entry and updates log_ptr before returning.
#
# The other replica (replica2) may or may not have caught up by the time we query
# (timing-dependent), so we only check that it has a valid (non-NULL) value.
#
# After syncing replica2 via SYSTEM SYNC DATABASE REPLICA, both replicas must have lag = 0.

DB1="rdb1_${CLICKHOUSE_TEST_UNIQUE_NAME}"
DB2="rdb2_${CLICKHOUSE_TEST_UNIQUE_NAME}"
ZK_PATH="/test/test_replication_lag_metric/${CLICKHOUSE_TEST_UNIQUE_NAME}"

$CLICKHOUSE_CLIENT --query "CREATE DATABASE ${DB1} ENGINE = Replicated('${ZK_PATH}', 'shard1', 'replica1')"
$CLICKHOUSE_CLIENT --query "CREATE DATABASE ${DB2} ENGINE = Replicated('${ZK_PATH}', 'shard1', 'replica2')"

$CLICKHOUSE_CLIENT --distributed_ddl_task_timeout 0 --query \
    "CREATE TABLE ${DB1}.t (id UInt32) ENGINE = ReplicatedMergeTree ORDER BY id"

# Initiator (replica1) is guaranteed to have lag = 0 after local execution.
$CLICKHOUSE_CLIENT --query "
    SELECT replication_lag = 0
    FROM system.clusters
    WHERE cluster = '${DB1}' AND replica_num = 1"

# Non-initiator (replica2) should have a valid non-NULL lag (value is timing-dependent).
$CLICKHOUSE_CLIENT --query "
    SELECT replication_lag IS NOT NULL
    FROM system.clusters
    WHERE cluster = '${DB1}' AND replica_num = 2"

# After syncing, both replicas must have lag = 0.
$CLICKHOUSE_CLIENT --query "SYSTEM SYNC DATABASE REPLICA ${DB2}"
$CLICKHOUSE_CLIENT --query "
    SELECT replication_lag
    FROM system.clusters
    WHERE cluster IN ('${DB1}', '${DB2}')
    ORDER BY cluster ASC, replica_num ASC"

$CLICKHOUSE_CLIENT --query "DROP DATABASE ${DB1}"
$CLICKHOUSE_CLIENT --query "DROP DATABASE ${DB2}"
