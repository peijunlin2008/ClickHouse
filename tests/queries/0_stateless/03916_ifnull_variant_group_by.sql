-- https://github.com/ClickHouse/ClickHouse/issues/96664
SELECT ifNull(if(0, '1', 1), 1::Int8) GROUP BY 1 SETTINGS allow_suspicious_types_in_group_by = 1;
