# Stage 0 — missing checksum index (unknown state)

**Expected state:** `--` (No index found)  
**Expected stage:** none — marker is not routed when the index file is absent

## Situation

A `._cfg0000_*` marker exists but `checksum.index` is not present on disk. In harness mode (`--ebuild --testsandbox`), cfg-update does not exit early; `determine_state` classifies the live file as unknown. Normal `-lv` output does not list the marker (no stage queue matches `--`).

## Files

| File | Role |
|------|------|
| `etc/test_no_index_file` | Live config |
| `etc/._cfg0000_test_no_index_file` | Pending update marker |

## Expected behavior

- `cfg-update -d -lv` → debug shows `State of the current file : No index found`
- `cfg-update -lv` → marker not listed under any `Stage[N]`
- `cfg-update -au` → `<< Stage1 >> … not found, skipping`