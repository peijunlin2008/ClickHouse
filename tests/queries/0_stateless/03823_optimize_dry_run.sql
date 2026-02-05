-- Tags: no-shared-merge-tree
-- no-shared-merge-tree: OPTIMIZE DRY RUN modifies local merge state, not compatible with shared MergeTree

SET optimize_on_insert = 0;

DROP TABLE IF EXISTS t_dry_run;

CREATE TABLE t_dry_run (key UInt64, value String) ENGINE = MergeTree ORDER BY key;

-- Insert 3 separate batches to create 3 parts.
INSERT INTO t_dry_run VALUES (1, 'a'), (2, 'b');
INSERT INTO t_dry_run VALUES (3, 'c'), (4, 'd');
INSERT INTO t_dry_run VALUES (5, 'e'), (6, 'f');

SELECT 'parts before dry run';
SELECT name, rows FROM system.parts WHERE database = currentDatabase() AND table = 't_dry_run' AND active ORDER BY name;

SELECT 'data before dry run';
SELECT * FROM t_dry_run ORDER BY key;

-- Get part names and run DRY RUN on the first two parts.
-- We use a subquery trick: build the OPTIMIZE statement dynamically isn't easy in .sql tests,
-- so we rely on well-known part naming for non-partitioned MergeTree: all_1_1_0, all_2_2_0, all_3_3_0.
OPTIMIZE TABLE t_dry_run DRY RUN PARTS 'all_1_1_0', 'all_2_2_0', 'all_3_3_0';

-- After DRY RUN, parts must remain unchanged: no merge committed.
SELECT 'parts after dry run';
SELECT name, rows FROM system.parts WHERE database = currentDatabase() AND table = 't_dry_run' AND active ORDER BY name;

SELECT 'data after dry run';
SELECT * FROM t_dry_run ORDER BY key;

-- A real OPTIMIZE should still work after the dry run.
OPTIMIZE TABLE t_dry_run FINAL;

SELECT 'parts after real optimize';
SELECT name, rows FROM system.parts WHERE database = currentDatabase() AND table = 't_dry_run' AND active ORDER BY name;

SELECT 'data after real optimize';
SELECT * FROM t_dry_run ORDER BY key;

-- Error: non-existent part.
OPTIMIZE TABLE t_dry_run DRY RUN PARTS 'nonexistent_part'; -- { serverError BAD_DATA_PART_NAME }

-- Error: incompatible with FINAL.
OPTIMIZE TABLE t_dry_run DRY RUN PARTS 'all_1_1_0' FINAL; -- { serverError BAD_ARGUMENTS }

-- Error: incompatible with PARTITION.
OPTIMIZE TABLE t_dry_run PARTITION tuple() DRY RUN PARTS 'all_1_1_0'; -- { serverError BAD_ARGUMENTS }

DROP TABLE t_dry_run;

-- Error: non-MergeTree engine.
DROP TABLE IF EXISTS t_dry_run_memory;
CREATE TABLE t_dry_run_memory (key UInt64) ENGINE = Memory;
OPTIMIZE TABLE t_dry_run_memory DRY RUN PARTS 'some_part'; -- { serverError BAD_ARGUMENTS }
DROP TABLE t_dry_run_memory;
