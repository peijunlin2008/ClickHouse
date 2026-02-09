-- Tags: no-random-settings, no-random-merge-tree-settings

DROP TABLE IF EXISTS t;

CREATE TABLE t
(
    CounterID UInt32,
    UserID UInt64,
    Version UInt64
)
ENGINE = ReplacingMergeTree(Version)
ORDER BY CounterID
PARTITION BY intHash32(UserID) % 100
SETTINGS index_granularity = 64, index_granularity_bytes = '1Mi';

SYSTEM STOP MERGES t;

-- CounterID in [0; 10000)
INSERT INTO t SELECT number, number % 1000, number % 10 FROM numbers_mt(100000);

-- Make around half of the rows to intersect with a smaller parts below

-- CounterID in [0; 5000)
INSERT INTO t SELECT number%5000, number % 1000, number % 10 FROM numbers_mt(5000);
-- CounterID in [1000; 15000)
INSERT INTO t SELECT number%5000+10000, number % 1000, number % 10 FROM numbers_mt(5000);
-- CounterID in [2000; 25000)
INSERT INTO t SELECT number%5000+20000, number % 1000, number % 10 FROM numbers_mt(5000);
-- CounterID in [3000; 35000)
INSERT INTO t SELECT number%5000+30000, number % 1000, number % 10 FROM numbers_mt(5000);
-- CounterID in [4000; 45000)
INSERT INTO t SELECT number%5000+40000, number % 1000, number % 10 FROM numbers_mt(5000);
-- CounterID in [50000; 55000)
INSERT INTO t SELECT number%5000+50000, number % 1000, number % 10 FROM numbers_mt(5000);
-- CounterID in [6000; 65000)
INSERT INTO t SELECT number%5000+60000, number % 1000, number % 10 FROM numbers_mt(5000);
-- CounterID in [7000; 75000)
INSERT INTO t SELECT number%5000+70000, number % 1000, number % 10 FROM numbers_mt(5000);
-- CounterID in [8000; 85000)
INSERT INTO t SELECT number%5000+80000, number % 1000, number % 10 FROM numbers_mt(5000);
-- CounterID in [9000; 95000)
INSERT INTO t SELECT number%5000+90000, number % 1000, number % 10 FROM numbers_mt(5000);

SET max_threads = 16, max_final_threads = 16, max_streams_to_max_threads_ratio = 1;

-- The number of partition (100) as well as parts is much larger than the allowed number of streams. Let's check that we won't produce too many streams:
-- it is still allowed to process each partition independently (thus producing 100 streams), but we should not split parts into smaller ranges within partitions.
SET split_parts_ranges_into_intersecting_and_non_intersecting_final = 1, split_intersecting_parts_ranges_into_layers_final = 1, do_not_merge_across_partitions_select_final = 1;

--set send_logs_level = 'trace', send_logs_source_regexp = 'debug|executeQuery';

SELECT replaceRegexpOne(trimBoth(explain), 'n\d+ (.*)', '\\1')
FROM (
EXPLAIN PIPELINE graph=1, compact=1
SELECT count() FROM t FINAL GROUP BY UserID
) WHERE explain ILIKE '%SelectByIndicesTransform%' OR explain ILIKE '%AggregatingTransform%'
ORDER BY explain;

DROP TABLE t;
