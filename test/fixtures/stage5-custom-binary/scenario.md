# Stage 5 — custom binary (CB)

**Expected state:** CB (Custom Binary)  
**Expected stage:** 5 — manual/special handling

## Situation

A user-placed binary at a path Portage now manages. Not in the checksum index (same idea as custom file, but `-B` test applies).

## Files

| File | Role |
|------|------|
| `etc/test_custom_binary` | User binary (not indexed) |
| `etc/._cfg0000_test_custom_binary` | New binary from Portage |

## Index entry

None. Omitted in the original `prepare_cfg-update_test` script.

## Expected behavior

- `cfg-update -l` → Stage 5 queue, state CB
- Replace requires explicit user confirmation