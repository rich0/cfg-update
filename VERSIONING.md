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
- Creates the new ebuild `gentoo/cfg-update-1.11.0.ebuild` (copied from the latest)
- Adds a stub header to `ChangeLog`

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
