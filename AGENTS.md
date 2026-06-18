# Agent guide — cfg-update

Instructions for AI agents and contributors working on [rich0/cfg-update](https://github.com/rich0/cfg-update).

## Project context

**cfg-update** is a single-host Perl program (~2,500 lines) that safely updates Gentoo configuration files after `emerge`. It classifies pending `._cfg0000_*` markers and routes each file through a five-stage pipeline (automatic overwrite, automatic diff3, manual 3-way, manual 2-way, manual binary/link handling).

This fork is being revived conservatively: trim dead/legacy code, fix obvious bugs, and expand sandbox tests. A future Python port is out of scope unless explicitly requested.

- **Primary target:** single-host Gentoo with Portage
- **Paludis:** best-effort only; do not break, but Portage is the priority
- **Default branch:** `master` (integration branch — do not commit here directly except when the maintainer says so)

For internal design, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). For the cleanup roadmap and feature retention matrix, see [docs/INVENTORY.md](docs/INVENTORY.md).

## Branch workflow

All work happens on **topic branches**. Open a PR to merge into `master`.

| Prefix | Use when |
|--------|----------|
| `refactor/` | Code cleanup, dead-code removal, test harness work, staged milestones (`refactor/stage-*`) |
| `cleanup/` | Narrow removals or simplifications that do not change behavior |
| `feature/` | New user-visible behavior or options |

**Examples from this repo:** `refactor/stage-6-tests`, `refactor/prune-sshfs`, `refactor/statenames`

**Flow:**

1. Branch from current `master`
2. One logical change per branch/PR
3. Reference GitHub issues in commits when applicable: `(issue #N)`
4. Open PR → review → merge

## Prohibitions

- **Do not create git tags.** Tagging releases is maintainer-only.
- **Do not push to `master` directly** (unless the maintainer explicitly allows it for a specific change).
- **Do not add drive-by refactors** or markdown/docs the task did not ask for.
- **Do not reintroduce removed features** (sshfs multi-host, emerge wrappers, `--test` stub, `-s`/`--move-backups`, etc.) — see the feature retention matrix in [docs/INVENTORY.md](docs/INVENTORY.md).

## Testing

All tests must run **without root**. From the repo root:

```bash
perl -c cfg-update
./test/run-tests.sh
./test/run-tests.sh --full   # ebuild/CI parity — required for release-bound changes
```

**Harness:** [test/run-tests.sh](test/run-tests.sh) — see [test/README.md](test/README.md) for fixture layout, tier breakdown, and sandbox details.

**When changing behavior**, update or add fixtures under [test/fixtures/](test/fixtures/):

- `scenario.md` — intent and expected stage/state
- `etc/`, optional `backups/`, `checksum.index.entry`
- `expected/` — post-update reference files where applicable
- [test/lint-fixtures.sh](test/lint-fixtures.sh) runs automatically in Tier 0

**Test philosophy:** Prefer assertions that verify **functionality** (filesystem outcomes, stage routing, merge-tool invocation, index rebuild behavior) over stdout-only checks. Output matching is fine as a supplement, not the sole signal.

**Ebuild parity:** The vendored ebuild under [gentoo/](gentoo/) runs `./test/run-tests.sh --full` in `src_test()` when `USE=test`.

## ChangeLog

Update [ChangeLog](ChangeLog) at the **top** for user-visible changes, using Gentoo ebuild changelog format:

```
*cfg-update-VERSION (DD MMM YYYY)

  Summary of change (issue #N if applicable).
```

- Keep the version in sync with the `$version` variable near the top of [cfg-update](cfg-update).
- When making changes, **increment the version** if the current version corresponds to an already-tagged release.
- Purely internal or test-only changes may omit a ChangeLog entry unless a release note is expected.

## Version bump checklist

When preparing a release (bump version strings; **do not tag**), sync:

| File | What to update |
|------|----------------|
| [cfg-update](cfg-update) | `$version` variable |
| [ChangeLog](ChangeLog) | New `*cfg-update-X.Y.Z` entry |
| [README.md](README.md) | Version line in header |
| [gentoo/](gentoo/) | Ebuild filename / `PV` as appropriate |

## Documentation map

Update these when behavior changes:

| Document | Update when |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Internal flow, hooks, indexing, stage logic |
| [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) | New system/Perl deps or test requirements |
| [docs/INVENTORY.md](docs/INVENTORY.md) | Large-scope characterization / roadmap status |
| [cfg-update.8](cfg-update.8) | CLI flags, runmodes, user-facing behavior |
| [cfg-update.conf](cfg-update.conf) | New or changed config knobs |
| [README.md](README.md) | Install, quick-start, or command changes |
| [test/README.md](test/README.md) | New fixture scenarios or harness tiers |

## Code style and scope

- Match existing Perl/bash style in [cfg-update](cfg-update) and test scripts.
- Prefer **minimal, focused diffs** — one concern per branch.
- Be **conservative** when removing code; verify with tests and the inventory matrix before deleting paths that look unused.
- Link related GitHub issues in commits and ChangeLog entries.

## Key entry points

| Path | Role |
|------|------|
| [cfg-update](cfg-update) | Main program |
| [cfg-update.conf](cfg-update.conf) | Config template |
| [cfg-update_indexing](cfg-update_indexing) | Paludis hook source |
| [test/run-tests.sh](test/run-tests.sh) | Integration harness |
| [gentoo/](gentoo/) | Vendored ebuild |