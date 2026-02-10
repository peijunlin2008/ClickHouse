DROP TABLE IF EXISTS test_table;
SET allow_experimental_statistics = 1;

CREATE TABLE test_table
(
    a UInt64,
    b String,
    c UInt64
)
ENGINE = MergeTree
ORDER BY a
SETTINGS
    enable_block_number_column = 0,
    enable_block_offset_column = 0,
    auto_statistics_types = '';

SYSTEM STOP MERGES test_table;

-- Insert first part without statistics
INSERT INTO test_table SELECT number, toString(number % 5), number % 3 FROM numbers(10000);

SELECT 'after first insert, no statistics';

SELECT name, column, type, statistics, estimates.cardinality, estimates.min, estimates.max
FROM system.parts_columns
WHERE database = currentDatabase() AND table = 'test_table' AND active
ORDER BY name, column;

SELECT count() FROM test_table;
SELECT uniqExact(a), uniqExact(b), uniqExact(c) FROM test_table;

-- Enable auto statistics
ALTER TABLE test_table MODIFY SETTING auto_statistics_types = 'uniq,minmax';

-- Insert second part with statistics
INSERT INTO test_table SELECT number + 10000, toString(number % 7 + 10), number % 4 + 10 FROM numbers(10000);

SELECT 'after second insert, partially materialized statistics';

SELECT name, column, type, statistics, estimates.cardinality, estimates.min, estimates.max
FROM system.parts_columns
WHERE database = currentDatabase() AND table = 'test_table' AND active
ORDER BY name, column;

SELECT count() FROM test_table;
SELECT uniqExact(a), uniqExact(b), uniqExact(c) FROM test_table;

-- Merge all parts
SYSTEM START MERGES test_table;
OPTIMIZE TABLE test_table FINAL;

SELECT 'after optimize final';

SELECT name, column, type, statistics, estimates.cardinality, estimates.min, estimates.max
FROM system.parts_columns
WHERE database = currentDatabase() AND table = 'test_table' AND active
ORDER BY name, column;

SELECT count() FROM test_table;
SELECT uniqExact(a), uniqExact(b), uniqExact(c) FROM test_table;

DROP TABLE IF EXISTS test_table;
