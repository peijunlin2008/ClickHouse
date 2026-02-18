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
# The other replica (replica2) may or may not have caught up (timing-dependent):
#   lag = 2 means replica2's DDL worker initialized (set log_ptr = max_log_ptr = 1) before
#           the CREATE TABLE committed (which sets max_log_ptr = 3), so lag = 3 - 1 = 2.
#   lag = 3 means replica2's DDL worker hasn't initialized yet (log_ptr still 0), so lag = 3 - 0 = 3.
#   lag = 0 means replica2 fully caught up before the SELECT.
#
# We retry in a loop and check that at least once we observe the expected state:
# replica1 lag = 0 and replica2 lag > 0.

DB1="rdb1_${CLICKHOUSE_TEST_UNIQUE_NAME}"
DB2="rdb2_${CLICKHOUSE_TEST_UNIQUE_NAME}"
ZK_PATH="/test/test_replication_lag_metric/${CLICKHOUSE_TEST_UNIQUE_NAME}"

for i in $(seq 1 10); do
    $CLICKHOUSE_CLIENT --query "CREATE DATABASE ${DB1} ENGINE = Replicated('${ZK_PATH}/${i}', 'shard1', 'replica1')"
    $CLICKHOUSE_CLIENT --query "CREATE DATABASE ${DB2} ENGINE = Replicated('${ZK_PATH}/${i}', 'shard1', 'replica2')"

    $CLICKHOUSE_CLIENT --distributed_ddl_task_timeout 0 --query \
        "CREATE TABLE ${DB1}.t (id UInt32) ENGINE = ReplicatedMergeTree ORDER BY id"

    lag1=$($CLICKHOUSE_CLIENT --query "SELECT replication_lag FROM system.clusters WHERE cluster = '${DB1}' AND replica_num = 1")
    lag2=$($CLICKHOUSE_CLIENT --query "SELECT replication_lag FROM system.clusters WHERE cluster = '${DB1}' AND replica_num = 2")

    $CLICKHOUSE_CLIENT --query "DROP DATABASE ${DB1}"
    $CLICKHOUSE_CLIENT --query "DROP DATABASE ${DB2}"

    if [[ "$lag1" == "0" ]] && [[ "$lag2" -gt 0 ]]; then
        echo "OK"
        exit 0
    fi
done

echo "FAIL: could not observe expected replication lag in 10 attempts (last: replica1=$lag1 replica2=$lag2)"
exit 1
