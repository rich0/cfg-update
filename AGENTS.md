# Agent guide — cfg-update

Instructions for AI agents and contributors working on [rich0/cfg-update](https://github.com/rich0/cfg-update).

## Project context
**cfg-update** is a ~2,500-line single-host Perl tool for safely updating Gentoo `._cfg0000_*`
config files post-`emerge`. It uses a five-stage pipeline (auto-overwrite → diff3 → manual merges → binary/link handling).

- **Primary target:** single-host Gentoo + Portage
- **Paludis:** best-effort only (do not break Portage compatibility)
- **Default branch for development:** `develop` (PRs target `develop`; `master` is release-only)

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design and [docs/INVENTORY.md](docs/INVENTORY.md)
for cleanup roadmap + feature retention matrix.

## Branch workflow
All work on **topic branches** → PR to `develop`.

| Prefix     | Use when |
|------------|----------|
| `refactor/`| Cleanup, dead code, tests, staged work (`refactor/stage-*`) |
| `cleanup/` | Narrow removals/simplifications (no behavior change) |
| `feature/` | New user-visible behavior/options |

- One logical change per branch/PR
- Reference issues: `(issue #N)`
- Branch from current `develop`
- Create PR after commit
- Plans always evaluate functional test coverage
- Tests prioritize verification of files over console output
- Version bumps happen only during release preparation (see VERSIONING.md)

## Release process (maintainer only)
1. Ensure `develop` is up-to-date and tests pass.
2. Merge `develop` into `master`.
3. On `master`, run `./scripts/bump-version.sh X.Y.Z` (updates all version strings + ebuild).
4. Manually edit the new ChangeLog entry with a concise summary.
5. Commit the bump.
6. `git tag -a X.Y.Z -m "Release X.Y.Z"`
7. Push `master` + tag.
8. (Optional) Fast-forward `develop` from the new `master`.

## Prohibitions
- Do not create git tags (maintainer-only)
- Do not push to `master` directly
- No drive-by refactors or unrelated docs

## Testing (must pass without root)
```bash
perl -c cfg-update
./test/run-tests.sh --full
```
