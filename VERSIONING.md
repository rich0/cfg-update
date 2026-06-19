## Version bump checklist

When preparing a release (bump version strings; **do not tag**), sync:

| File | What to update |
|------|----------------|
| [cfg-update](cfg-update) | `$version` variable |
| [ChangeLog](ChangeLog) | New `*cfg-update-X.Y.Z` entry |
| [README.md](README.md) | Version line in header |
| [gentoo/](gentoo/) | Ebuild filename / `PV` as appropriate |
