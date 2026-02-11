-- Test for issue #96670: min(timestamp) returns 1970-01-01 via _minmax_count_projection after TTL merge
-- When TTL removes all rows from a partition during merge, the minmax index should not be corrupted with epoch values
-- The bug was that empty blocks (after TTL filtering) were still passed to minmax_idx->update(),
-- and getExtremes() on an empty column returns 0, which is epoch for DateTime64.

-- { echoOn }

DROP TABLE IF EXISTS test_ttl_minmax_epoch;

-- Create table with DateTime64 + TTL that expires in the past
-- Use two separate partitions: one with expired data, one with future data
CREATE TABLE test_ttl_minmax_epoch
(
    id UInt64,
    timestamp DateTime64(6, 'UTC')
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, id)
TTL timestamp + INTERVAL 1 DAY
SETTINGS index_granularity = 8192;

-- Insert data into two partitions:
-- Partition 1: 30 days in the past (already expired, will be removed by TTL)
-- Partition 2: 30 days in the future (control partition, will not expire)
INSERT INTO test_ttl_minmax_epoch VALUES
    (1, now64(6, 'UTC') - INTERVAL 30 DAY),
    (2, now64(6, 'UTC') - INTERVAL 30 DAY),
    (3, now64(6, 'UTC') + INTERVAL 30 DAY),
    (4, now64(6, 'UTC') + INTERVAL 30 DAY);

-- Optimize to trigger TTL merge - the expired rows should be removed
OPTIMIZE TABLE test_ttl_minmax_epoch FINAL;

-- Verify only future rows remain (2 rows)
SELECT count() FROM test_ttl_minmax_epoch;

-- Verify no rows have timestamp near epoch (this should always be 0)
SELECT count() FROM test_ttl_minmax_epoch WHERE timestamp < '1970-01-02';

-- Key test: min(timestamp) via projection should equal min(timestamp) via scan
-- Before the fix, projection would return epoch (1970-01-01) due to corrupted minmax index
-- After the fix, both should return the same correct value (30 days in future)
SELECT (SELECT min(timestamp) FROM test_ttl_minmax_epoch) = (SELECT min(timestamp) FROM test_ttl_minmax_epoch SETTINGS optimize_use_implicit_projections = 0);

-- Also verify that the min is not epoch
SELECT min(timestamp) > '2020-01-01' FROM test_ttl_minmax_epoch;

DROP TABLE test_ttl_minmax_epoch;
