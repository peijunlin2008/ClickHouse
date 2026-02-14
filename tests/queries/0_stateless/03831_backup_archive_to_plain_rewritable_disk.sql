-- Tags: no-fasttest, no-encrypted-storage
-- Backup with an archive extension to a plain_rewritable disk.
-- The archive format causes root_path to be empty (parent_path of "name.zip"),
-- which previously led to stack overflow during cleanup by traversing the entire disk.

DROP TABLE IF EXISTS t_backup_archive_plain SYNC;

CREATE TABLE t_backup_archive_plain (x Int32) ENGINE = MergeTree ORDER BY x;
INSERT INTO t_backup_archive_plain SELECT number FROM numbers(100);

BACKUP TABLE t_backup_archive_plain TO Disk('disk_s3_plain_rewritable_03517', '03831_backup.zip') SETTINGS id = '03831_backup' FORMAT Null;

DROP TABLE IF EXISTS t_restore_archive_plain SYNC;
RESTORE TABLE t_backup_archive_plain AS t_restore_archive_plain FROM Disk('disk_s3_plain_rewritable_03517', '03831_backup.zip') SETTINGS id = '03831_restore' FORMAT Null;

SELECT count(), sum(x) FROM t_restore_archive_plain;

DROP TABLE t_restore_archive_plain SYNC;
DROP TABLE t_backup_archive_plain SYNC;
