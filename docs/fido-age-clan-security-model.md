# FIDO + Clan Security Notes

This draft white paper has been superseded by the simpler policy in
[`security_model.md`](../security_model.md).

The repo now follows these rules:

- human secret access is defined by `sops/users/max/key.json`
- that `sops/users` path is now only operator key metadata, not the secret store
- that user recipient set includes the offline recovery recipient
- day-to-day operator decryption uses the repo-tracked FIDO stub at `sops/users/max/fido-identities.txt`
- the repo now uses Clan's native `age` backend for runtime secrets
- machine runtime keys live under `secrets/age-keys/machines/*`
- encrypted runtime vars live under `secrets/clan-vars/*`
- shared secrets stay normal Clan-managed shared vars
- SSH cert signing reads the shared CA through normal Clan vars instead of backend-specific decrypt logic

During the transition:

- servers trust the shared SSH user CA through `clanServices/operator-access`
- a static admin `authorized_keys` fallback may remain for testing
- SSH certs default to a long validity window for convenience

For the current source of truth, use [`security_model.md`](../security_model.md).
