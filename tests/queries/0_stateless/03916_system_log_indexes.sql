-- Tags: no-fasttest
-- Verify that system log tables have secondary indexes and projection indexes.

SYSTEM FLUSH LOGS;

SELECT database, table, name, type, granularity
FROM system.data_skipping_indices
WHERE database = 'system' AND table = 'query_log'
ORDER BY name;

SELECT database, table, name, type
FROM system.projections
WHERE database = 'system' AND table = 'query_log'
ORDER BY name;

-- Check that a table without query_id (metric_log) only has minmax indexes and no projections.
SELECT database, table, name, type, granularity
FROM system.data_skipping_indices
WHERE database = 'system' AND table = 'metric_log'
ORDER BY name;

SELECT count()
FROM system.projections
WHERE database = 'system' AND table = 'metric_log';
