#!/usr/bin/env bash
# Tags: no-random-settings, no-object-storage, no-replicated-database, no-shared-merge-tree
# Tag no-random-settings: enable after root causing flakiness
# Tag no-replicated-database: plain rewritable should not be shared between replicas

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

${CLICKHOUSE_CLIENT} --query "DROP TABLE IF EXISTS writer SYNC"
${CLICKHOUSE_CLIENT} --query "DROP TABLE IF EXISTS reader SYNC"

${CLICKHOUSE_CLIENT} --query "CREATE TABLE writer (s String) ORDER BY ()"

WRITER_DATA_PATH=$(${CLICKHOUSE_CLIENT} --query "
    SELECT data_paths[1]
    FROM system.tables
    WHERE database = currentDatabase() AND name = 'writer'
")

${CLICKHOUSE_CLIENT} --query "
CREATE TABLE reader (s String) ORDER BY ()
SETTINGS table_disk = true, refresh_parts_interval = 1,
  disk = disk(
      readonly = true,
      name = 03362_reader_${CLICKHOUSE_DATABASE},
      type = object_storage,
      object_storage_type = local,
      metadata_type = plain,
      path = '${WRITER_DATA_PATH}')
"

${CLICKHOUSE_CLIENT} --query "INSERT INTO writer SELECT 'Hello'";

while true
do
    ${CLICKHOUSE_CLIENT} --query "SELECT * FROM reader" | grep -F 'Hello' && break;
    sleep 0.1;
done

${CLICKHOUSE_CLIENT} --query "DROP TABLE reader SYNC"
${CLICKHOUSE_CLIENT} --query "DROP TABLE writer SYNC"
