# Release Process & Versioning

**cfg-update** follows semantic versioning (`X.Y.Z`).

Version bumps and releases are **release-only** activities. Do not change version strings during normal development on `develop`.

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
- Verifies all three version strings match the new version before finishing

ChangeLog entries added by the script use an **ISO date** in the header, e.g. `*cfg-update-1.11.0 (2026-06-19)`. Older entries may use Gentoo-style dates (`19 JUN 2026`); no backfill is required.

After running the script, **manually edit** the ChangeLog entry with a good summary, then commit + tag on `master`.

## Full release steps (maintainer)

1. On `develop`: all work merged, tests passing.
2. Merge/rebase `develop` into `master`.
3. Switch to `master` and run the bump script for the new version.
4. Polish the ChangeLog entry.
5. Commit (`git commit -m "Release X.Y.Z"`).
6. Tag (`git tag -a X.Y.Z -m "cfg-update X.Y.Z"`).
7. Push (`git push origin master X.Y.Z`).
8. (Optional) Create GitHub Release from the tag.

See [AGENTS.md](AGENTS.md) for the full contributor + branch model.