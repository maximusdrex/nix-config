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

  mkRouteFQDN = domain: host: if host == "@" then domain else "${host}.${domain}";
in
{
  _class = "clan.service";
  manifest.name = "edge-proxy";
  manifest.description = "Public nginx edge proxy with ACME and ZeroTier-backed upstream routing";
  manifest.categories = [ "Network" ];
  manifest.readme = builtins.readFile ./README.md;
  manifest.exports.out = [ "publicProxy" ];

  roles.server = {
    description = "Exports route claims for services running on this machine.";
    interface =
      { lib, ... }:
      {
        options.routes = lib.mkOption {
          default = { };
          description = ''
            Public routes claimed by this machine.

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
                    description = "Upstream scheme used by nginx when proxying.";
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
          machine = machine.name;
          generator = "zerotier";
          file = "zerotier-ip";
          default = null;
        };
        normalizedRoutes = lib.mapAttrsToList (routeName: route: {
          inherit routeName;
          machineName = machine.name;
          fqdn = mkRouteFQDN meta.domain route.host;
          path = route.path;
          port = route.port;
          scheme = route.scheme;
          proxyWebsockets = route.proxyWebsockets;
          locationExtraConfig = route.locationExtraConfig;
          upstreamIP = zerotierIP;
        }) settings.routes;
        exposedPorts = lib.unique (map (route: route.port) normalizedRoutes);
      in
      {
        exports = mkExports {
          publicProxy.routes = normalizedRoutes;
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

          networking.firewall.allowedTCPPorts = exposedPorts;
        };
      };
  };

  roles.edge = {
    description = "Runs nginx, terminates TLS, and proxies claimed routes to servers over ZeroTier.";
    interface =
      { lib, ... }:
      {
        options.acmeEmail = lib.mkOption {
          type = types.str;
          description = "Email address used for ACME registration.";
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

        routeKey = route: "${route.fqdn}|${route.path}";
        groupedByClaim = lib.groupBy routeKey allRoutes;
        duplicateClaimKeys = lib.filter (
          key: lib.length groupedByClaim.${key} > 1
        ) (builtins.attrNames groupedByClaim);
        routesMissingUpstreamIP = lib.filter (route: route.upstreamIP == null) allRoutes;
        routesByHost = lib.groupBy (route: route.fqdn) allRoutes;

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
              ++ duplicateClaimAssertions;

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
            };

            networking.firewall.allowedTCPPorts = [
              80
              443
            ];
          };
      };
  };
}
