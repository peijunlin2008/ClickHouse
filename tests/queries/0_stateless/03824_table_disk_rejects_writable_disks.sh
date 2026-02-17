#!/usr/bin/env bash
# Tags: no-parallel, no-object-storage
# Tag no-parallel - creates custom disks
# Tag no-object-storage - uses object_storage_type = local

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

# table_disk on a writable disk is allowed for the first table
${CLICKHOUSE_CLIENT} --query "
CREATE TABLE test_table_disk_writable_first (key Int) ENGINE = MergeTree ORDER BY ()
SETTINGS table_disk = 1,
    disk = disk(
        name = 03824_first_${CLICKHOUSE_DATABASE},
        type = object_storage,
        object_storage_type = local,
        metadata_type = plain_rewritable,
        path = 'disks/03824_${CLICKHOUSE_DATABASE}/')
"

# A second non-readonly table on the same disk must be rejected
${CLICKHOUSE_CLIENT} --query "
CREATE TABLE test_table_disk_writable_second (key Int) ENGINE = MergeTree ORDER BY ()
SETTINGS table_disk = 1,
    disk = disk(
        name = 03824_first_${CLICKHOUSE_DATABASE},
        type = object_storage,
        object_storage_type = local,
        metadata_type = plain_rewritable,
        path = 'disks/03824_${CLICKHOUSE_DATABASE}/'); -- { serverError BAD_ARGUMENTS }
"

# A readonly table on the same path is fine (readonly disks are exempt from the prefix check)
${CLICKHOUSE_CLIENT} --query "
CREATE TABLE test_table_disk_readonly_second (key Int) ENGINE = MergeTree ORDER BY ()
SETTINGS table_disk = 1,
    disk = disk(
        readonly = true,
        name = 03824_ro_${CLICKHOUSE_DATABASE},
        type = object_storage,
        object_storage_type = local,
        metadata_type = plain_rewritable,
        path = 'disks/03824_${CLICKHOUSE_DATABASE}/')
"

# Two writable tables on different disks are fine and don't collide
${CLICKHOUSE_CLIENT} --query "
CREATE TABLE test_table_disk_writable_other_disk (key Int, value String) ENGINE = MergeTree ORDER BY ()
SETTINGS table_disk = 1,
    disk = disk(
        name = 03824_other_${CLICKHOUSE_DATABASE},
        type = object_storage,
        object_storage_type = local,
        metadata_type = plain_rewritable,
        path = 'disks/03824_other_${CLICKHOUSE_DATABASE}/')
"

${CLICKHOUSE_CLIENT} --query "INSERT INTO test_table_disk_writable_first VALUES (1), (2), (3)"
${CLICKHOUSE_CLIENT} --query "INSERT INTO test_table_disk_writable_first VALUES (3), (2), (1)"
${CLICKHOUSE_CLIENT} --query "INSERT INTO test_table_disk_writable_other_disk VALUES (100, 'a'), (200, 'b')"

${CLICKHOUSE_CLIENT} --query "SELECT 'first', * FROM test_table_disk_writable_first ORDER BY key"
${CLICKHOUSE_CLIENT} --query "SELECT 'other', * FROM test_table_disk_writable_other_disk ORDER BY key"

${CLICKHOUSE_CLIENT} --query "DROP TABLE test_table_disk_writable_other_disk"
${CLICKHOUSE_CLIENT} --query "DROP TABLE test_table_disk_readonly_second"
${CLICKHOUSE_CLIENT} --query "DROP TABLE test_table_disk_writable_first"
