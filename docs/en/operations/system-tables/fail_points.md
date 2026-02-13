---
title: 'system.fail_points'
slug: '/en/operations/system-tables/fail_points'
description: 'Contains a list of all available failpoints with their type and current status.'
keywords: ['system table', 'fail_points', 'failpoint', 'testing', 'debug']
doc_type: 'reference'
---

# system.fail_points {#fail_points}

Contains a list of all available failpoints registered in the server, along with their type and whether they are currently enabled.

:::note
This table is only available in debug builds (i.e., when `NDEBUG` is not defined). It will not exist in release builds.
:::

Failpoints can be enabled and disabled at runtime using the [`SYSTEM ENABLE FAILPOINT`](/docs/en/sql-reference/statements/system#enable-failpoint) and [`SYSTEM DISABLE FAILPOINT`](/docs/en/sql-reference/statements/system#disable-failpoint) statements.

## Columns {#columns}

- `name` ([String](/docs/en/sql-reference/data-types/string.md)) — Name of the failpoint.
- `type` ([Enum8](/docs/en/sql-reference/data-types/enum.md)) — Type of the failpoint. Possible values:
  - `'once'` — Triggers a single time and then auto-disables.
  - `'regular'` — Triggers every time the failpoint is hit.
  - `'pauseable_once'` — Blocks execution once until explicitly resumed.
  - `'pauseable'` — Blocks execution every time the failpoint is hit until explicitly resumed.
- `enabled` ([UInt8](/docs/en/sql-reference/data-types/int-uint.md)) — Whether the failpoint is currently enabled. `1` means enabled, `0` means disabled.

## Example {#example}

```sql
SELECT * FROM system.fail_points WHERE enabled = 1
```

```text
┌─name──────────────────────────────────┬─type────┬─enabled─┐
│ replicated_merge_tree_commit_zk_fail  │ once    │       1 │
└───────────────────────────────────────┴─────────┴─────────┘
```

## See Also {#see-also}

- [SYSTEM ENABLE FAILPOINT](/docs/en/sql-reference/statements/system#enable-failpoint)
- [SYSTEM DISABLE FAILPOINT](/docs/en/sql-reference/statements/system#disable-failpoint)
- [SYSTEM WAIT FAILPOINT](/docs/en/sql-reference/statements/system#wait-failpoint)
