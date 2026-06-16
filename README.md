# DISCLAIMER / WARNING

I'm in the process of using an LLM to clean up some of the dead code branches here.
I'm being conservative, but please use care before using the 1.9.0+ releases.  
Feedback is welcome.  Eventually I might port this to python, but the initial focus is on trimming
some of the features like sshfs that nobody uses.  A few obvious bugs were fixed, as well as 
dilfridge's patch.

# cfg-update

A safe, staged alternative to Gentoo's `etc-update` for handling configuration file updates after package merges.

**Upstream:** Stephan van Boven (Gentoo, 2007)  
**Maintained fork:** [rich0/cfg-update](https://github.com/rich0/cfg-update)  
**Version:** 1.9.1 (development)  
**License:** GPL v2 ([COPYING](COPYING))

## What it does

When Portage installs a package that updates a protected config file, it leaves a `._cfg0000_*` file beside the live config. `cfg-update` finds those pending updates and processes them through a **5-stage pipeline**:

| Stage | Mode | Behavior |
|-------|------|----------|
| 1 | Automatic | Overwrite files whose MD5 still matches the install-time checksum |
| 2 | Automatic | 3-way `diff3` merge when a backup from a prior update exists |
| 3 | Manual | Resolve merge conflicts in your chosen diff/merge tool |
| 4 | Manual | 2-way merge for files never updated by cfg-update before |
| 5 | Manual | Binaries, symlinks, and other special cases |

Stages can be disabled individually in `/etc/cfg-update.conf`. Use `-a` (automatic-only) for cron jobs that should skip manual stages.

## Quick start

```bash
# List pending config updates
cfg-update -l

# Interactive update session (requires root)
sudo cfg-update -u

# Preview what would happen without making changes
sudo cfg-update -p -u

# Automatic stages only (suitable for cron)
sudo cfg-update -au
```

After `emerge`, if new `._cfg0000_*` files appear, run `cfg-update -u` before the next emerge when possible — the checksum index cannot refresh while pending updates exist.

## Installation

This repository contains the script sources. On Gentoo, install via an ebuild/overlay or manually:

```bash
# Example manual install (adjust paths to taste)
sudo install -m 755 cfg-update /usr/bin/cfg-update
sudo install -m 644 cfg-update.conf /etc/cfg-update.conf
sudo install -m 644 cfg-update.hosts /etc/cfg-update.hosts
sudo install -m 644 cfg-update.8 /usr/share/man/man8/cfg-update.8
sudo install -m 755 cfg-update_indexing /usr/lib/cfg-update/cfg-update_indexing
sudo mandb
```

On first run, `cfg-update` automatically installs a Portage hook in `/etc/portage/bashrc` that rebuilds the checksum index before each emerge:

```bash
pre_pkg_setup() {
    [[ $ROOT = / ]] && cfg-update --index
}
```

Set your preferred merge tool in `/etc/cfg-update.conf` (default: `meld`):

```
MERGE_TOOL = /usr/bin/meld
```

See [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) for required packages.

## Configuration

| File | Purpose |
|------|---------|
| `/etc/cfg-update.conf` | Merge tool, stage toggles, backup/index paths |
| `/etc/cfg-update.hosts` | Legacy sshfs remote hosts (**deprecated**; run cfg-update per host) |
| `/var/lib/cfg-update/checksum.index` | MD5 index of protected files |
| `/var/lib/cfg-update/backups/` | Per-update backups for 3-way merging |

Template copies of the config files are in this repository: [`cfg-update.conf`](cfg-update.conf), [`cfg-update.hosts`](cfg-update.hosts).

## Common commands

```bash
cfg-update -l              # list pending updates
cfg-update -u              # update (interactive)
cfg-update -au             # automatic stages only
cfg-update -b              # list backups
cfg-update -r <n>          # restore backup #n from -b output
cfg-update -i              # rebuild checksum index
cfg-update --optimize-backups   # prune redundant backup files
cfg-update --help          # full option list
man cfg-update             # detailed manual
```

## Documentation

| Document | Description |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Internal design, data flow, hooks |
| [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) | System and Perl dependencies |
| [docs/INVENTORY.md](docs/INVENTORY.md) | Full codebase characterization (stage 1) |
| [cfg-update.8](cfg-update.8) | Man page |

## Development

This fork is being revived on isolated `refactor/stage-*` branches. See [docs/INVENTORY.md](docs/INVENTORY.md) for the cleanup roadmap.

The vendored ebuild in [`gentoo/`](gentoo/) tracks the development line (**1.9.1**). Release **1.9.0** is tagged; do not tag new versions without maintainer approval.

```bash
# Validate Perl syntax
perl -c cfg-update

# Run included test fixtures (on a Gentoo host)
tar xzf test.tgz -C /tmp
# See test/prepare_cfg-update_test inside the archive
```

## Reporting issues

Report bugs on the [GitHub issue tracker](https://github.com/rich0/cfg-update/issues).

Historical bugs were filed at [bugs.gentoo.org](https://bugs.gentoo.org) when this lived in the Gentoo tree.

## See also

- `etc-update` — Portage's built-in config updater
- `dispatch-conf` — Another Gentoo config merge tool
