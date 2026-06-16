# cfg-update Dependencies

`cfg-update` has no language-level lockfile (`cpanfile`, `package.json`, etc.). All dependencies are **system packages** installed via Gentoo Portage (or equivalent). This document lists what you need for a single-host Portage setup.

## Required

### Interpreter

| Package | Binary | Notes |
|---------|--------|-------|
| `dev-lang/perl` | `perl` | 5.x; tested with modern Perl |

### Perl modules

| Module | Gentoo package | Purpose |
|--------|----------------|---------|
| `strict` | (pragma, core) | — |
| `File::Basename` | (core) | Script name, path helpers |
| `Getopt::Long` | (core) | CLI argument parsing |
| `Term::ANSIColor` | `dev-perl/Term-ANSIColor` | Colored terminal output |
| `Term::ReadKey` | `dev-perl/TermReadKey` | Interactive keypress reads |

Install all Perl deps:

```bash
emerge -av dev-perl/Term-ANSIColor dev-perl/TermReadKey
```

### Core system utilities

Used directly by the script for indexing, merging, and checksums:

| Binary | Gentoo package | Used in |
|--------|----------------|---------|
| `diff3` | `sys-apps/diffutils` | Stage 2 automatic merge |
| `md5sum` | `sys-apps/coreutils` | Checksum comparison |
| `grep` | `sys-apps/grep` | Index build, hook detection |
| `xargs` | `sys-apps/findutils` | Index build (avoids arg limits) |
| `cut`, `head`, `tac`, `sed`, `echo` | various core packages | Index and log parsing |
| `id` | `sys-apps/coreutils` | Root privilege check |
| `stty` | `sys-apps/coreutils` | Terminal width for `sdiff` |

### Portage

| Requirement | Notes |
|-------------|-------|
| `sys-apps/portage` | Provides `emerge`, `/var/db/pkg`, `/var/log/emerge.log` |
| `CONFIG_PROTECT` | Must include `/etc` (default on Gentoo) |

`cfg-update` auto-installs its index hook into `/etc/portage/bashrc` on first run.

## Recommended

### Merge tool

Pick one tool with the capabilities you need:

| Tool | Stages | GUI | Gentoo package | Notes |
|------|--------|:---:|----------------|-------|
| **meld** | 2-way + 3-way | Yes | `dev-util/meld` | **Default** in `cfg-update.conf` |
| kdiff3 | 2-way + 3-way | Yes | `dev-util/kdiff3` | KDE; solid 3-way |
| imediff2 | 2-way | No | varies | CLI; good for headless |
| imediff | 2-way + 3-way | No | varies | CLI 3-way (2025 fork patch) |
| sdiff | 2-way | No | `sys-apps/diffutils` | Fallback if configured tool missing |
| vimdiff | 2-way | Optional | `app-editors/vim` | No X required |

Set in `/etc/cfg-update.conf`:

```
MERGE_TOOL = /usr/bin/meld
```

Stage 3 (manual 3-way) is automatically disabled if your tool lacks 3-way support. Stage 4 (manual 2-way) is disabled only for unsupported tools.

### Optional: less or an editor

```
VIEW_TOOL = less
```

Used to display diffs and file contents during interactive sessions. Can be set to `nano -w` or `vi`.

## Optional

### Paludis

Only needed if you use Paludis instead of (or alongside) Portage:

| Requirement | Notes |
|-------------|-------|
| `sys-apps/paludis` | Provides `/usr/bin/cave` |
| Hook path | `/usr/share/paludis/hooks/install_all_pre/cfg-update.bash` |

`cfg-update` auto-installs the hook when `cave` is present.

### Remote host management (deprecated)

| Package | Purpose |
|---------|---------|
| `sys-fs/sshfs` | Mount remote systems for `-h` / `--mount` |
| `net-misc/openssh` | SSH access to remote hosts |

Not required for single-host use. This feature is deprecated.

### PHP (legacy, scheduled for removal)

| Package | Purpose |
|---------|---------|
| `dev-lang/php` | Only used by `cfg-update_phphelper` |

The PHP helper and emerge wrapper scripts are obsolete. The Portage bashrc hook replaced them. These files will be removed in stage 3 of the refactor.

## Dependency tracking and Renovate

This project has no machine-readable dependency manifest today. Automated update tooling applies only to:

| Ecosystem | Status | Action |
|-----------|--------|--------|
| GitHub Actions | Planned (stage 6) | `renovate.json` with `github-actions` manager |
| CPAN / Perl | Optional future | Add `cpanfile` to enable Renovate `cpan` manager |
| Gentoo packages | Manual | Track versions here; revisit when ebuild is restored |
| System binaries | Manual | No lockfile possible |

### Suggested `cpanfile` (future)

```
requires 'Term::ANSIColor';
requires 'Term::ReadKey';
```

## Verify dependencies

On a Gentoo system with cfg-update installed:

```bash
# Perl syntax
perl -c /usr/bin/cfg-update

# Perl modules
perl -MTerm::ANSIColor -MTerm::ReadKey -e 1

# Merge tool
which meld    # or your configured MERGE_TOOL

# Core utilities
which diff3 md5sum xargs grep

# Portage hook present
grep -q 'cfg-update --index' /etc/portage/bashrc && echo "hook OK"
```

## Historical note

The original Gentoo ebuild (`app-portage/cfg-update`) selected merge tools based on USE flags (`-qt -kde` for meld-only systems). This repository does not include an ebuild; install dependencies manually or via your overlay.