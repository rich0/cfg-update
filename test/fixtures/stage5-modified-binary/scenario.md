# Stage 5 — modified binary (MB)

**Expected state:** MB (Modified Binary)  
**Expected stage:** 5 — manual/special handling

## Situation

The user replaced or patched the binary after installation. The index records `0` (modified). Portage dropped a new binary as `._cfg0000_*`. cfg-update cannot auto-replace modified binaries.

## Files

| File | Role |
|------|------|
| `etc/test_modified_binary` | Live binary (one byte differs from `test_unmodified_binary`) |
| `etc/._cfg0000_test_modified_binary` | New binary from Portage (same image as unmodified case) |

## Index entry

```
/etc/test/test_modified_binary 0
```

## Expected behavior

- `cfg-update -l` → Stage 5 queue, state MB
- `cfg-update -u` → requires manual handling; no automatic replace