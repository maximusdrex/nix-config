{ lib, config, pkgs, ... }:

let
  cfg = config.services.edgeProxy;

  # Read peers from our exporter module
  peerList = config.networking.wireguardPeers or [ ];

  # Correct: IP -> [ hostnames... ] (so /etc/hosts lines are "IP name")
  wgHostsMap =
    builtins.listToAttrs (builtins.map
      (p: { name = p.ip; value = [ "${p.hostname}.wg" ]; })
      peerList);

  mkWgName = host: "${host}.wg";

  # Optional helper to look up an IP by hostname (for "inline IP" mode)
  peerIP = host:
    let m = lib.findFirst (x: x.hostname == host) null peerList;
    in if m == null then
         (throw "edge-proxy: upstreamHost '${host}' not found in networking.wireguardPeers")
       else m.ip;

in
{
  options.services.edgeProxy = {
    enable = lib.mkEnableOption "Nginx + ACME edge proxy over WireGuard";

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Email for Let's Encrypt/ACME";
    };

    # If true, use the peer IPs directly in proxy_pass (no runtime name resolution).
    resolveUpstreamsAtBuild = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Inline upstream IPs at build-time instead of using *.wg hostnames.";
    };

    # sites."public.domain" = { upstreamHost = "peer-hostname"; upstreamPort = 8123; extraLocations = {...}; }
    sites = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          upstreamHost = lib.mkOption {
            type = lib.types.str;
            description = "WG peer hostname from wg-hosts.nix (e.g., max-richard-nix)";
          };
          upstreamPort = lib.mkOption {
            type = lib.types.port;
            description = "Port on the peer (e.g., 8123)";
          };
          extraLocations = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                proxyPass = lib.mkOption {
                  type = lib.types.str;
                  description = "Full proxy_pass URL (e.g., http://host.wg:port/path)";
                };
              };
            });
            default = {};
            description = "Optional extra locations";
          };
        };
      }));
      default = {};
      description = "Public hostnames to proxy to WG peers";
    };
  };

  config = lib.mkIf cfg.enable {
    ########################################
    # Make *.wg resolvable for nginx at start
    ########################################
    networking.hosts = wgHostsMap;

    ########################################
    # ACME / TLS
    ########################################
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
    };

    ########################################
    # Nginx
    ########################################
    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts =
        lib.mapAttrs (publicHost: site:
          let
            upstreamHostOrIP =
              if cfg.resolveUpstreamsAtBuild
              then peerIP site.upstreamHost
              else mkWgName site.upstreamHost;

            upstreamURL = "http://${upstreamHostOrIP}:${toString site.upstreamPort}";
          in {
            serverName = publicHost;
            enableACME = true;
            forceSSL = true;

            listen = [
              { addr = "0.0.0.0"; port = 80; }
              { addr = "0.0.0.0"; port = 443; ssl = true; }
              { addr = "[::]";     port = 80; }
              { addr = "[::]";     port = 443; ssl = true; }
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

            locations =
              {
                "/" = {
                  proxyPass = upstreamURL;
                  proxyWebsockets = true;
                };
              }
              // lib.mapAttrs (_loc: locConf: {
                proxyPass = locConf.proxyPass;
                proxyWebsockets = true;
              }) site.extraLocations;
          }
        ) cfg.sites;
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}

