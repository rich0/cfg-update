# Release Process & Versioning

**cfg-update** follows semantic versioning (`X.Y.Z`).

Version bumps and releases are **release-only** activities. Do not change version strings during normal development on `develop`.

## Version consistency check

[`scripts/check-version.sh`](scripts/check-version.sh) verifies that `cfg-update`, `README.md`, and the ebuild PV all agree. It does **not** use git and is safe to run in CI, locally, and from the ebuild test phase.

```bash
./scripts/check-version.sh          # all three sources must match
./scripts/check-version.sh 1.11.0 # all three must equal 1.11.0
```

## Automated bump script

From the repo root, run:

```bash
./scripts/bump-version.sh 1.11.0
```

This updates in one step:
- `$version` variable in `cfg-update`
- `**Version:**` line in `README.md`
- Renames the ebuild via `git mv` (e.g. `gentoo/cfg-update-1.10.3.ebuild` → `gentoo/cfg-update-1.11.0.ebuild`). Exactly one ebuild should exist in `gentoo/`.
- Inserts a stub header into `ChangeLog` (after the file header block)
- Runs `check-version.sh` to verify all three version strings match the new version

ChangeLog entries added by the script use an **ISO date** in the header, e.g. `*cfg-update-1.11.0 (2026-06-19)`. Older entries may use Gentoo-style dates (`19 JUN 2026`); no backfill is required.

After running the script, **manually edit** the ChangeLog entry with a good summary, then open a release PR to `master`.

## Full release steps (maintainer)

1. On `develop`: all work merged, tests passing.
2. Create a release branch from `develop` (e.g. `release/1.11.0`).
3. On the release branch: run `./scripts/bump-version.sh 1.11.0`, polish the ChangeLog entry, and commit.
4. Open **PR: release branch → `master`** — CI runs `perl -c`, `check-version.sh`, and `./test/run-tests.sh --full`.
5. Merge the PR.
6. On `master`: tag (`git tag -a 1.11.0 -m "cfg-update 1.11.0"`), push the tag (`git push origin 1.11.0`).
7. (Optional) Create a GitHub Release from the tag.
8. (Optional) Merge `master` back into `develop` if versions diverged.

## Branch protection (rulesets)

Configure at **Settings → Rules → Rulesets → New branch ruleset**. Use rulesets only (do not also add legacy branch protection rules for the same branches). Start with enforcement status **Evaluate**, then switch to **Active** once behavior is confirmed.

### Ruleset: `protect-develop`

| Setting | Value |
|---------|-------|
| Target branches | Include by name: `develop` |
| Restrict deletions | Yes |
| Block force pushes | Yes |
| Require a pull request before merging | Yes (0 approvals OK for solo maintainer) |
| Require status checks to pass | Yes — add `integration` (may appear as `Tests / integration`) |
| Require branches to be up to date before merging | Yes |

### Ruleset: `protect-master`

| Setting | Value |
|---------|-------|
| Target branches | Include by name: `master` |
| Restrict deletions | Yes |
| Block force pushes | Yes |
| Require a pull request before merging | Yes — all changes including releases |
| Require status checks to pass | Yes — same `integration` check |
| Require branches to be up to date before merging | Yes |

**Default branch:** set to `develop` in **Settings → General** if still `master`.

### What “up to date before merging” means

This does not require rebasing on every push. It only blocks the **Merge** button when the PR branch is behind its base branch. Use **Update branch** on the PR, `git merge develop`, or `git rebase develop`, then wait for CI to pass on the updated head commit.

See [AGENTS.md](AGENTS.md) for the full contributor + branch model.
