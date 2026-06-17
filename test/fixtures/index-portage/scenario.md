# Index — Portage `--index` rebuild (Tier E)

**Package manager:** Portage only  
**Purpose:** Exercise `check_index` / `build_index` against mock `emerge.log` and `CONTENTS`.

## Files

| File | Role |
|------|------|
| `etc/test_unmodified_file` | Live config indexed by CONTENTS |
| `var/db/pkg/app-test/test-pkg-1.0/CONTENTS.template` | `obj @SANDBOX@/etc/test/test_unmodified_file {md5}` |
| `emerge.log.current` | Last emerge timestamp `1690000000` |
| `emerge.log.stale` | Older emerge timestamp `1000000000` |
| `checksum.index.current` | Golden index after rebuild (`Portage:1690000000`) |
| `checksum.index.stale` | Stale index header + wrong MD5 body |

Paths use `@SANDBOX@` placeholder; the harness substitutes the temp sandbox path at deploy time.

## Expected behavior (Tier E)

| Case | Condition | Result |
|------|-----------|--------|
| E1 | Index ts matches emerge.log | Skip rebuild |
| E2 | Stale index, no `._cfg*` markers | Rebuild from CONTENTS |
| E3 | Stale index + pending marker | Skip rebuild (markers block) |
| E4 | E3 + `--force` | Rebuild anyway |
| E5 | After E2 rebuild | `-lv` shows Stage 1 UF for live file |