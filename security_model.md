# Security Model

## Goal

Use Clan's native `age` vars backend with FIDO-backed operator decryption,
unattended machine runtime decryption, and no repo-local secret orchestration.

## Operator Identities

Operator public recipients are defined directly in:

- `operators/max/recipients.nix`

Day-to-day operator decryption uses the FIDO-backed age identity stub:

- `operators/max/fido-age-identity.txt`

The dev shell exports that path as `AGE_KEYFILE`. Recovery or alternate
operator identities should be passed explicitly by overriding `AGE_KEYFILE`.

## Machine Identities

Clan's age backend manages one runtime age keypair per machine:

- `secrets/age-keys/machines/<machine>/pub`
- `secrets/age-keys/machines/<machine>/key.age`
- `secrets/age-keys/machines/<machine>/key.age.recipients`

The encrypted private key is committed so operators can recover or deploy a
machine with their configured age identities. At runtime, machines use the
deployed key managed by Clan's vars backend.

## Secret Data

Secret vars are stored in Clan's native encrypted layout:

- `secrets/clan-vars/per-machine/.../*.age`
- `secrets/clan-vars/shared/.../*.age`

Public generated values stay in:

- `vars/per-machine/.../value`
- `vars/shared/.../value`

Secret generation, recipient updates, and validation should be performed with
upstream Clan commands such as:

```sh
clan vars generate <machine>
clan vars fix <machine>
clan vars check
clan vars get <machine> <generator>/<file>
```

## Deployment

Use Clan as the default deployment path:

```sh
clan machines update <machine>
```

Direct `nixos-rebuild` remains useful for local debugging, but it should not
grow custom secret upload or machine-key escrow wrappers in this repository.

## Local Clan Services

The local services in `clanServices/` are intentional:

- `edge-proxy` exports public route claims and builds an nginx edge proxy.
- `build-farm` models future remote builders and cache wiring.
- `operator-access` installs the shared SSH user CA trust path.

These services may be refined over time, but they are not legacy secret glue.

## Non-Goals

- no SOPS-based repository secret store
- no custom machine-key escrow scripts
- no custom bootstrap ISO or encrypted repo payload
- no repo-local justfile workflow
- no FIDO requirement for unattended machine runtime decryption
