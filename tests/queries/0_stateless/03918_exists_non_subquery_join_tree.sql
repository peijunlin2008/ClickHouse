-- Regression test: `exists` with a subquery containing invalid expressions should not cause
-- a LOGICAL_ERROR (exception in debug builds) during error message formatting.
-- The issue was that when the Analyzer detected an invalid node type in the join tree,
-- formatting the error message via `toAST` would trigger a secondary LOGICAL_ERROR in
-- `addTableExpressionOrJoinIntoTablesInSelectQuery`.
-- https://s3.amazonaws.com/clickhouse-test-reports/json.html?PR=96790&sha=cbdee8ffcd02bf966e588b7d06f2e39718da5486&name_0=PR&name_1=AST%20fuzzer%20%28amd_debug%29

SET mutations_execute_nondeterministic_on_initiator = 1;
SET allow_nondeterministic_mutations = 1;

DROP TABLE IF EXISTS t_exists_join_tree;
CREATE TABLE t_exists_join_tree (k UInt64, v UInt64) ENGINE = MergeTree ORDER BY k;
INSERT INTO t_exists_join_tree VALUES (1, 1);

-- This fuzzed query previously produced a logical error exception in debug builds.
-- It should not produce any logical errors.
ALTER TABLE t_exists_join_tree UPDATE v = now(and(isNull(materialize(toNullable(toUInt128(exists((SELECT 1023 WHERE isNotNull(3) GROUP BY GROUPING SETS ((and(*, assumeNotNull(isNotNull(3))))) HAVING and(toNullable(1)))), 3)))), *)) WHERE NULL;

SELECT * FROM t_exists_join_tree;

DROP TABLE IF EXISTS t_exists_join_tree;
