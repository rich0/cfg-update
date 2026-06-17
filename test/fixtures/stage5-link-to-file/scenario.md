# Stage 5 — link to file (FL)

**Expected state:** FL (File to Link)  
**Expected stage:** 5 — manual investigation

## Situation

The live path is a symlink. The new Portage payload is a regular file. Opposite of file-to-link.

## Files

| File | Role |
|------|------|
| `etc/test_link_2_file` | Symlink → `link_target_before_update` |
| `etc/._cfg0000_test_link_2_file` | New regular file |
| `etc/link_target_before_update` | Former symlink target |

## Index entry

```
/etc/test/test_link_2_file 0
```

## Expected behavior

- `cfg-update -l` → Stage 5 queue, state FL