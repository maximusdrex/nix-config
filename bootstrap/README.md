# Bootstrap USB payload

This directory is used by `just write flash /dev/sdX`.

Generated (ignored):
- `payload.age` — encrypted payload embedded in bootstrap ISO.
- `fido2-identity.txt` — age-plugin-fido2-hmac identity generated during write.
- `fido2-recipient.txt` — recipient derived from identity.

## What gets encrypted into payload

- A working copy of this repo at `/opt/nix-config`
- Optional bootstrap assets (for example Berkeley Mono archive)

The bootstrap payload **does not** include a shared operator SOPS private key.

## Runtime host key provisioning (new model)

After `bootstrap-unlock` and `bootstrap-disko`, generate a host-local runtime key:

- `bootstrap-provision-host-age-key <target>`

This will:
- install a freshly generated age identity to `/mnt/var/lib/sops-nix/key.txt`
- update `/opt/nix-config/sops/machines/<target>/key.json` with the new machine recipient

Then commit/push that machine recipient update so future encryptions target the host key.

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
   - `bootstrap-unlock`
   - `bootstrap-disko <target> <disk>`
   - `bootstrap-capture-hardware <target>`
   - `bootstrap-provision-host-age-key <target>`
   - `bootstrap-install <target>`
