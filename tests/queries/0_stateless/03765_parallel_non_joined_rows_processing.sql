-- Tags: no-random-settings

SET enable_analyzer = 1, query_plan_join_swap_table = 0;

SELECT '--- Correctness: FULL JOIN ---';

SET join_use_nulls = 1;

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

SELECT '--- Correctness: RIGHT JOIN ---';

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


SET join_use_nulls = 0;
SET join_algorithm = 'parallel_hash';
SET log_processors_profiles = 1;
SET max_threads = 8;

SET log_comment = '03800_parallel_nonjoin';
SET parallel_non_joined_rows_processing = 1;
SELECT count()
FROM (SELECT toString(number) AS key FROM numbers(200000)) AS t1
FULL JOIN (SELECT toString(number + 100000) AS key FROM numbers(200000)) AS t2
ON t1.key = t2.key
FORMAT Null;

SET log_comment = '03800_sequential_nonjoin';
SET parallel_non_joined_rows_processing = 0;
SELECT count()
FROM (SELECT toString(number) AS key FROM numbers(200000)) AS t1
FULL JOIN (SELECT toString(number + 100000) AS key FROM numbers(200000)) AS t2
ON t1.key = t2.key
FORMAT Null;

SYSTEM FLUSH LOGS query_log, processors_profile_log;

SELECT '--- Parallelism: multiple NonJoinedBlocksTransforms emit non-joined rows ---';

WITH (
    SELECT query_id FROM system.query_log
    WHERE current_database = currentDatabase()
        AND log_comment = '03800_parallel_nonjoin' AND type = 'QueryFinish' AND event_date >= yesterday()
    ORDER BY event_time DESC LIMIT 1
) AS parallel_id
SELECT
    if(countIf(output_rows > 0) > 1, 'PARALLEL', 'SEQUENTIAL') AS mode,
    countIf(output_rows > 0) > 1 AS is_parallel
FROM system.processors_profile_log
WHERE event_date >= yesterday() AND query_id = parallel_id AND name = 'NonJoinedBlocksTransform';

SELECT '--- Parallelism: all NonJoinedBlocksTransforms produce output ---';

WITH (
    SELECT query_id FROM system.query_log
    WHERE current_database = currentDatabase()
        AND log_comment = '03800_parallel_nonjoin' AND type = 'QueryFinish' AND event_date >= yesterday()
    ORDER BY event_time DESC LIMIT 1
) AS parallel_id
SELECT
    count() > 0 AS has_transforms,
    countIf(output_rows = 0) = 0 AS all_active
FROM system.processors_profile_log
WHERE event_date >= yesterday() AND query_id = parallel_id AND name = 'NonJoinedBlocksTransform';

SELECT '--- Parallelism: work distributed across transforms ---';

WITH (
    SELECT query_id FROM system.query_log
    WHERE current_database = currentDatabase()
        AND log_comment = '03800_parallel_nonjoin' AND type = 'QueryFinish' AND event_date >= yesterday()
    ORDER BY event_time DESC LIMIT 1
) AS parallel_id
SELECT
    if(max(elapsed_us) > 0, sum(elapsed_us) / max(elapsed_us), 1) > 1 AS work_is_distributed
FROM system.processors_profile_log
WHERE event_date >= yesterday() AND query_id = parallel_id AND name = 'NonJoinedBlocksTransform';

SELECT '--- Setting disabled: falls back to sequential ---';

WITH (
    SELECT query_id FROM system.query_log
    WHERE current_database = currentDatabase()
        AND log_comment = '03800_sequential_nonjoin' AND type = 'QueryFinish' AND event_date >= yesterday()
    ORDER BY event_time DESC LIMIT 1
) AS sequential_id
SELECT
    if(countIf(input_rows = 0 AND output_rows > 0) <= 1, 'SEQUENTIAL', 'PARALLEL') AS mode,
    countIf(input_rows = 0 AND output_rows > 0) <= 1 AS is_sequential
FROM system.processors_profile_log
WHERE event_date >= yesterday() AND query_id = sequential_id AND name = 'JoiningTransform';
