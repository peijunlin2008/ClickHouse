-- Tags: no-replicated-database

DROP DATABASE IF EXISTS {CLICKHOUSE_DATABASE_1:Identifier};

CREATE DATABASE {CLICKHOUSE_DATABASE_1:Identifier} ENGINE = Atomic SETTINGS lazy_load_tables = 1;

CREATE TABLE {CLICKHOUSE_DATABASE_1:Identifier}.t1 (id UInt64, value String) ENGINE = MergeTree ORDER BY id;
INSERT INTO {CLICKHOUSE_DATABASE_1:Identifier}.t1 VALUES (1, 'hello'), (2, 'world');

-- Use the database so the view's AS clause resolves table names without explicit db prefix.
USE {CLICKHOUSE_DATABASE_1:Identifier};
CREATE VIEW v1 AS SELECT * FROM t1;

DETACH DATABASE {CLICKHOUSE_DATABASE_1:Identifier};
ATTACH DATABASE {CLICKHOUSE_DATABASE_1:Identifier};

-- After re-attach, MergeTree shows as TableProxy; views load normally.
SELECT name, engine FROM system.tables WHERE database = {CLICKHOUSE_DATABASE_1:String} ORDER BY name;

SELECT * FROM {CLICKHOUSE_DATABASE_1:Identifier}.t1 ORDER BY id;

SELECT name, engine FROM system.tables WHERE database = {CLICKHOUSE_DATABASE_1:String} ORDER BY name;

-- DROP on an unloaded lazy proxy forces nested load for cleanup.
CREATE TABLE {CLICKHOUSE_DATABASE_1:Identifier}.t2 (x UInt32) ENGINE = MergeTree ORDER BY x;
INSERT INTO {CLICKHOUSE_DATABASE_1:Identifier}.t2 VALUES (42);

DETACH DATABASE {CLICKHOUSE_DATABASE_1:Identifier};
ATTACH DATABASE {CLICKHOUSE_DATABASE_1:Identifier};

SELECT name, engine FROM system.tables WHERE database = {CLICKHOUSE_DATABASE_1:String} AND name = 't2';

DROP TABLE {CLICKHOUSE_DATABASE_1:Identifier}.t2;
SELECT count() FROM system.tables WHERE database = {CLICKHOUSE_DATABASE_1:String} AND name = 't2';

DROP DATABASE {CLICKHOUSE_DATABASE_1:Identifier};
