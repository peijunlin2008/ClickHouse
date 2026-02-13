-- Tags: no-random-merge-tree-settings

DROP TABLE IF EXISTS t0;
CREATE TABLE t0 (c0 Int) ENGINE = MergeTree() ORDER BY (1 = ANY(SELECT 1)); -- { serverError BAD_ARGUMENTS }
CREATE TABLE t0 (c0 Int) ENGINE = MergeTree() ORDER BY (c0 IN (SELECT 1)); -- { serverError BAD_ARGUMENTS }
CREATE TABLE t0 (c0 Int) ENGINE = MergeTree() PARTITION BY (1 IN (SELECT 1)) ORDER BY c0; -- { serverError BAD_ARGUMENTS }
CREATE TABLE t0 (c0 Int) ENGINE = MergeTree() ORDER BY c0 PRIMARY KEY (c0 IN (SELECT 1)); -- { serverError BAD_ARGUMENTS }
