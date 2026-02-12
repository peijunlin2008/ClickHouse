-- Tags: no-fasttest
-- Verify that system log tables have secondary indexes on time columns.

SYSTEM FLUSH LOGS query_log;
SYSTEM FLUSH LOGS metric_log;

SELECT database, table, name, type, granularity
FROM system.data_skipping_indices
WHERE database = 'system' AND table = 'query_log'
ORDER BY name;

SELECT database, table, name, type, granularity
FROM system.data_skipping_indices
WHERE database = 'system' AND table = 'metric_log'
ORDER BY name;
