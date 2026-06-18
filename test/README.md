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
| [`stage0-no-index`](fixtures/stage0-no-index/) | `--` | — | No `checksum.index` on disk; unknown state (Tier A only, not in combined sandbox) |
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

Integration harness: [`run-tests.sh`](run-tests.sh). Uses a temp sandbox, mock `portageq`, and `CFG_UPDATE_CONF` (no writes to `/etc`).

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
| A | `-lv` | Combined + per-scenario classify (12 markers), missing-index case, removed-flag regression (`-s`, `--move-backups`, ad-hoc diff), multi `CONFIG_PROTECT` dirs, ancestor backups on disk |
| B | `-p -au` | Stages 1–2 pretend; live files unchanged |
| C | `-au` | Stages 1–2 execute: golden file equality, binary MD5, 3-way conflict handling, stage 3 re-list |
| D | `-u` + stdin | Stages 3–5 execute (one stage enabled at a time): stage-specific output, mock 3-way merge, replace/keep filesystem outcomes |
| E | `-i` / `-i -f` | Portage `--index`: up-to-date skip, stale rebuild from mock CONTENTS, marker-blocked skip, force rebuild |
| F | `-b`, `-r`, `--optimize-backups` | Backup list/restore after stage-2 update; stage-1 backups land in `BACKUP_PATH` (not inline); optimize-backups creates `._new-cfg_*` for unmodified files |

Tier B/C/D/E/F pass `--testsandbox` with `--ebuild` so `-u`, `--index`, `-r`, and `--optimize-backups` skip the root check inside the temp sandbox.

### Golden `expected/` files

Scenarios exercised in Tier C/D include an `expected/` subdirectory with post-update reference files. Tier C compares live files with `cmp`. Tier D isolates a single manual stage per scenario (`stage3_only`, `stage4_only`, `stage5_only`), asserts stage-specific stdout (e.g. `manual 3-way merging` vs `manual updating`), and uses a mock `kdiff3` to verify 3-way merge invocation. Keys are piped to STDIN (sandbox `readkey` reads lines when stdin is not a TTY).

The harness prepends a mock `portageq` to `PATH` that returns two sandbox directories as `CONFIG_PROTECT`: `etc/test` and `etc/test2` (the latter may be empty in most scenarios). Tier A `multi CONFIG_PROTECT` deploys stage-1 fixtures into both dirs and asserts `-lv` and `-b` see files from each protected path. Ancestor backups are placed at `BACKUP_PATH` + full dirname of each marker (e.g. `{sandbox}/var/lib/cfg-update/backups{sandbox}/etc/test/`), matching cfg-update's internal path logic.

### Sandbox mode (stage 6c)

When `--testsandbox` and `--ebuild` are passed, `cfg-update -u`, `cfg-update --index`, `cfg-update -r`, and `cfg-update --optimize-backups` skip the root check so the harness and ebuild `src_test()` can run Tier B/C/D/E/F as an unprivileged user. Tier E uses mock `PKG_DB`, `INSTALL_LOG`, and `portageq` under [`fixtures/index-portage/`](fixtures/index-portage/). In the same mode, `readkey` reads from STDIN when piped (enabling Tier D and Tier F restore). `CFG_UPDATE_CONF` only selects the config file path; production `-u`/`--index`/`-r`/`--optimize-backups` still require root.

### Manual single-scenario check (Gentoo host)

```bash
SCENARIO=test/fixtures/stage1-unmodified-text
sudo cp -a "$SCENARIO/etc/." /etc/test/
# seed index/backups per scenario.md, then:
cfg-update -lv
```