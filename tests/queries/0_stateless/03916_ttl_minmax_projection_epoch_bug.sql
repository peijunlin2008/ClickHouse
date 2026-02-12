-- Test for issue #96670: min(timestamp) returns 1970-01-01 via _minmax_count_projection after TTL merge
-- When TTL removes all rows from a partition during merge, the minmax index should not be corrupted with epoch values

DROP TABLE IF EXISTS test_ttl_minmax_epoch;
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

INSERT INTO test_ttl_minmax_epoch VALUES
    (1, now64(6, 'UTC') - INTERVAL 30 DAY),
    (2, now64(6, 'UTC') - INTERVAL 30 DAY),
    (3, now64(6, 'UTC') + INTERVAL 30 DAY),
    (4, now64(6, 'UTC') + INTERVAL 30 DAY);

OPTIMIZE TABLE test_ttl_minmax_epoch FINAL;

SELECT count() FROM test_ttl_minmax_epoch;
SELECT count() FROM test_ttl_minmax_epoch WHERE timestamp < '1970-01-02';
SELECT (SELECT min(timestamp) FROM test_ttl_minmax_epoch) = (SELECT min(timestamp) FROM test_ttl_minmax_epoch SETTINGS optimize_use_implicit_projections = 0);
SELECT min(timestamp) > '2020-01-01' FROM test_ttl_minmax_epoch;

DROP TABLE test_ttl_minmax_epoch;
