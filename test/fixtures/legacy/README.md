# Legacy test setup

[`prepare_cfg-update_test`](prepare_cfg-update_test) is the original author setup script for a real Gentoo install. It predates the sandbox harness and assumes live system paths:

- Appends lines to `/var/lib/cfg-update/checksum.index`
- Moves `._new-cfg_*` files into `/var/lib/cfg-update/backups/etc/test/`
- Runs `cfg-update --list`

**Do not run blindly** on a production system. Use the per-scenario directories in the parent [`fixtures/`](../) tree with [`run-tests.sh`](../../run-tests.sh) instead.