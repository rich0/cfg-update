# Stage 4 — custom file (CF)

**Expected state:** CF (Custom File)  
**Expected stage:** 4 — manual handling (replace not allowed by default)

## Situation

The live file was never installed by Portage — it was created by an application script. It does not appear in the checksum index. Portage now ships a default for the same path.

## Files

| File | Role |
|------|------|
| `etc/test_custom_file` | User-created config (not in index) |
| `etc/._cfg0000_test_custom_file` | New Portage default |

## Index entry

None. The original `prepare_cfg-update_test` script deliberately omitted this path (commented out).

## Expected behavior

- `cfg-update -l` → Stage 4 queue, state CF
- User must choose keep/replace/merge manually; automatic replace is not offered