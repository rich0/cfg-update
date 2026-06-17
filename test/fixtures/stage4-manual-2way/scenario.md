# Stage 4 — manual 2-way merge (MF)

**Expected state:** MF (Modified File)  
**Expected stage:** 4 — manual 2-way merge

## Situation

The live file was modified, but no ancestor backup exists (first cfg-update encounter for this file). Automatic 3-way merge is impossible; cfg-update falls through to manual 2-way merge.

## Files

| File | Role |
|------|------|
| `etc/test_manual_2way` | Live config (`SETTING = custom`) |
| `etc/._cfg0000_test_manual_2way` | New default (`#version 1.1`) |
| `etc/._cfg0001_test_manual_2way` | Second pending marker (`#version 1.2`) — edge case |

The dual `._cfg0000_*` and `._cfg0001_*` markers exercise multiple pending updates on the same basename (unusual but possible with stacked package revisions).

## Index entry

```
/etc/test/test_manual_2way 0
```

No `backups/` tree — ancestor intentionally absent.

## Expected behavior

- `cfg-update -l` → Stage 4 queue, state MF, ancestor not available
- Requires interactive merge tool for `-u`