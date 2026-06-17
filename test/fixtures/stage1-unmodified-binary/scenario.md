# Stage 1 — unmodified binary (UB)

**Expected state:** UB (Unmodified Binary)  
**Expected stage:** 1 — automatic overwrite

## Situation

Same as the text-file case, but the protected file is an ELF binary. The live binary still matches the indexed MD5. cfg-update should auto-replace it (binaries are allowed when unmodified).

## Files

| File | Role |
|------|------|
| `etc/test_unmodified_binary` | Live binary (matches index) |
| `etc/._cfg0000_test_unmodified_binary` | New binary from Portage |

## Index entry

```
/etc/test/test_unmodified_binary 6964280fbdcfa71b9bb39c07ef72f506
```

## Expected behavior

- `cfg-update -l` → Stage 1 queue, state UB
- `cfg-update -au` → replaces binary automatically