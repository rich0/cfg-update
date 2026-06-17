# Stage 5 — link to link (LL)

**Expected state:** LL (Link to Link)  
**Expected stage:** 5 — manual investigation

## Situation

Both live and new configs are symlinks, but they point to different targets (`link_target_before_update` vs `link_target_after_update`).

## Files

| File | Role |
|------|------|
| `etc/test_link_2_link` | Symlink → `link_target_before_update` |
| `etc/._cfg0000_test_link_2_link` | Symlink → `link_target_after_update` |
| `etc/link_target_before_update` | Old target |
| `etc/link_target_after_update` | New target |

## Index entry

```
/etc/test/test_link_2_link 0
```

## Expected behavior

- `cfg-update -l` → Stage 5 queue, state LL