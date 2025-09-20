{ lib, config, pkgs, ... }:

let
  # Reuse your single source of truth for WG peers
  wgHosts = import ../wireguard/wg-hosts.nix;  # path relative to this file

  # Build a mapping like { "max-richard-nix.wg" = "10.20.0.6"; ... }
  wgHostsMap =
    builtins.listToAttrs
      (builtins.map (h: { name = "${h.hostname}.wg"; value = [ h.ip ]; }) wgHosts);

  # For resolving a plain hostname to its .wg name
  mkWgName = host: "${host}.wg";

  cfg = config.services.edgeProxy;
in
{
  options.services.edgeProxy = {
    enable = lib.mkEnableOption "Edge reverse proxy (TLS) that tunnels to services via WireGuard";

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Contact email for Let's Encrypt / ACME.";
    };

    # sites."public.host.name" = { upstreamHost = "max-richard-nix"; upstreamPort = 8123; extraLocations = { ... }; }
    sites = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          upstreamHost = lib.mkOption { type = lib.types.str; description = "WG peer hostname (from wg-hosts.nix)."; };
          upstreamPort = lib.mkOption { type = lib.types.port; description = "Upstream service port on the peer."; };
          extraLocations = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                proxyPass = lib.mkOption { type = lib.types.str; description = "Proxy pass URL (http://host.wg:port/path)."; };
              };
            });
            default = {};
            description = "Optional additional locations for this vhost.";
          };
        };
      }));
      default = {};
      description = "Map of public hostnames to WireGuard upstreams.";
    };
  };

  config = lib.mkIf cfg.enable {

    ############################
    # Local name resolution for WG peers (no hard-coded IPs)
    ############################
    networking.hosts = wgHostsMap;
    # e.g. ensures entries like: "max-richard-nix.wg" → 10.20.0.6
    # derived from modules/wireguard/wg-hosts.nix

    ############################
    # ACME / TLS
    ############################
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
    };

    ############################
    # Nginx (TLS termination + proxy to WG)
    ############################
    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts =
        lib.mapAttrs (publicHost: site: {
          enableACME = true;
          forceSSL = true;

          # Websocket/long-lived connections (e.g. HA)
          extraConfig = ''
            proxy_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
          '';

          locations =
            {
              "/" = {
                proxyPass = "http://${mkWgName site.upstreamHost}:${toString site.upstreamPort}";
                proxyWebsockets = true;
              };
            }
            // lib.mapAttrs (loc: locConf: {
              proxyPass = locConf.proxyPass;
              proxyWebsockets = true;
            }) site.extraLocations;
        })
        cfg.sites;
    };

    # Open 80/443 if you ever turn the firewall back on this host
    networking.firewall = {
      allowedTCPPorts = [ 80 443 ];
    };
  };
}

