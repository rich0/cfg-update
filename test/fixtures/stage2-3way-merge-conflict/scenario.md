# Stage 2/3 — 3-way merge conflict (MF)

**Expected state:** MF (Modified File)  
**Expected stage:** 2 attempted, then **3** if conflict markers remain

## Situation

Like the success case, but the user, ancestor, and new default disagree in ways `diff3` cannot resolve silently. cfg-update should queue this for manual 3-way merge (stage 3) after automatic merge leaves conflict markers.

## Files

| File | Role |
|------|------|
| `etc/test_auto_3way_conflict` | Live config (`SETTING = custom`, `#version 1.0`) |
| `etc/._cfg0000_test_auto_3way_conflict` | New default (`SETTING = new-default`, `#version 1.1`) |
| `backups/etc/test/._new-cfg_test_auto_3way_conflict` | Ancestor (`SETTING = default`, `#version 1.0`) |

All three versions differ on `SETTING`.

## Index entry

```
/etc/test/test_auto_3way_conflict 0
```

## Expected behavior

- `cfg-update -l` → Stage 2 queue initially (MF + ancestor, no pre-existing conflict file)
- After failed auto-merge → Stage 3 queue
- `cfg-update -au` with only stages 1–2 enabled → leaves `*.merge` with conflict markers