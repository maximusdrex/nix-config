# Max's NixOS Configuration

This repository defines my machines as a Clan using Clan's native NixOS
configuration, inventory, services, and vars model.

## Layout

- `clan.nix` is the main Clan definition: machines, inventory, instances, and
  local Clan services.
- `machines/<name>/` contains host-specific NixOS configuration and generated
  hardware configuration.
- `roles/` contains shared NixOS roles used by multiple machines.
- `homes/` contains Home Manager modules.
- `operators/` contains public operator age recipients and the FIDO-backed age
  identity stub used for local operator decryption.
- `vars/` contains public Clan vars values.
- `secrets/` contains encrypted Clan age backend data and is intended to be
  committed.
- `clanServices/` contains local Clan services that intentionally extend the
  upstream Clan model for this fleet.

## Normal Workflow

Enter the development shell:

```sh
nix develop
```

The shell exports:

```sh
CLAN_DIR=$PWD
AGE_KEYFILE=$PWD/operators/max/fido-age-identity.txt
```

Common commands:

```sh
clan vars check
clan vars generate <machine>
clan vars fix <machine>
clan machines update <machine>
```

For direct local NixOS work, use standard Nix commands:

```sh
nixos-rebuild build --flake .#<machine>
nixos-rebuild switch --flake .#<machine>
```

Prefer `clan machines update` for deployed machines because it follows Clan's
deployment and vars workflow.
