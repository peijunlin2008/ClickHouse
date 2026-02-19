-- In debug builds, the server checks AST formatting roundtrip consistency.
-- Previously, RoundBracketsLayer created ASTFunction("tuple") for all-literal tuples like (1, 0.648),
-- while ParserCollectionOfLiterals created ASTLiteral(Tuple) for the same syntax on reparse,
-- breaking the roundtrip. The fix removes the fast-path literal parsers from expression operand parsing,
-- so all tuples/arrays consistently go through RoundBracketsLayer/ArrayLayer.
-- https://s3.amazonaws.com/clickhouse-test-reports/json.html?REF=master&sha=a5e9d1c7da638871e8a4c99fda083c9d4dc9ffdc&name_0=MasterCI&name_1=BuzzHouse%20%28amd_debug%29

SELECT ((1), 0.648);
SELECT (((1), 0.648) AS a7);
SELECT [((1), 2), 3];
