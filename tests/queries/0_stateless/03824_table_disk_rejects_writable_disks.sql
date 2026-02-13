-- Tags: no-parallel, no-object-storage
-- Tag no-parallel - creates custom disks
-- Tag no-object-storage – uses object_storage_type = local

-- table_disk must only be allowed on read-only disks.
-- A writable plain_rewritable disk must be rejected and read-only accepted.

CREATE TABLE test_table_disk_plain_rewritable (key Int) ENGINE = MergeTree ORDER BY ()
SETTINGS table_disk = 1,
    disk = disk(
        type = object_storage,
        object_storage_type = local,
        metadata_type = plain_rewritable,
        path = 'disks/03824_test/'); -- { serverError BAD_ARGUMENTS }

CREATE TABLE test_table_disk_plain_rewritable_readonly (key Int) ENGINE = MergeTree ORDER BY ()
SETTINGS table_disk = 1,
    disk = disk(
        readonly = true,
        type = object_storage,
        object_storage_type = local,
        metadata_type = plain_rewritable,
        path = 'disks/03824_test_ro/');

DROP TABLE test_table_disk_plain_rewritable_readonly;
