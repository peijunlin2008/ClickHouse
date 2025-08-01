---
description: 'System table containing information about settings for MergeTree tables.'
keywords: ['system table', 'merge_tree_settings']
slug: /operations/system-tables/merge_tree_settings
title: 'system.merge_tree_settings'
---

# system.merge_tree_settings

Contains information about settings for `MergeTree` tables.

Columns:

- `name` ([String](../../sql-reference/data-types/string.md)) — Setting name.
- `value` ([String](../../sql-reference/data-types/string.md)) — Setting value.
- `default` ([String](../../sql-reference/data-types/string.md)) — Setting default value.
- `changed` ([UInt8](/sql-reference/data-types/int-uint#integer-ranges)) — Whether the setting was explicitly defined in the config or explicitly changed.
- `description` ([String](../../sql-reference/data-types/string.md)) — Setting description.
- `min` ([Nullable](../../sql-reference/data-types/nullable.md)([String](../../sql-reference/data-types/string.md))) — Minimum value of the setting, if any is set via [constraints](/operations/settings/constraints-on-settings). If the setting has no minimum value, contains [NULL](/operations/settings/formats#input_format_null_as_default).
- `max` ([Nullable](../../sql-reference/data-types/nullable.md)([String](../../sql-reference/data-types/string.md))) — Maximum value of the setting, if any is set via [constraints](/operations/settings/constraints-on-settings). If the setting has no maximum value, contains [NULL](/operations/settings/formats#input_format_null_as_default).
- `readonly` ([UInt8](/sql-reference/data-types/int-uint#integer-ranges)) — Shows whether the current user can change the setting:
  - `0` — Current user can change the setting.
  - `1` — Current user can't change the setting.
- `type` ([String](../../sql-reference/data-types/string.md)) — Setting type (implementation specific string value).
- `is_obsolete` ([UInt8](/sql-reference/data-types/int-uint#integer-ranges)) - Shows whether a setting is obsolete.
- `tier` ([Enum8](../../sql-reference/data-types/enum.md)) — Support level for this feature. ClickHouse features are organized in tiers, varying depending on the current status of their development and the expectations one might have when using them. Values:
  - `'Production'` — The feature is stable, safe to use and does not have issues interacting with other **production** features. .
  - `'Beta'` — The feature is stable and safe. The outcome of using it together with other features is unknown and correctness is not guaranteed. Testing and reports are welcome.
  - `'Experimental'` — The feature is under development. Only intended for developers and ClickHouse enthusiasts. The feature might or might not work and could be removed at any time.
  - `'Obsolete'` — No longer supported. Either it is already removed or it will be removed in future releases.

**Example**
```sql
SELECT * FROM system.merge_tree_settings LIMIT 3 FORMAT Vertical;
```

```response
SELECT *
FROM system.merge_tree_settings
LIMIT 3
FORMAT Vertical

Query id: 2580779c-776e-465f-a90c-4b7630d0bb70

Row 1:
──────
name:        min_compress_block_size
value:       0
default:     0
changed:     0
description: When granule is written, compress the data in buffer if the size of pending uncompressed data is larger or equal than the specified threshold. If this setting is not set, the corresponding global setting is used.
min:         ᴺᵁᴸᴸ
max:         ᴺᵁᴸᴸ
readonly:    0
type:        UInt64
is_obsolete: 0
tier:        Production

Row 2:
──────
name:        max_compress_block_size
value:       0
default:     0
changed:     0
description: Compress the pending uncompressed data in buffer if its size is larger or equal than the specified threshold. Block of data will be compressed even if the current granule is not finished. If this setting is not set, the corresponding global setting is used.
min:         ᴺᵁᴸᴸ
max:         ᴺᵁᴸᴸ
readonly:    0
type:        UInt64
is_obsolete: 0
tier:        Production

Row 3:
──────
name:        index_granularity
value:       8192
default:     8192
changed:     0
description: How many rows correspond to one primary key value.
min:         ᴺᵁᴸᴸ
max:         ᴺᵁᴸᴸ
readonly:    0
type:        UInt64
is_obsolete: 0
tier:        Production

3 rows in set. Elapsed: 0.001 sec. 
```
