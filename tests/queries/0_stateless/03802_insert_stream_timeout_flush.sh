#!/usr/bin/env bash
# Tags: no-async-insert
# no-async-insert: Test expects new part for each time interval

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

function run_test() {
    local parallel_parsing=$1
    local test_suffix=$2
    
    ${CLICKHOUSE_CLIENT} --query "DROP TABLE IF EXISTS test_insert_timeout${test_suffix}"
    ${CLICKHOUSE_CLIENT} --query "CREATE TABLE test_insert_timeout${test_suffix} (id UInt64, data String) ENGINE MergeTree ORDER BY id"
    
    {
        for iteration in 1 2; do
            for i in $(seq 1 40); do
                echo "{\"id\":$(( (iteration*100) + i )),\"data\":\"batch_${iteration}\"}"
            done
            sleep 6
            echo "{\"id\":$(( (iteration*100) + 99 )),\"data\":\"trigger_${iteration}\"}"
        done
    } | ${CLICKHOUSE_CLIENT} --query "INSERT INTO test_insert_timeout${test_suffix} FORMAT JSONEachRow" \
        --max_insert_block_size=1000 \
        --input_format_max_block_wait_ms=2000 \
        --min_insert_block_size_bytes=0 \
        --min_insert_block_size_rows=0 \
	--min_chunk_bytes_for_parallel_parsing=10485760 \
	--max_block_size=65409 \
	--max_insert_block_size=1048449 \
        --input_format_parallel_parsing=${parallel_parsing}
    
    sleep 1
    
    record_count=$(${CLICKHOUSE_CLIENT} --query "SELECT count() FROM test_insert_timeout${test_suffix}")
    echo "Total records inserted: ${record_count}"
    
    $CLICKHOUSE_CLIENT -q "SYSTEM FLUSH LOGS query_log, part_log;"
    
    parts_count=$(${CLICKHOUSE_CLIENT} --query "
        SELECT count(*)
        FROM system.part_log
        WHERE table = 'test_insert_timeout${test_suffix}'
            AND event_type = 'NewPart'
            AND query_id = (
                SELECT argMax(query_id, event_time)
                FROM system.query_log
                WHERE query LIKE '%INSERT INTO test_insert_timeout${test_suffix}%'
                    AND current_database = currentDatabase()
            )
    ")
    echo "Number of parts created: ${parts_count}"
    
    ${CLICKHOUSE_CLIENT} --query "DROP TABLE IF EXISTS test_insert_timeout${test_suffix}"
}

# Run test with parallel_parsing=0
run_test 0 "_no_parallel"

# Run test with parallel_parsing=1
run_test 1 "_parallel"
