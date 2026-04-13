# Bootstrap USB payload

This directory is used by `just write flash /dev/sdX`.

Generated (ignored):
- `payload.age` — encrypted payload embedded in bootstrap ISO.

## What gets encrypted into payload

- A working copy of this repo at `/opt/nix-config`
- Optional bootstrap assets (for example Berkeley Mono archive)

The bootstrap payload **does not** include a shared operator private key.

## New-machine prep

Before building or using the installer for a brand-new target, prepare that
machine in your main repo:

- add the machine entry/config
- run `clan vars generate <target>`

That creates the managed Clan age backend machine key and the target's runtime
secret material in the repo, so the installer can stage `/etc/secret-vars`
without extra key-generation steps.

Optional font bootstrap:
- If `bootstrap/berkeley-mono-1.009.zip` exists when you run `just write flash`, it is embedded and restored to:
  - `/opt/nix-config/bootstrap/berkeley-mono-1.009.zip`
  - `/opt/nix-config/packages/berkeley-mono/berkeley-mono-1.009.zip`

## Typical flow

1. Build/write USB:
   - `nix develop .#bootstrap`
   - `just write flash /dev/sdX`
2. Boot target machine from USB.
3. In installer environment, run:
   - `bootstrap-install <target> <disk>`

`bootstrap-install` will:
- unlock the payload if needed
- verify the target exists, vars are valid, and operator access works before touching the disk
- prompt for networking only if no connection is active
- partition the disk
- capture hardware config into the repo copy
- populate `/mnt/etc/secret-vars` through Clan's local age-backend path
- run `nixos-install`
- preserve generated repo updates under `/var/lib/bootstrap/nix-config-updates`

`bootstrap-unlock` decrypts the payload with the operator recipients already tracked in `sops/users/max/key.json`.
By default it uses the repo-tracked FIDO identity stub embedded on the installer media, so it should prompt for touch/PIN without needing a home-directory identity file.
If needed, set `AGE_IDENTITY_FILE=/path/to/recovery.agekey` or `AGE_KEYFILE=/path/to/recovery.agekey` for a recovery-key override.

If you change operator recipients or add a new target with `clan vars generate <target>`, rebuild and rewrite the installer USB before using it.

Advanced/manual recovery path:
- `bootstrap-provision-host-age-key <target>` still exists, but it is no longer
  part of the normal install flow.
