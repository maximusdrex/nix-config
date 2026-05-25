# Clan Age Backend Secrets

This directory holds encrypted data for Clan's native `age` vars backend.

Committed layout:

- `age-keys/machines/<machine>/pub`
- `age-keys/machines/<machine>/key.age`
- `age-keys/machines/<machine>/key.age.recipients`
- `clan-vars/per-machine/.../*.age`
- `clan-vars/shared/.../*.age`

These files are encrypted and are meant to be committed. Do not replace this
with a repo-local secret wrapper; use `clan vars generate`, `clan vars fix`,
`clan vars check`, and `clan machines update`.
