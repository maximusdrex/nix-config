# FIDO + Clan Age Notes

The active policy is documented in [`../security_model.md`](../security_model.md).

Current state:

- Clan's native `age` vars backend is the only repository secret backend.
- Operator recipients are plain Nix data in `operators/max/recipients.nix`.
- Operator decryption normally uses `operators/max/fido-age-identity.txt`.
- Machine runtime keys live under `secrets/age-keys/machines/*`.
- Encrypted vars live under `secrets/clan-vars/*`.
- Public generated values live under `vars/*`.

Use upstream Clan commands for generation, validation, repair, and deployment:

```sh
nix develop
clan vars check
clan vars generate <machine>
clan vars fix <machine>
clan machines update <machine>
```
