-- Tags: no-parallel

CREATE DATABASE rdb1 ENGINE = Replicated('/test/test_replication_lag_metric', 'shard1', 'replica1');
CREATE DATABASE rdb2 ENGINE = Replicated('/test/test_replication_lag_metric', 'shard1', 'replica2');

SET distributed_ddl_task_timeout = 0;
CREATE TABLE rdb1.t (id UInt32) ENGINE = ReplicatedMergeTree ORDER BY id;

-- The local replica (replica1) should have zero lag; the other (replica2) should have non-zero lag
-- because distributed_ddl_task_timeout = 0 means we don't wait for the other replica to process the entry.
-- The exact lag for replica2 depends on timing (whether its DDL worker has initialized), so check > 0.
SELECT
    replication_lag = 0,
    replication_lag > 0
FROM system.clusters
WHERE cluster IN ('rdb1', 'rdb2')
ORDER BY cluster ASC, replica_num ASC;

DROP DATABASE rdb1;
DROP DATABASE rdb2;
