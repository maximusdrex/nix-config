`edge-proxy` is a self-hosted Clan service that turns one machine into the
public edge for your clan domain.

Machines with the `server` role export route claims in the form of
`host + path -> local port`. The machine with the `edge` role consumes those
claims, provisions ACME certificates with nginx, and proxies each route to the
claiming machine over ZeroTier using the published `zerotier-ip` Clan var.
Routes published by the edge machine itself are proxied over `127.0.0.1`
instead of the mesh address.

Example:

```nix
modules.edge-proxy = ./clanServices/edge-proxy;

inventory.instances.edge-proxy = {
  module = {
    input = "self";
    name = "edge-proxy";
  };

  roles.edge.machines.edge-box.settings.acmeEmail = "admin@example.com";
  roles.server.tags.server = { };

  roles.server.machines.app-box.settings.routes.home = {
    host = "home";
    port = 8123;
  };
};
```
