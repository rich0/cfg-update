# Stage 2 — automatic 3-way merge success (MF)

**Expected state:** MF (Modified File)  
**Expected stage:** 2 — automatic diff3 merge

## Situation

The user customized the live config after the previous update. A backup ancestor (`._new-cfg_*`) exists from the last cfg-update run. The new Portage default can be merged cleanly via `diff3` without conflict markers.

## Files

| File | Role |
|------|------|
| `etc/test_auto_3way_success` | Live config (`SETTING = custom`, `#version 1.0`) |
| `etc/._cfg0000_test_auto_3way_success` | New default (`SETTING = default`, `#version 1.1`) |
| `backups/etc/test/._new-cfg_test_auto_3way_success` | Ancestor from prior update (`#version 1.0`, `SETTING = default`) |

## Index entry

```
/etc/test/test_auto_3way_success 0
```

`0` means the live file was modified since indexing (checksum no longer matches).

## Expected behavior

- `cfg-update -l` → Stage 2 queue, state MF, ancestor available
- `cfg-update -au` → diff3 produces merged file without `<<<<<<<` markers