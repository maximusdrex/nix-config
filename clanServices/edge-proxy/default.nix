{
  clanLib,
  config,
  directory,
  lib,
  ...
}:
let
  inherit (lib) types;

  formatURLHost =
    host: if lib.hasInfix ":" host then "[${host}]" else host;

  hostType = types.strMatching "^(@|[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*)$";
  pathType = types.strMatching "^/.*$";
  durationType = types.strMatching "^[0-9]+(ms|s|m|h|d)$";

  mkRouteFQDN = domain: host: if host == "@" then domain else "${host}.${domain}";
in
{
  _class = "clan.service";
  manifest.name = "edge-proxy";
  manifest.description = "Public nginx edge proxy with ACME and upstream routes over ZeroTier";
  manifest.categories = [ "Network" ];
  manifest.readme = builtins.readFile ./README.md;
  manifest.exports.out = [ "publicProxy" ];

  roles.server = {
    description = "Exports route claims for services on this machine.";
    interface =
      { lib, ... }:
      {
        options = {
          routes = lib.mkOption {
            default = { };
            description = ''
              Public HTTP routes claimed by this machine.

              Each route maps a subdomain and path on the clan domain to a local
              port that the edge machine will proxy over ZeroTier.
            '';
            type = types.attrsOf (
              types.submodule (
                { ... }:
                {
                  options = {
                    host = lib.mkOption {
                      type = hostType;
                      description = ''
                        Subdomain under meta.domain to claim.
                        Use "@" to claim the apex domain directly.
                      '';
                      example = "home";
                    };

                    path = lib.mkOption {
                      type = pathType;
                      default = "/";
                      description = "URL path prefix to proxy.";
                    };

                    port = lib.mkOption {
                      type = types.port;
                      description = "Local port to proxy on this machine.";
                      example = 8123;
                    };

                    scheme = lib.mkOption {
                      type = types.enum [
                        "http"
                        "https"
                      ];
                      default = "http";
                      description = "Upstream scheme for the nginx proxy.";
                    };

                    proxyWebsockets = lib.mkOption {
                      type = types.bool;
                      default = true;
                      description = "Enable websocket proxy support for this route.";
                    };

                    locationExtraConfig = lib.mkOption {
                      type = types.lines;
                      default = "";
                      description = "Extra nginx location config for this route.";
                    };
                  };
                }
              )
            );
          };

          transports = lib.mkOption {
            default = { };
            description = "Public TCP and UDP routes claimed by this machine.";
            type = types.attrsOf (
              types.submodule (
                { config, ... }:
                {
                  options = {
                    protocol = lib.mkOption {
                      type = types.enum [
                        "tcp"
                        "udp"
                      ];
                      description = "Transport protocol for this route.";
                    };

                    publicPort = lib.mkOption {
                      type = types.port;
                      description = "Public port on the edge machine.";
                    };

                    upstreamPort = lib.mkOption {
                      type = types.port;
                      default = config.publicPort;
                      defaultText = lib.literalExpression "config.publicPort";
                      description = "Port on the source machine.";
                    };

                    proxyTimeout = lib.mkOption {
                      type = durationType;
                      default = "10m";
                      description = "Maximum idle time for a proxied session.";
                    };

                    connectionLimitPerIP = lib.mkOption {
                      type = types.ints.positive;
                      default = 64;
                      description = "Maximum active sessions for one source address.";
                    };
                  };
                }
              )
            );
          };
        };
      };

    perInstance =
      {
        machine,
        meta,
        mkExports,
        roles,
        settings,
        instanceName,
        ...
      }:
      let
        edgeMachineNames = lib.attrNames (roles.edge.machines or { });
        zerotierIP = clanLib.getPublicValue {
          flake = directory;
          generator = "zerotier-ip-${machine.name}-zerotier";
          file = "ip";
          default = null;
        };
        upstreamHost = if lib.elem machine.name edgeMachineNames then "127.0.0.1" else zerotierIP;
        normalizedRoutes = lib.mapAttrsToList (routeName: route: {
          inherit routeName;
          machineName = machine.name;
          fqdn = mkRouteFQDN meta.domain route.host;
          path = route.path;
          port = route.port;
          scheme = route.scheme;
          proxyWebsockets = route.proxyWebsockets;
          locationExtraConfig = route.locationExtraConfig;
          upstreamIP = upstreamHost;
        }) settings.routes;
        normalizedTransports = lib.mapAttrsToList (routeName: route: {
          inherit routeName;
          inherit (route)
            connectionLimitPerIP
            protocol
            proxyTimeout
            publicPort
            upstreamPort
            ;
          machineName = machine.name;
          upstreamIP = upstreamHost;
        }) settings.transports;
        exposedPorts = lib.unique (map (route: route.port) normalizedRoutes);
        exposedTCPPorts = lib.unique (
          map (route: route.upstreamPort) (
            lib.filter (route: route.protocol == "tcp") normalizedTransports
          )
        );
        exposedUDPPorts = lib.unique (
          map (route: route.upstreamPort) (
            lib.filter (route: route.protocol == "udp") normalizedTransports
          )
        );
      in
      {
        exports = mkExports {
          publicProxy.routes = normalizedRoutes;
          publicProxy.transports = normalizedTransports;
        };

        nixosModule = {
          assertions = [
            {
              assertion = edgeMachineNames != [ ];
              message = ''
                edge-proxy instance '${instanceName}' needs exactly one edge machine, but none are assigned.
              '';
            }
            {
              assertion = lib.length edgeMachineNames == 1;
              message = ''
                edge-proxy instance '${instanceName}' needs exactly one edge machine, but found:
                ${builtins.concatStringsSep ", " edgeMachineNames}
              '';
            }
          ];

          networking.firewall.allowedTCPPorts = exposedPorts ++ exposedTCPPorts;
          networking.firewall.allowedUDPPorts = exposedUDPPorts;
        };
      };
  };

  roles.edge = {
    description = "Runs nginx, terminates TLS, and proxies claimed routes to servers over ZeroTier.";
    interface =
      { lib, ... }:
      {
        options = {
          acmeEmail = lib.mkOption {
            type = types.str;
            description = "Email address used for ACME registration.";
          };

          transportListenAddresses = lib.mkOption {
            type = types.listOf types.str;
            default = [
              "0.0.0.0"
              "[::]"
            ];
            description = "Addresses that accept public TCP and UDP routes.";
          };
        };
      };

    perInstance =
      {
        exports,
        instanceName,
        roles,
        settings,
        ...
      }:
      let
        edgeMachineNames = lib.attrNames (roles.edge.machines or { });

        routeExports = clanLib.selectExports (
          scope:
          scope.serviceName == config.manifest.name
          && scope.instanceName == instanceName
          && scope.roleName == "server"
        ) exports;

        allRoutes = lib.concatLists (
          lib.mapAttrsToList (_scopeKey: exportValue: exportValue.publicProxy.routes or [ ]) routeExports
        );
        allTransports = lib.concatLists (
          lib.mapAttrsToList (_scopeKey: exportValue: exportValue.publicProxy.transports or [ ]) routeExports
        );

        routeKey = route: "${route.fqdn}|${route.path}";
        groupedByClaim = lib.groupBy routeKey allRoutes;
        duplicateClaimKeys = lib.filter (
          key: lib.length groupedByClaim.${key} > 1
        ) (builtins.attrNames groupedByClaim);
        routesMissingUpstreamIP = lib.filter (route: route.upstreamIP == null) allRoutes;
        routesByHost = lib.groupBy (route: route.fqdn) allRoutes;
        transportKey = route: "${route.protocol}|${toString route.publicPort}";
        groupedByTransport = lib.groupBy transportKey allTransports;
        duplicateTransportKeys = lib.filter (
          key: lib.length groupedByTransport.${key} > 1
        ) (builtins.attrNames groupedByTransport);
        transportsMissingUpstreamIP = lib.filter (route: route.upstreamIP == null) allTransports;

        transportZoneName =
          route:
          "edge_transport_${builtins.substring 0 12 (builtins.hashString "sha256" (transportKey route))}";

        renderTransportListen =
          route: address:
          "listen ${address}:${toString route.publicPort}${
            lib.optionalString (route.protocol == "udp") " udp reuseport"
          };";

        renderTransport =
          route:
          let
            zoneName = transportZoneName route;
          in
          ''
            limit_conn_zone $binary_remote_addr zone=${zoneName}:1m;

            server {
              ${builtins.concatStringsSep "\n" (map (renderTransportListen route) settings.transportListenAddresses)}
              proxy_connect_timeout 5s;
              proxy_timeout ${route.proxyTimeout};
              ${lib.optionalString (route.protocol == "tcp") "proxy_socket_keepalive on;"}
              proxy_pass ${formatURLHost route.upstreamIP}:${toString route.upstreamPort};
              limit_conn ${zoneName} ${toString route.connectionLimitPerIP};
            }
          '';

        duplicateClaimAssertions = map (
          key:
          let
            routes = groupedByClaim.${key};
            claimants = builtins.concatStringsSep ", " (
              map (route: "${route.machineName}.${route.routeName}") routes
            );
          in
          {
            assertion = false;
            message = ''
              edge-proxy instance '${instanceName}' has a duplicate route claim for '${key}'.
              Claimants: ${claimants}
            '';
          }
        ) duplicateClaimKeys;
        duplicateTransportAssertions = map (
          key:
          let
            routes = groupedByTransport.${key};
            claimants = builtins.concatStringsSep ", " (
              map (route: "${route.machineName}.${route.routeName}") routes
            );
          in
          {
            assertion = false;
            message = ''
              edge-proxy instance '${instanceName}' has a duplicate transport claim for '${key}'.
              Claimants: ${claimants}
            '';
          }
        ) duplicateTransportKeys;
      in
      {
        nixosModule =
          { ... }:
          {
            assertions =
              [
                {
                  assertion = edgeMachineNames != [ ];
                  message = ''
                    edge-proxy instance '${instanceName}' needs exactly one edge machine, but none are assigned.
                  '';
                }
                {
                  assertion = lib.length edgeMachineNames == 1;
                  message = ''
                    edge-proxy instance '${instanceName}' needs exactly one edge machine, but found:
                    ${builtins.concatStringsSep ", " edgeMachineNames}
                  '';
                }
                {
                  assertion = routesMissingUpstreamIP == [ ];
                  message = ''
                    edge-proxy instance '${instanceName}' has route claims on machines without a published ZeroTier IP:
                    ${
                      builtins.concatStringsSep ", " (
                        map (route: "${route.machineName}.${route.routeName}") routesMissingUpstreamIP
                      )
                    }
                  '';
                }
              ]
              ++ lib.optional (allTransports != [ ] && settings.transportListenAddresses == [ ]) {
                assertion = false;
                message = "edge-proxy instance '${instanceName}' needs a transport listen address.";
              }
              ++ lib.optional (transportsMissingUpstreamIP != [ ]) {
                assertion = false;
                message = ''
                  edge-proxy instance '${instanceName}' has transport claims on machines without a published ZeroTier IP:
                  ${
                    builtins.concatStringsSep ", " (
                      map (route: "${route.machineName}.${route.routeName}") transportsMissingUpstreamIP
                    )
                  }
                '';
              }
              ++ duplicateClaimAssertions
              ++ duplicateTransportAssertions;

            security.acme = {
              acceptTerms = true;
              defaults.email = settings.acmeEmail;
            };

            users.users.nginx.extraGroups = [ "acme" ];

            services.nginx = {
              enable = true;
              recommendedGzipSettings = true;
              recommendedOptimisation = true;
              recommendedProxySettings = true;
              recommendedTlsSettings = true;

              virtualHosts = lib.mapAttrs (
                publicHost: hostRoutes:
                let
                  locations = builtins.listToAttrs (
                    map (
                      route:
                      {
                        name = route.path;
                        value = {
                          proxyPass = "${route.scheme}://${formatURLHost route.upstreamIP}:${toString route.port}";
                          proxyWebsockets = route.proxyWebsockets;
                          extraConfig = lib.optionalString (route.locationExtraConfig != "") route.locationExtraConfig;
                        };
                      }
                    ) hostRoutes
                  );
                in
                {
                  serverName = publicHost;
                  enableACME = true;
                  forceSSL = true;

                  listen = [
                    {
                      addr = "0.0.0.0";
                      port = 80;
                    }
                    {
                      addr = "0.0.0.0";
                      port = 443;
                      ssl = true;
                    }
                    {
                      addr = "[::]";
                      port = 80;
                    }
                    {
                      addr = "[::]";
                      port = 443;
                      ssl = true;
                    }
                  ];

                  extraConfig = ''
                    proxy_buffering off;
                    proxy_read_timeout 3600s;
                    proxy_send_timeout 3600s;

                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection $connection_upgrade;
                  '';

                  inherit locations;
                }
              ) routesByHost;

              streamConfig = lib.mkAfter (
                builtins.concatStringsSep "\n" (map renderTransport allTransports)
              );
            };

            networking.firewall.allowedTCPPorts =
              [
                80
                443
              ]
              ++ map (route: route.publicPort) (
                lib.filter (route: route.protocol == "tcp") allTransports
              );
            networking.firewall.allowedUDPPorts = map (route: route.publicPort) (
              lib.filter (route: route.protocol == "udp") allTransports
            );
          };
      };
  };
}
