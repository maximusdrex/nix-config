# Clan Age Backend Secrets

This directory holds the encrypted secret material for Clan's native `age` backend.

Layout:

- `age-keys/machines/<machine>/pub`
  machine public key
- `age-keys/machines/<machine>/key.age`
  machine private key encrypted to operator recipients
- `age-keys/machines/<machine>/key.age.recipients`
  operator recipients for that encrypted machine key
- `clan-vars/per-machine/.../*.age`
  per-machine secret vars
- `clan-vars/shared/.../*.age`
  shared secret vars

These files are encrypted and are meant to be committed.
