# DISCLAIMER / WARNING

I'm in the process of using an LLM to clean up some of the dead code branches here.
I'm being conservative, but please use care before using the 1.9.0+ releases.  
Feedback is welcome.

# cfg-update

A safe, staged alternative to Gentoo's `etc-update` for handling configuration file updates after package merges.

**Version:** 9.9.9
**License:** GPL-2 ([COPYING](COPYING))

## Description

When Portage installs a package that updates a protected config file, it leaves a `._cfg0000_*` marker beside the live config. `cfg-update` finds those pending updates and routes each file through a staged pipeline — automatic overwrites and merges first, then interactive resolution for anything that still needs attention.

## Key features

- Automatic updates for configs whose checksum still matches the install-time index
- Automatic 3-way merge when a backup from a prior update exists
- GUI or CLI merge tool support (`MERGE_TOOL` in `/etc/cfg-update.conf`)
- Enable or disable each stage individually; `-a` runs automatic stages only (handy for cron)
- `-p` pretend mode to preview actions without changing files

| Stage | Mode | Behavior |
|-------|------|----------|
| 1 | Automatic | Overwrite files whose MD5 still matches the install-time checksum |
| 2 | Automatic | 3-way `diff3` merge when a backup from a prior update exists |
| 3 | Manual | Resolve merge conflicts in your chosen diff/merge tool |
| 4 | Manual | 2-way merge for files never updated by cfg-update before |
| 5 | Manual | Binaries, symlinks, and other special cases |

## Installation

```bash
emerge app-portage/cfg-update
```

On first run, `cfg-update` installs a Portage hook in `/etc/portage/bashrc` that rebuilds the checksum index before each emerge. Set your preferred merge tool in `/etc/cfg-update.conf` (default: `meld`). See [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) for optional packages.

This repository tracks the maintained fork; Gentoo's tree may package an older release.

| Path | Purpose |
|------|---------|
| `/etc/cfg-update.conf` | Merge tool, stage toggles, backup/index paths |
| `/var/lib/cfg-update/checksum.index` | MD5 index of protected files |
| `/var/lib/cfg-update/backups/` | Per-update backups for 3-way merging |

A template config file is in this repository: [`cfg-update.conf`](cfg-update.conf).

## Basic use

```bash
cfg-update -l          # list pending config updates
sudo cfg-update -u     # interactive update session
sudo cfg-update -p -u  # preview without making changes
sudo cfg-update -au    # automatic stages only (suitable for cron)
```

After `emerge`, if new `._cfg0000_*` files appear, run `cfg-update -u` before the next emerge when possible — the checksum index cannot refresh while pending updates exist.

For the full option list, run `cfg-update --help` or `man cfg-update`.

## Contact and contributing

Report bugs and request features on the [GitHub issue tracker](https://github.com/rich0/cfg-update/issues). Pull requests are welcome.

## Acknowledgements

- **Original author:** Stephan van Boven (Gentoo, 2007)
- **Fork maintenance:** [rich0](https://github.com/rich0)
- **Community:** Gentoo proxy maintainers and contributors
