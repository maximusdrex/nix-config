# Edge proxy

This Clan service makes one machine the public edge for the clan domain.

Server-role machines export HTTP, TCP, or UDP route claims. The edge role consumes those claims and configures Nginx.

HTTP routes receive ACME certificates. Nginx proxies each route to its source machine through ZeroTier.

TCP and UDP routes use the Nginx stream module. These routes do not use hostnames, HTTP, ACME, or TLS termination.

Routes from the edge host use `127.0.0.1` as the upstream address.

## HTTP example

```nix
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

## TCP and UDP example

Set `transportListenAddresses` when Nginx must bind to selected public addresses.

```nix
roles.edge.machines.edge-box.settings = {
  acmeEmail = "admin@example.com";
  transportListenAddresses = [ "203.0.113.10" ];
};

roles.server.machines.app-box.settings.transports = {
  application-tcp = {
    protocol = "tcp";
    publicPort = 1001;
    upstreamPort = 1001;
    proxyTimeout = "10m";
    connectionLimitPerIP = 64;
  };

  application-udp = {
    protocol = "udp";
    publicPort = 1011;
    upstreamPort = 1011;
  };
};
```

The source machine firewall accepts each declared upstream port.

The edge firewall accepts each declared public port.

Each protocol and public port pair must be unique within one service instance.
