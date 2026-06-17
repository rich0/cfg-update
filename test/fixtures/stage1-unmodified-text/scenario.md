# Stage 1 — unmodified text file (UF)

**Expected state:** UF (Unmodified File)  
**Expected stage:** 1 — automatic overwrite

## Situation

The live config still matches the MD5 recorded in the checksum index at install time. Portage dropped a new default as `._cfg0000_*`. cfg-update should replace the live file without user interaction.

## Files

| File | Role |
|------|------|
| `etc/test_unmodified_file` | Live config (`#version 1.0`, `SETTING = default`) |
| `etc/._cfg0000_test_unmodified_file` | New default from Portage (`#version 1.1`) |

## Index entry

```
/etc/test/test_unmodified_file e2dda9550032d229538e6ae35652ca6d
```

The live file MD5 matches this value.

## Expected behavior

- `cfg-update -l` → Stage 1 queue, state UF
- `cfg-update -au` → replaces live file with new default, removes `._cfg*` marker