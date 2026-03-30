# Bootstrap USB payload

This directory is used by `just write flash /dev/sdX`.

- `payload.age` (generated, ignored): encrypted tarball embedded in bootstrap ISO.
- `yubikey-recipient.txt` (optional, commit-safe): first line `age1...` recipient for your hardware key.
- `yubikey-identity.txt` (optional, ignored): identity stub used by age plugin on installer media.

## Typical flow

1. Ensure your hardware key age recipient is available (or set `bootstrap/yubikey-recipient.txt`).
2. Build/write USB:
   - `just write flash /dev/sdX`
3. Boot target machine from USB.
4. In installer environment, run:
   - `bootstrap-unlock`
5. Then:
   - `cd /opt/nix-config`
   - `nix develop .#bootstrap`
   - `just switch <target>`
