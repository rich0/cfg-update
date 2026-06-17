# cfg-update test fixtures

Synthetic Portage config-update scenarios extracted from the legacy [`test.tgz`](../test.tgz) archive. Each scenario lives in its own subdirectory under [`fixtures/`](fixtures/) so intent, files, and expected behavior stay together.

The original archive kept every file in a flat `test/` directory. The layout here mirrors how a harness will deploy files:

| Path within a scenario | Deployed to (sandbox) |
|------------------------|------------------------|
| `etc/*` | `{sandbox}/etc/test/` |
| `backups/etc/test/*` | `{sandbox}/var/lib/cfg-update/backups{sandbox}/etc/test/` |
| `checksum.index.entry` | Line appended to `{sandbox}/var/lib/cfg-update/checksum.index` |

Deploy with `cp -a scenario/etc/.` (not `etc/*`) so `._cfg*` dotfiles are included.

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
| [`stage5-modified-binary`](fixtures/stage5-modified-binary/) | MB | 5 | Modified binary + new `._cfg` marker; manual handling |
| [`stage5-custom-binary`](fixtures/stage5-custom-binary/) | CB | 5 | Custom binary not in index |
| [`stage5-file-to-link`](fixtures/stage5-file-to-link/) | LF | 5 | Live file → new symlink |
| [`stage5-link-to-file`](fixtures/stage5-link-to-file/) | FL | 5 | Live symlink → new regular file |
| [`stage5-link-to-link`](fixtures/stage5-link-to-link/) | LL | 5 | Symlink target changes |

## Legacy

[`fixtures/legacy/prepare_cfg-update_test`](fixtures/legacy/prepare_cfg-update_test) is the original Gentoo-host setup script. It writes to real `/etc` and `/var/lib` paths. Prefer the per-scenario layout for future harness work.

## Running tests

Integration harness: [`run-tests.sh`](run-tests.sh). Uses a temp sandbox, mock `portageq`, and `CFG_UPDATE_CONF` / `CFG_UPDATE_HOSTS` (no writes to `/etc`).

Fixture lint: [`lint-fixtures.sh`](lint-fixtures.sh) — structure, MD5 vs `checksum.index.entry`, duplicate marker detection. Invoked automatically as Tier 0.

**Requirements:** Perl (`Term::ANSIColor`, `Term::ReadKey`), `diff3`, `grep`, `find`, `md5sum`.

```bash
# From repo root — full suite (no root required)
./test/run-tests.sh

# Ebuild / CI: fail if any tier was skipped
./test/run-tests.sh --full

# Gentoo ebuild (FEATURES=test USE=test)
FEATURES=test USE=test emerge --oneshot app-portage/cfg-update
```

| Tier | What | Checks |
|------|------|--------|
| 0 | static + lint | `perl -c`, `bash -n`, optional `shellcheck`, `lint-fixtures.sh` |
| A | `-lv`, `-s` | Combined + per-scenario classify (12 markers), protected dirs, ancestor backups on disk |
| B | `-p -au` | Stages 1–2 pretend; live files unchanged |
| C | `-au` | Stages 1–2 execute: golden file equality, binary MD5, 3-way conflict handling, stage 3 re-list |
| D | `-mu` + stdin | Stages 3–5 execute: replace/keep filesystem outcomes (non-interactive via sandbox STDIN) |
| E | `-i` / `-i -f` | Portage `--index`: up-to-date skip, stale rebuild from mock CONTENTS, marker-blocked skip, force rebuild |

Tier B/C/D/E pass `--testsandbox` with `--ebuild` so `-u` and `--index` skip the root check inside the temp sandbox.

### Golden `expected/` files

Scenarios exercised in Tier C/D include an `expected/` subdirectory with post-update reference files. Tier C compares live files with `cmp`; Tier D drives manual stages by piping keys to STDIN (sandbox `readkey` reads lines when stdin is not a TTY).

The harness prepends a mock `portageq` to `PATH` that returns the sandbox `etc/test` directory as `CONFIG_PROTECT`. Ancestor backups are placed at `BACKUP_PATH` + full dirname of each marker (e.g. `{sandbox}/var/lib/cfg-update/backups{sandbox}/etc/test/`), matching cfg-update's internal path logic.

### Sandbox mode (stage 6c)

When `--testsandbox` and `--ebuild` are passed, `cfg-update -u` and `cfg-update --index` skip the root check so the harness and ebuild `src_test()` can run Tier B/C/D/E as an unprivileged user. Tier E uses mock `PKG_DB`, `INSTALL_LOG`, and `portageq` under [`fixtures/index-portage/`](fixtures/index-portage/). In the same mode, `readkey` reads from STDIN when piped (enabling Tier D). `CFG_UPDATE_CONF` only selects the config file path; production `-u`/`--index` still require root.

### Manual single-scenario check (Gentoo host)

```bash
SCENARIO=test/fixtures/stage1-unmodified-text
sudo cp -a "$SCENARIO/etc/." /etc/test/
# seed index/backups per scenario.md, then:
cfg-update -lv
```