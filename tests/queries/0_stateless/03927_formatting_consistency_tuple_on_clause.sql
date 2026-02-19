-- In debug builds, the server checks AST formatting roundtrip consistency.
-- Previously, RoundBracketsLayer had a special case that promoted ((tuple_literal)) to tuple(tuple_literal),
-- but the reparsed text used ParserCollectionOfLiterals which produced ASTLiteral(Tuple) instead,
-- causing the roundtrip to fail. The fix removes the unnecessary special-case promotion.
-- https://s3.amazonaws.com/clickhouse-test-reports/json.html?REF=master&sha=a5e9d1c7da638871e8a4c99fda083c9d4dc9ffdc&name_0=MasterCI&name_1=BuzzHouse%20%28amd_debug%29

SELECT ((1), 0.648);
SELECT (((1), 0.648) AS a7);
SELECT [((1), 2), 3];
