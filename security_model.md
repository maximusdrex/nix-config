# Simplified Security Model

## Goal

Use the simplest model that gives us:

- FIDO-backed operator access
- unattended machine runtime decryption
- one normal Clan vars workflow
- as little custom secret glue as possible

The steady-state target is Clan's native `age` backend.

## Core Model

### Operator identities

Operators are defined by public recipients in:

- `sops/users/max/key.json`

That file contains:

- active FIDO-backed AGE recipients
- the offline recovery AGE recipient

Day-to-day operator decryption uses the repo-tracked FIDO identity stub:

- `sops/users/max/fido-identities.txt`

In practice:

- `AGE_KEYFILE` is the normal identity path for Clan's `age` backend
- `SOPS_AGE_KEY_FILE` remains available for the current `sops`-backed migration path
- the recovery key is only used as an explicit override

### Machine identities

Under the `age` backend, each machine has one runtime AGE keypair managed by Clan:

- repo public key: `secrets/age-keys/machines/<machine>/pub`
- repo encrypted private key: `secrets/age-keys/machines/<machine>/key.age`
- repo recipients sidecar: `secrets/age-keys/machines/<machine>/key.age.recipients`
- deployed private key: `/etc/secret-vars/key.txt`

Operators can decrypt the encrypted machine private key. Machines use the deployed copy at runtime.

### Secret classes

We keep only two classes:

- `machine-runtime`
  - default
  - deployed to machines
  - encrypted to machine public keys
- `operator-only`
  - not deployed
  - encrypted only to operator recipients

In Clan terms, this is mostly just:

- `deploy = true` for machine-runtime
- `deploy = false` for operator-only

Shared secrets are still normal Clan shared vars.

## Backend Choice

This repo now has a tracked backend selector:

- `vars-backend.nix`

Values:

- `secretStore = "sops"` means the repo is still on the old backend
- `secretStore = "age"` means the repo has migrated to Clan's native age backend

When the backend is `age`, `clan.nix` derives:

- `vars.settings.secretStore = "age"`
- `vars.settings.recipients.default` from `sops/users/*/key.json`

This keeps the public operator recipient list in one place and lets the actual secret backend stay pure Clan.

## Repo Layout

### Public operator metadata

- `sops/users/max/key.json`
- `sops/users/max/fido-identities.txt`

### Age backend secret data

- `secrets/age-keys/machines/<machine>/pub`
- `secrets/age-keys/machines/<machine>/key.age`
- `secrets/age-keys/machines/<machine>/key.age.recipients`
- `secrets/clan-vars/per-machine/.../*.age`
- `secrets/clan-vars/shared/.../*.age`

### Public/generated values that stay in `vars/`

- `vars/**/value`
- `vars/per-machine/*/openssh/ssh.id_ed25519.pub/value`
- `vars/per-machine/*/openssh-cert/ssh.id_ed25519-cert.pub/value`
- `vars/shared/openssh-ca/id_ed25519.pub/value`

## Operational Workflow

### Normal operator work

1. Enter the dev shell with `nix develop .#bootstrap`
2. Clan commands use `AGE_KEYFILE=$PWD/sops/users/max/fido-identities.txt`
3. Use `clan vars check`, `clan vars get`, `clan vars upload`, and `clan machines update`
4. If using `nixos-rebuild` directly, run `clan vars upload <machine>` first

### SSH access

The SSH CA stays as a shared Clan var:

- `openssh-ca/id_ed25519`

Servers trust its public key through `clanServices/operator-access`.

For now:

- the static admin SSH key fallback stays in place for testing
- SSH certs default to 180 days

### New machine bootstrap

Current custom bootstrap flow remains:

1. `bootstrap-unlock`
2. `bootstrap-disko <target> <disk>`
3. `bootstrap-capture-hardware <target>`
4. `bootstrap-provision-host-age-key <target>`
5. `bootstrap-install <target>`

Behavior now depends on `vars-backend.nix`:

- with `sops`, bootstrap provisions `/mnt/var/lib/sops-nix/key.txt`
- with `age`, bootstrap provisions `/mnt/etc/secret-vars/key.txt` and writes the machine key to `secrets/age-keys/machines/<target>/`

This keeps first boot working before the first full `clan machines update`.

## Migration Plan

The migration path is:

1. keep the repo working on `sops`
2. copy current secret values into the Clan `age` layout
3. create machine keypairs under `secrets/age-keys/machines/*`
4. flip `vars-backend.nix` to `secretStore = "age"`

The one-time helper is:

- `just migrate-to-age`

That script:

- decrypts current `vars/**/secret` values from the `sops` backend
- writes them to `secrets/clan-vars/.../*.age`
- creates machine keys under `secrets/age-keys/machines/*`
- updates `vars-backend.nix` to `age`
- stages the new `secrets/` tree so flake evaluation can see it

After migration:

1. `nix develop .#bootstrap`
2. `clan vars check`
3. `clan vars upload <machine>`
4. `nixos-rebuild switch --flake .#<machine>` or `clan machines update <machine>`

## Transition Notes

Until the backend flip is complete:

- `clanServices/runtime-secrets` remains as the legacy `sops` shim
- `sops/machines/*` and the old `sops` secret layout still describe the current backend

Once the repo is fully on `age`, those legacy `sops` machine-secret paths can be removed.

## Non-Goals

- no GPG/PGP
- no extra repo-local recipient policy system
- no home-directory software AGE key for normal operator use
- no FIDO touch requirement for unattended runtime decryption
- no PAM FIDO or FIDO-backed disk unlock in this phase
