# Agent guide — cfg-update

Instructions for AI agents and contributors working on [rich0/cfg-update](https://github.com/rich0/cfg-update).

## Project context
**cfg-update** is a ~2,500-line single-host Perl tool for safely updating Gentoo `._cfg0000_*`
config files post-`emerge`. It uses a five-stage pipeline (auto-overwrite → diff3 → manual merges → binary/link handling).

- **Primary target:** single-host Gentoo + Portage
- **Paludis:** best-effort only (do not break Portage compatibility)
- **Default branch:** `master` (integration only — never push directly unless maintainer-approved)

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design and [docs/INVENTORY.md](docs/INVENTORY.md)
for cleanup roadmap + feature retention matrix.

## Branch workflow
All work on **topic branches** → PR to `master`.

| Prefix     | Use when |
|------------|----------|
| `refactor/`| Cleanup, dead code, tests, staged work (`refactor/stage-*`) |
| `cleanup/` | Narrow removals/simplifications (no behavior change) |
| `feature/` | New user-visible behavior/options |

- One logical change per branch/PR
- Reference issues: `(issue #N)`
- Branch from current `master`
- Create PR after commit
- Plans always evaluate functional test coverage
- Tests prioritize verification of files over console output
- Check git tag and bump version if current version is tagged on any change (see VERSIONING.md)
- After version bump update changelog with concise summary

## Prohibitions
- Do not create git tags (maintainer-only)
- Do not push to `master` directly
- No drive-by refactors or unrelated docs

## Testing (must pass without root)
```bash
perl -c cfg-update
./test/run-tests.sh --full
```
