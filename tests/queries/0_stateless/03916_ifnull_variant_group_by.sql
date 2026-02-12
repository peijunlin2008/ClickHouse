-- https://github.com/ClickHouse/ClickHouse/issues/96664

-- ifNull with Variant produced by if() with incompatible types, used in GROUP BY (the original crash)
SELECT ifNull(if(0, '1', 1), 1::Int8) GROUP BY 1 SETTINGS allow_suspicious_types_in_group_by = 1;

-- Check the result type: should be Variant(Int8, String, UInt8) since ifNull must include the alternative type
SELECT toTypeName(ifNull(if(0, '1', 1), 1::Int8));

-- ifNull where the alternative type is already present in the Variant
SELECT toTypeName(ifNull(if(0, '1', 1), 'hello'));

-- ifNull with Variant and a completely different alternative type
SELECT toTypeName(ifNull(if(0, '1', 1), toFloat64(3.14)));

-- coalesce with Variant (same underlying issue)
SELECT coalesce(if(0, '1', 1), 1::Int8) GROUP BY 1 SETTINGS allow_suspicious_types_in_group_by = 1;

-- coalesce result type with Variant
SELECT toTypeName(coalesce(if(0, '1', 1), 1::Int8));

-- coalesce with multiple Variant-producing arguments
SELECT toTypeName(coalesce(if(0, '1', 1), if(0, toDate('2024-01-01'), 3.14)));

-- ifNull with non-nullable first arg (should be identity)
SELECT ifNull(42, 100);

-- ifNull with NULL first arg
SELECT ifNull(NULL, 'fallback');

-- ifNull with Nullable
SELECT ifNull(CAST(NULL AS Nullable(Int32)), 123);

-- coalesce basic cases still work
SELECT coalesce(NULL, NULL, 42);
SELECT coalesce(NULL, 'hello', 42);

-- ifNull producing Variant from Nullable and incompatible alternative
SELECT toTypeName(ifNull(CAST(1 AS Nullable(Int8)), 'hello'));

-- coalesce producing Variant from incompatible types
SELECT toTypeName(coalesce(CAST(NULL AS Nullable(Int8)), 'hello'));
