#!/usr/bin/env bash
# Tags: no-random-settings

set -e

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh


echo "--- Correctness: FULL JOIN ---"
$CLICKHOUSE_CLIENT --multiquery -q "
SET enable_analyzer = 1, join_use_nulls = 1, query_plan_join_swap_table = 0;

-- Use string keys to force two-level hash maps
SET join_algorithm = 'hash';
SELECT count(), countIf(t1.key != ''), countIf(t2.key != '')
FROM (SELECT toString(number) AS key FROM numbers(50000)) AS t1
FULL JOIN (SELECT toString(number + 25000) AS key FROM numbers(50000)) AS t2
ON t1.key = t2.key;

SET join_algorithm = 'parallel_hash';
SELECT count(), countIf(t1.key != ''), countIf(t2.key != '')
FROM (SELECT toString(number) AS key FROM numbers(50000)) AS t1
FULL JOIN (SELECT toString(number + 25000) AS key FROM numbers(50000)) AS t2
ON t1.key = t2.key;
"

echo "--- Correctness: RIGHT JOIN ---"
$CLICKHOUSE_CLIENT --multiquery -q "
SET enable_analyzer = 1, join_use_nulls = 1, query_plan_join_swap_table = 0;

SET join_algorithm = 'hash';
SELECT count(), countIf(t1.key != ''), countIf(t2.key != '')
FROM (SELECT toString(number) AS key FROM numbers(50000)) AS t1
RIGHT JOIN (SELECT toString(number + 25000) AS key FROM numbers(50000)) AS t2
ON t1.key = t2.key;

SET join_algorithm = 'parallel_hash';
SELECT count(), countIf(t1.key != ''), countIf(t2.key != '')
FROM (SELECT toString(number) AS key FROM numbers(50000)) AS t1
RIGHT JOIN (SELECT toString(number + 25000) AS key FROM numbers(50000)) AS t2
ON t1.key = t2.key;
"


# When parallel non-joined processing is active, non-joined rows are emitted by
# separate NonJoinedBlocksTransform sources (not by JoiningTransform).
# There must be more than 1 such source producing output rows.

echo "--- Parallelism: multiple NonJoinedBlocksTransforms emit non-joined rows ---"

query_id="03800_parallel_nonjoin_${CLICKHOUSE_DATABASE}_$RANDOM"

$CLICKHOUSE_CLIENT --query_id="$query_id" --multiquery -q "
SET enable_analyzer = 1, query_plan_join_swap_table = 0;
SET join_algorithm = 'parallel_hash';
SET log_processors_profiles = 1;
SET max_threads = 8;

-- Force two-level hash maps via string keys with enough data
SELECT count()
FROM (SELECT toString(number) AS key FROM numbers(200000)) AS t1
FULL JOIN (SELECT toString(number + 100000) AS key FROM numbers(200000)) AS t2
ON t1.key = t2.key
FORMAT Null;
"

$CLICKHOUSE_CLIENT --multiquery -q "
SYSTEM FLUSH LOGS processors_profile_log;

-- Count NonJoinedBlocksTransforms that produced output rows.
-- With true parallelism this must be > 1.
SELECT
    if(transforms_producing_nonjoin_output > 1, 'PARALLEL', 'SEQUENTIAL') AS mode,
    transforms_producing_nonjoin_output > 1 AS is_parallel
FROM (
    SELECT countIf(output_rows > 0) AS transforms_producing_nonjoin_output
    FROM system.processors_profile_log
    WHERE event_date >= yesterday()
        AND query_id = '$query_id'
        AND name = 'NonJoinedBlocksTransform'
);
"

echo "--- Parallelism: all NonJoinedBlocksTransforms produce output ---"

$CLICKHOUSE_CLIENT --multiquery -q "
SELECT
    total_transforms > 0 AS has_transforms,
    idle_transforms = 0 AS all_active
FROM (
    SELECT
        count() AS total_transforms,
        countIf(output_rows = 0) AS idle_transforms
    FROM system.processors_profile_log
    WHERE event_date >= yesterday()
        AND query_id = '$query_id'
        AND name = 'NonJoinedBlocksTransform'
);
"

echo "--- Parallelism: work distributed across transforms ---"

$CLICKHOUSE_CLIENT --multiquery -q "
SELECT
    parallelism_factor > 1 AS work_is_distributed
FROM (
    SELECT
        if(max(elapsed_us) > 0, sum(elapsed_us) / max(elapsed_us), 1) AS parallelism_factor
    FROM system.processors_profile_log
    WHERE event_date >= yesterday()
        AND query_id = '$query_id'
        AND name = 'NonJoinedBlocksTransform'
);
"

# When the setting is disabled, only one JoiningTransform should emit non-joined rows (sequential mode).

echo "--- Setting disabled: falls back to sequential ---"

query_id_seq="03800_sequential_nonjoin_${CLICKHOUSE_DATABASE}_$RANDOM"

$CLICKHOUSE_CLIENT --query_id="$query_id_seq" --multiquery -q "
SET enable_analyzer = 1, query_plan_join_swap_table = 0;
SET join_algorithm = 'parallel_hash';
SET parallel_non_joined_rows_processing = 0;
SET log_processors_profiles = 1;
SET max_threads = 8;

SELECT count()
FROM (SELECT toString(number) AS key FROM numbers(200000)) AS t1
FULL JOIN (SELECT toString(number + 100000) AS key FROM numbers(200000)) AS t2
ON t1.key = t2.key
FORMAT Null;
"

$CLICKHOUSE_CLIENT --multiquery -q "
SYSTEM FLUSH LOGS processors_profile_log;

-- With the setting disabled, at most 1 transform should produce non-joined output.
SELECT
    if(transforms_producing_nonjoin_output <= 1, 'SEQUENTIAL', 'PARALLEL') AS mode,
    transforms_producing_nonjoin_output <= 1 AS is_sequential
FROM (
    SELECT countIf(input_rows = 0 AND output_rows > 0) AS transforms_producing_nonjoin_output
    FROM system.processors_profile_log
    WHERE event_date >= yesterday()
        AND query_id = '$query_id_seq'
        AND name = 'JoiningTransform'
);
"
