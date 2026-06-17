# cfg-update test fixtures

Synthetic Portage config-update scenarios extracted from the legacy [`test.tgz`](../test.tgz) archive. Each scenario lives in its own subdirectory under [`fixtures/`](fixtures/) so intent, files, and expected behavior stay together.

The original archive kept every file in a flat `test/` directory. The layout here mirrors how a harness will deploy files:

| Path within a scenario | Deployed to (sandbox) |
|------------------------|------------------------|
| `etc/*` | `{sandbox}/etc/test/` |
| `backups/etc/test/*` | `{sandbox}/var/lib/cfg-update/backups{sandbox}/etc/test/` |
| `checksum.index.entry` | Line appended to `{sandbox}/var/lib/cfg-update/checksum.index` |

Combine all scenarios with [`fixtures/checksum.index.seed`](fixtures/checksum.index.seed) for a full index, or use per-scenario entries when testing in isolation.

## Scenarios

| Directory | State | Stage | Summary |
|-----------|-------|-------|---------|
| [`stage1-unmodified-text`](fixtures/stage1-unmodified-text/) | UF | 1 | Live file matches index MD5; auto-replace |
| [`stage1-unmodified-binary`](fixtures/stage1-unmodified-binary/) | UB | 1 | Unmodified binary; auto-replace |
| [`stage2-3way-merge-success`](fixtures/stage2-3way-merge-success/) | MF | 2 | Modified file + ancestor backup; diff3 merges cleanly |
| [`stage2-3way-merge-conflict`](fixtures/stage2-3way-merge-conflict/) | MF | 3 | Modified file + ancestor; diff3 leaves conflict markers |
| [`stage4-manual-2way`](fixtures/stage4-manual-2way/) | MF | 4 | Modified file, no ancestor; manual 2-way merge |
| [`stage4-custom-file`](fixtures/stage4-custom-file/) | CF | 4 | File not in index (user-created); manual handling |
| [`stage5-modified-binary`](fixtures/stage5-modified-binary/) | MB | 5 | Modified binary (see scenario note — no `._cfg` marker) |
| [`stage5-custom-binary`](fixtures/stage5-custom-binary/) | CB | 5 | Custom binary not in index |
| [`stage5-file-to-link`](fixtures/stage5-file-to-link/) | LF | 5 | Live file → new symlink |
| [`stage5-link-to-file`](fixtures/stage5-link-to-file/) | FL | 5 | Live symlink → new regular file |
| [`stage5-link-to-link`](fixtures/stage5-link-to-link/) | LL | 5 | Symlink target changes |

## Legacy

[`fixtures/legacy/prepare_cfg-update_test`](fixtures/legacy/prepare_cfg-update_test) is the original Gentoo-host setup script. It writes to real `/etc` and `/var/lib` paths. Prefer the per-scenario layout for future harness work.

## Running tests

Integration harness: [`run-tests.sh`](run-tests.sh). Uses a temp sandbox, mock `portageq`, and `CFG_UPDATE_CONF` (no writes to `/etc`).

**Requirements:** Perl (`Term::ANSIColor`, `Term::ReadKey`), `diff3`, `grep`, `find`.

```bash
# From repo root — Tier A only (no root)
./test/run-tests.sh

# Full suite including auto-update execute tests (Tier B/C)
sudo ./test/run-tests.sh

# Or via cfg-update --test (same harness)
./cfg-update --test
```

| Tier | Flags | Privilege | Checks |
|------|-------|-----------|--------|
| A | `-lv` | user | All fixtures classified to expected stage |
| B | `-p -au` | root | Stages 1–2 pretend; files unchanged |
| C | `-au` | root | Stage 1 replace + stage 2 diff3 merge |

The harness prepends a mock `portageq` to `PATH` that returns the sandbox `etc/test` directory as `CONFIG_PROTECT`. Ancestor backups are placed at `BACKUP_PATH` + full dirname of each marker (e.g. `{sandbox}/var/lib/cfg-update/backups{sandbox}/etc/test/`), matching cfg-update's internal path logic.

### Manual single-scenario check (Gentoo host)

```bash
SCENARIO=test/fixtures/stage1-unmodified-text
sudo cp -a "$SCENARIO/etc/." /etc/test/
# seed index/backups per scenario.md, then:
cfg-update -lv
```