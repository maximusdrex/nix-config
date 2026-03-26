The `build-farm` service turns one or more Clan machines into an internal Nix
build farm over ZeroTier.

Roles:

- `builder`: accepts remote Nix builds over SSH using a dedicated shared builder
  key.
- `cache`: serves the local `/nix/store` as a signed binary cache using
  Harmonia, bound to the machine's published ZeroTier address.
- `client`: configures remote builders and cache substituters for a machine.

The service is inventory-driven:

- cache endpoints are derived from the assigned cache machines and their
  published `zerotier-ip` vars
- builder SSH endpoints are derived from the assigned builder machines
- no builder or cache address is hardcoded in the service implementation

Example:

```nix
modules.build-farm = ./clanServices/build-farm;

inventory.instances.build-farm = {
  module = {
    input = "self";
    name = "build-farm";
  };

  roles.builder.machines."max-hetzner-nix".settings = {
    maxJobs = 8;
    speedFactor = 20;
    systems = [ "x86_64-linux" ];
  };

  roles.cache.machines."max-hetzner-nix".settings = {
    port = 5000;
    priority = 25;
  };

  roles.client.tags.nixos = { };
  roles.client.settings.builderDomain = "zt.example.com";
};
```

If you want SSH host verification without TOFU prompts, enable Clan's `sshd`
service `client` role and include your internal mesh domain in the `server`
certificate search domains.
