-- Test that CAST with nullable_source propagation through nested types
-- (Array, Map, Tuple) does not cause "ColumnNullable is not compatible with original".
-- https://s3.amazonaws.com/clickhouse-test-reports/json.html?PR=96894&sha=20e3ac9e9d7a4790a81b166af49e932202510e1e&name_0=PR&name_1=BuzzHouse%20%28amd_debug%29

SET allow_experimental_nullable_tuple_type = 1;
SET allow_suspicious_types_in_order_by = 1;

DROP TABLE IF EXISTS t_cast_nested;

CREATE TABLE t_cast_nested
(
    c0 Date,
    c1 Int32,
    c2 Date32,
    c3 Array(Nullable(Tuple(Map(String, Nullable(Enum8('a' = 1, 'b' = 2))))))
) ENGINE = MergeTree ORDER BY c0;

INSERT INTO t_cast_nested (c0, c2, c1, c3)
SELECT
    CAST(number AS Date),
    CAST(number AS Int32),
    '1911-11-24'::Date32,
    [NULL, (map('a', NULL, 'b', 'a'),)]
FROM numbers(10);

SELECT count() FROM t_cast_nested;

DROP TABLE t_cast_nested;
