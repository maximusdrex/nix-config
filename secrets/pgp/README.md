# OpenPGP Keys (Per-Device Architecture)

This directory contains OpenPGP public keys for per-device authentication.

## Architecture

Each device has its own OpenPGP keypair:
- Private key stored securely on the device's security key
- Public key stored in this repository for git-crypt access
- No shared master keys - each device is independent

## Directory Structure

- `public-keys/` - Public keys for each device (safe to commit)
  - `max-hetzner-nix.asc` - Server public key
  - `max-xps-modal.asc` - Laptop public key
  - `max-g14-nix.asc` - Gaming laptop public key

## Setup Process (Per Device)

1. **Generate device key on security key:**
   ```bash
   # Follow Token2 documentation for your specific model
   ```

2. **Export public key to repository:**
   ```bash
   gpg-export-device-key
   git add secrets/pgp/public-keys/$(hostname).asc
   git commit -m "Add public key for $(hostname)"
   ```

3. **Add device to git-crypt:**
   ```bash
   git-crypt-add-device $(hostname)
   git commit -m "Add $(hostname) to git-crypt"
   ```

## Key Management

- **Private keys:** Only exist on security keys, never in repository
- **Public keys:** Stored in repository for git-crypt access
- **Independence:** Loss of one device doesn't affect others
- **Git-crypt:** Uses native multi-key support

## Commands

- `gpg-export-device-key [device]` - Export public key to repository
- `git-crypt-add-device [device]` - Add device to git-crypt
- `git-crypt-unlock` - Unlock repository with device key

## Security Benefits

- No shared secrets between devices
- Device compromise only affects that device
- Simple key rotation per device
- No master key to backup securely