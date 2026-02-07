-- Tags: no-replicated-database

DROP DATABASE IF EXISTS test_lazy_load;

-- Create database with lazy_load_tables enabled (Atomic engine, the default)
CREATE DATABASE test_lazy_load ENGINE = Atomic SETTINGS lazy_load_tables = 1;

-- Create a MergeTree table and insert data
CREATE TABLE test_lazy_load.t1 (id UInt64, value String) ENGINE = MergeTree ORDER BY id;
INSERT INTO test_lazy_load.t1 VALUES (1, 'hello'), (2, 'world');

-- Create a view (should NOT be lazy-loaded)
CREATE VIEW test_lazy_load.v1 AS SELECT * FROM test_lazy_load.t1;

-- Detach and re-attach database to trigger reload with lazy loading
DETACH DATABASE test_lazy_load;
ATTACH DATABASE test_lazy_load;

-- After re-attach, the MergeTree table should show as TableProxy (lazy, not yet loaded).
-- Views are not lazy-loaded so they keep their real engine name.
SELECT name, engine FROM system.tables WHERE database = 'test_lazy_load' ORDER BY name;

-- Accessing the table should trigger loading and return the correct data.
SELECT * FROM test_lazy_load.t1 ORDER BY id;

-- The engine name in system.tables stays as TableProxy (by design: proxy wraps the real storage).
SELECT name, engine FROM system.tables WHERE database = 'test_lazy_load' ORDER BY name;

-- Test: DROP works on an unloaded lazy table.
-- Create t2, insert data, then detach/attach so it becomes a proxy.
CREATE TABLE test_lazy_load.t2 (x UInt32) ENGINE = MergeTree ORDER BY x;
INSERT INTO test_lazy_load.t2 VALUES (42);

DETACH DATABASE test_lazy_load;
ATTACH DATABASE test_lazy_load;

-- t2 should be a proxy now
SELECT name, engine FROM system.tables WHERE database = 'test_lazy_load' AND name = 't2';

-- DROP should work even though the table is still a proxy (forces nested load for cleanup)
DROP TABLE test_lazy_load.t2;
SELECT count() FROM system.tables WHERE database = 'test_lazy_load' AND name = 't2';

-- Cleanup
DROP DATABASE test_lazy_load;
