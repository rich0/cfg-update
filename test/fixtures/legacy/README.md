# Legacy test setup

[`prepare_cfg-update_test`](prepare_cfg-update_test) is the original author script from `test.tgz`. It assumes a real Gentoo install:

- Appends lines to `/var/lib/cfg-update/checksum.index`
- Moves `._new-cfg_*` files into `/var/lib/cfg-update/backups/etc/test/`
- Runs `cfg-update --list`

**Do not run blindly** on a production system. Use the per-scenario directories in the parent [`fixtures/`](../) tree instead; a future harness will deploy them into an isolated sandbox.