# Stage 5 — file to link (LF)

**Expected state:** LF (Link to File)  
**Expected stage:** 5 — manual investigation

## Situation

The live path is a regular file. The new Portage payload is a symlink (to `link_target_after_update`). cfg-update treats file→symlink transitions as special cases.

## Files

| File | Role |
|------|------|
| `etc/test_file_2_link` | Live regular file |
| `etc/._cfg0000_test_file_2_link` | Symlink → `link_target_after_update` |
| `etc/link_target_after_update` | Symlink target content |

## Index entry

```
/etc/test/test_file_2_link 0
```

## Expected behavior

- `cfg-update -l` → Stage 5 queue, state LF
- User must investigate; auto-replace is not offered