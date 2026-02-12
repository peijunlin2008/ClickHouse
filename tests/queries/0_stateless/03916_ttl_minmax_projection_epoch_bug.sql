

DROP TABLE IF EXISTS test_ttl_minmax_epoch;

CREATE TABLE test_ttl_minmax_epoch
(
    timestamp DateTime,
    id UUID,
    payload String
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (timestamp, id)
TTL timestamp + INTERVAL 1 MINUTE;

-- Partition 1: rows from ~1-60 seconds ago, some will expire during merge
INSERT INTO test_ttl_minmax_epoch
SELECT
    now('UTC') - toIntervalSecond(1 + rand() % 60) AS timestamp,
    generateUUIDv4() AS id,
    randomPrintableASCII(200) AS payload
FROM numbers(500000);

-- Partition 2: tomorrow (safe from TTL, control group)
INSERT INTO test_ttl_minmax_epoch
SELECT
    now('UTC') + toIntervalDay(1) - toIntervalSecond(rand() % 60) AS timestamp,
    generateUUIDv4() AS id,
    randomPrintableASCII(200) AS payload
FROM numbers(500000);

SELECT count() FROM test_ttl_minmax_epoch WHERE timestamp < '1970-01-02';

OPTIMIZE TABLE test_ttl_minmax_epoch FINAL;

SELECT (SELECT min(timestamp) FROM test_ttl_minmax_epoch) =
       (SELECT min(timestamp) FROM test_ttl_minmax_epoch SETTINGS optimize_use_implicit_projections = 0) AS minmax_matches;

SELECT countIf(min_time < '1971-01-01') AS parts_with_epoch_mintime
FROM system.parts
WHERE table = 'test_ttl_minmax_epoch' AND database = currentDatabase() AND active;


DROP TABLE test_ttl_minmax_epoch;
