# Stage 5 — modified binary (MB)

**Expected state:** MB (Modified Binary)  
**Expected stage:** 5 — manual/special handling

## Situation

The user replaced or patched the binary after installation. The index records `0` (modified). Modified binaries cannot be auto-replaced.

## Files

| File | Role |
|------|------|
| `etc/test_modified_binary` | Live binary (one byte differs from `test_unmodified_binary`) |

## Index entry

```
/etc/test/test_modified_binary 0
```

## Gap in original fixtures

The legacy `test.tgz` archive has **no** `._cfg0000_test_modified_binary` marker. This scenario documents the live-file state only. To exercise the full update flow, add a `._cfg0000_*` marker alongside the live binary.

## Expected behavior

- With a `._cfg*` marker present: `cfg-update -l` → Stage 5 queue, state MB
- Without a marker: file is not discovered by `find_updates`