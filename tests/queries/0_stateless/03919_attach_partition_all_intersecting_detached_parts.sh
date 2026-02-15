#!/usr/bin/env bash
# Tags: no-replicated-database

# Test that ATTACH PARTITION ALL handles intersecting parts in the detached directory
# gracefully instead of throwing a LOGICAL_ERROR.
# This can happen when detached directory accumulates parts from different table states
# (e.g., from the BuzzHouse fuzzer).

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

$CLICKHOUSE_CLIENT -q "DROP TABLE IF EXISTS t_attach_intersect"

$CLICKHOUSE_CLIENT -q "
    CREATE TABLE t_attach_intersect (x UInt64)
    ENGINE = MergeTree ORDER BY x
"

# Insert several parts and merge them
$CLICKHOUSE_CLIENT -q "SYSTEM STOP MERGES t_attach_intersect"
for i in $(seq 1 5); do
    $CLICKHOUSE_CLIENT -q "INSERT INTO t_attach_intersect VALUES ($i)"
done
$CLICKHOUSE_CLIENT -q "SYSTEM START MERGES t_attach_intersect"
$CLICKHOUSE_CLIENT -q "OPTIMIZE TABLE t_attach_intersect FINAL"
$CLICKHOUSE_CLIENT -q "SYSTEM SYNC REPLICA t_attach_intersect PULL" 2>/dev/null ||:

# Insert one more part to extend the block range
$CLICKHOUSE_CLIENT -q "INSERT INTO t_attach_intersect VALUES (6)"
# Now we have merged part all_1_5_N and a new part all_6_6_0

# Detach everything to populate the detached directory
$CLICKHOUSE_CLIENT -q "ALTER TABLE t_attach_intersect DETACH PARTITION ALL"

# Get the data directory path
data_dir=$($CLICKHOUSE_CLIENT -q "
    SELECT arrayJoin(data_paths) FROM system.tables
    WHERE database = currentDatabase() AND name = 't_attach_intersect'" | head -1)

# Find the merged part (e.g., all_1_5_4) and copy it with a modified name
# to create an intersecting part (wider range, lower level).
# For example, copy all_1_5_4 to all_1_6_0.
# all_1_5_4 and all_1_6_0 intersect because:
# - all_1_6_0 covers a wider block range (1-6 vs 1-5)
# - all_1_6_0 has a lower level (0 vs 4)
# So neither contains the other, and they are not disjoint.
for d in "${data_dir}detached/"all_*; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    # Find the merged part (level > 0, covering multiple blocks)
    if [[ $n =~ ^all_([0-9]+)_([0-9]+)_([0-9]+)$ ]]; then
        min_block=${BASH_REMATCH[1]}
        max_block=${BASH_REMATCH[2]}
        level=${BASH_REMATCH[3]}
        if [ "$level" -gt 0 ] && [ "$min_block" -ne "$max_block" ]; then
            # Create an intersecting part: wider range, level 0
            new_max=$((max_block + 1))
            new_name="all_${min_block}_${new_max}_0"
            cp -r "$d" "${data_dir}detached/${new_name}"
            break
        fi
    fi
done

# ATTACH PARTITION ALL should handle intersecting parts gracefully
$CLICKHOUSE_CLIENT -q "ALTER TABLE t_attach_intersect ATTACH PARTITION ALL"

# Verify we got data back
$CLICKHOUSE_CLIENT -q "SELECT count() > 0 FROM t_attach_intersect"

$CLICKHOUSE_CLIENT -q "DROP TABLE t_attach_intersect"
