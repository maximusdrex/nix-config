# Bootstrap USB payload

This directory is used by `just write flash /dev/sdX`.

Generated (ignored):
- `payload.age` — encrypted payload embedded in bootstrap ISO.
- `fido2-identity.txt` — age-plugin-fido2-hmac identity generated during write.
- `fido2-recipient.txt` — recipient derived from identity.

## What gets encrypted into payload

- A working copy of this repo at `/opt/nix-config`
- Your sops age key file (from `$SOPS_AGE_KEY_FILE` or `~/.config/sops/age/keys.txt`) at:
  - `bootstrap-secrets/sops-age-key.txt`

On the live USB, `bootstrap-unlock` decrypts and installs the key to:
- `/var/lib/sops-nix/key.txt`
- `/home/nixos/.config/sops/age/keys.txt`
- `/mnt/var/lib/sops-nix/key.txt` (if `/mnt` exists)

Optional font bootstrap:
- If `bootstrap/berkeley-mono-1.009.zip` exists when you run `just write flash`, it is embedded and restored to:
  - `/opt/nix-config/bootstrap/berkeley-mono-1.009.zip`

## Typical flow

1. Build/write USB:
   - `nix develop .#bootstrap`
   - `just write flash /dev/sdX`
2. Boot target machine from USB.
3. In installer environment, run:
   - `bootstrap-unlock`
4. Then:
   - `cd /opt/nix-config`
   - `nix develop .#bootstrap`
   - `just switch <target>`
