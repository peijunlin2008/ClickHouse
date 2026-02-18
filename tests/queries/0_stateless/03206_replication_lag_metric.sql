-- Tags: no-parallel

CREATE DATABASE rdb1 ENGINE = Replicated('/test/test_replication_lag_metric', 'shard1', 'replica1');
CREATE DATABASE rdb2 ENGINE = Replicated('/test/test_replication_lag_metric', 'shard1', 'replica2');

SET distributed_ddl_task_timeout = 0;
CREATE TABLE rdb1.t (id UInt32) ENGINE = ReplicatedMergeTree ORDER BY id;

-- The initiator replica (replica1) is guaranteed to have zero lag after executing a DDL,
-- because tryEnqueueAndExecuteEntry commits the entry and updates log_ptr before returning.
-- The other replica (replica2) may or may not have caught up by this point (timing-dependent),
-- so we only check that replication_lag is a valid non-negative value for all replicas.
SELECT replication_lag FROM system.clusters WHERE cluster = 'rdb1' AND is_local;
SELECT replication_lag >= 0 FROM system.clusters WHERE cluster IN ('rdb1', 'rdb2');

DROP DATABASE rdb1;
DROP DATABASE rdb2;
