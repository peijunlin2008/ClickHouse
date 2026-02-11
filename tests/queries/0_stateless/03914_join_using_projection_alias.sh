#!/usr/bin/env bash
# Regression test: Bad cast from ConstantNode to ListNode when JOIN USING
# resolves identifier from a projection alias (with analyzer_compatibility_join_using_top_level_identifier).
# https://s3.amazonaws.com/clickhouse-test-reports/json.html?REF=master&sha=2d046da0e9520c48cd6d1c01eda29f76dcc4f93c&name_0=MasterCI&name_1=AST%20fuzzer%20%28amd_tsan%29

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

$CLICKHOUSE_CLIENT --query "DROP TABLE IF EXISTS t1"
$CLICKHOUSE_CLIENT --query "DROP TABLE IF EXISTS t2"
$CLICKHOUSE_CLIENT --query "DROP TABLE IF EXISTS t3"

$CLICKHOUSE_CLIENT --query "CREATE TABLE t1 (id String, val String) ENGINE = MergeTree ORDER BY id"
$CLICKHOUSE_CLIENT --query "CREATE TABLE t2 (id String, code String) ENGINE = MergeTree ORDER BY id"
$CLICKHOUSE_CLIENT --query "CREATE TABLE t3 (id String, code String) ENGINE = MergeTree ORDER BY id"

$CLICKHOUSE_CLIENT --query "INSERT INTO t1 VALUES ('a', '1')"
$CLICKHOUSE_CLIENT --query "INSERT INTO t2 VALUES ('a', 'x')"
$CLICKHOUSE_CLIENT --query "INSERT INTO t3 VALUES ('a', 'y')"

# Previously caused LOGICAL_ERROR: Bad cast from type DB::ConstantNode to DB::ListNode.
# After the fix, the query may succeed or return INVALID_JOIN_ON_EXPRESSION depending on
# the analyzer configuration -- both are acceptable, as long as there is no LOGICAL_ERROR.
ERROR=$($CLICKHOUSE_CLIENT --query "
    SET analyzer_compatibility_join_using_top_level_identifier = 1;
    SELECT t1.val, concat('_1', 2, 2) AS id
    FROM t1 LEFT JOIN t2 ON t1.id = t2.id LEFT JOIN t3 USING (id)
    ORDER BY t1.val ASC
" 2>&1 >/dev/null)

if echo "$ERROR" | grep -q "LOGICAL_ERROR"; then
    echo "UNEXPECTED: LOGICAL_ERROR encountered"
    echo "$ERROR"
elif [ -z "$ERROR" ] || echo "$ERROR" | grep -q "INVALID_JOIN_ON_EXPRESSION"; then
    echo "OK"
else
    echo "UNEXPECTED error: $ERROR"
fi

$CLICKHOUSE_CLIENT --query "DROP TABLE t1"
$CLICKHOUSE_CLIENT --query "DROP TABLE t2"
$CLICKHOUSE_CLIENT --query "DROP TABLE t3"
