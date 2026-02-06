#!/usr/bin/env bash
# Tags: no-fasttest, no-parallel, long

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

NUM_DATABASES=300
user="user_03821_$CLICKHOUSE_DATABASE"

function cleanup()
{
    for i in $(seq 1 $NUM_DATABASES); do
        $CLICKHOUSE_CLIENT --query "DROP DATABASE IF EXISTS test_03821_db_$i" 2>/dev/null &
    done
    wait
    $CLICKHOUSE_CLIENT --query "DROP USER IF EXISTS $user" 2>/dev/null
}
trap cleanup EXIT

for i in $(seq 1 $NUM_DATABASES); do
    $CLICKHOUSE_CLIENT --query "CREATE DATABASE IF NOT EXISTS test_03821_db_$i" 2>/dev/null &
done
wait

$CLICKHOUSE_CLIENT --query "DROP USER IF EXISTS $user"
$CLICKHOUSE_CLIENT --query "CREATE USER $user"
$CLICKHOUSE_CLIENT --query "GRANT SHOW DATABASES ON test_03821_db_1.* TO $user"
$CLICKHOUSE_CLIENT --query "GRANT SHOW DATABASES ON test_03821_db_2.* TO $user"
$CLICKHOUSE_CLIENT --query "GRANT SHOW DATABASES ON test_03821_db_3.* TO $user"
$CLICKHOUSE_CLIENT --query "GRANT SHOW DATABASES ON test_03821_db_4.* TO $user"
$CLICKHOUSE_CLIENT --query "GRANT SHOW DATABASES ON test_03821_db_5.* TO $user"

$CLICKHOUSE_CLIENT --user "$user" --query "SELECT count() FROM system.databases WHERE name LIKE 'test_03821_db_%'"
