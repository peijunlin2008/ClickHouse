"""
Test BAD_ARGUMENTS for Iceberg ORDER BY (parseTransformAndColumn in Utils.cpp).
Each case should raise when creating a table with the given order_by.
"""
import pytest

from helpers.iceberg_utils import (
    create_iceberg_table,
    get_uuid_str,
)


@pytest.mark.parametrize("format_version", [2])
@pytest.mark.parametrize("storage_type", ["s3"])
@pytest.mark.parametrize(
    "schema,order_by",
    [
        # Literal / expression instead of column or function
        ("(c0 Int)", "(1)"),
        ("(c0 Int)", "(1+1)"),
        # Unsupported function
        ("(c0 Int)", "rand(c0)"),
        ("(c0 Int)", "(now())"),
        # identity/1-arg: expected column identifier
        ("(c0 Int)", "identity(1)"),
        ("(c0 Int)", "identity(1+1)"),
        # expected 1 or 2 arguments (0 or 3+)
        ("(c0 Int)", "identity()"),
        ("(c0 Int, c1 Int)", "identity(c0, c1, c0)"),
        # 2-arg: expected (integer_literal, column_identifier)
        ("(c0 Int, c1 Int)", "icebergBucket(c0, c1)"),
        ("(c0 Int, c1 Int)", "icebergBucket(1, 2)"),
        ("(c0 Int)", "icebergBucket(c0, 1)"),
        # expected non-negative integer literal as first argument
        ("(c0 Int)", "icebergBucket(-1, c0)"),
        ("(c0 Int)", "icebergTruncate(1.5, c0)"),
        # Invalid tuple (empty)
        ("(c0 Int)", "tuple()"),
    ],
    ids=[
        "literal_order_by_1",
        "literal_order_by_1_plus_1",
        "unsupported_rand",
        "unsupported_now",
        "identity_literal_arg",
        "identity_expr_arg",
        "identity_no_args",
        "identity_three_args",
        "bucket_two_columns",
        "bucket_two_literals",
        "bucket_column_then_literal",
        "bucket_negative_param",
        "truncate_float_param",
        "tuple_empty",
    ],
)
def test_order_by_bad_arguments(
    started_cluster_iceberg_with_spark, format_version, storage_type, schema, order_by
):
    instance = started_cluster_iceberg_with_spark.instances["node1"]
    table_name = "test_order_by_bad_" + storage_type + "_" + get_uuid_str()

    with pytest.raises(Exception):
        create_iceberg_table(
            storage_type,
            instance,
            table_name,
            started_cluster_iceberg_with_spark,
            schema,
            format_version=format_version,
            order_by=order_by,
        )
