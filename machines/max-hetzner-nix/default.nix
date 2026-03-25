{ config, lib, pkgs, ... }:

########################
# Host-specific config
########################

{
  # Import auto-configured hardware settings
  imports =
    [ 
       ./hardware-configuration.nix
       ../../roles/server.nix
    ];

  ######################
  # 1. Bootloader
  ######################

  ######################
  # 2. Kernel
  ######################

  ######################
  # 3. Networking
  ######################

  ######################
  # 4. General Config
  ######################

  ######################
  # 6. Other
  ######################

  services.actual = {
    enable = true;
    settings = {
      port = 5006;
      hostname = "0.0.0.0";
    };
  };

  services.nginx.virtualHosts."max-hetzner-nix.maxschaefer.me".serverAliases = [
    "max-hetzner-nix.zt.maxschaefer.me"
  ];

  services.nginx.virtualHosts."monitoring.zt.maxschaefer.me" = {
    locations = {
      "/" = {
        extraConfig = ''
          return 302 /grafana/;
        '';
      };

      "/mimir/" = {
        basicAuthFile = "/run/nginx/credentials/mimir-auth-htpasswd";
        proxyPass =
          "http://127.0.0.1:${builtins.toString config.services.mimir.configuration.server.http_listen_port}${config.services.mimir.configuration.server.http_path_prefix}/";
      };

      "/loki/" = {
        basicAuthFile = "/run/nginx/credentials/loki-auth-htpasswd";
        proxyPass =
          "http://127.0.0.1:${builtins.toString config.services.loki.configuration.server.http_listen_port}${config.services.loki.configuration.server.http_path_prefix}/";
      };

      "/grafana/" = {
        proxyPass = "http://127.0.0.1:${builtins.toString config.services.grafana.settings.server.http_port}/";
        proxyWebsockets = true;
      };
    };
  };

  # Internal ZeroTier hostnames are HTTP-only right now. Reject unmatched TLS
  # handshakes so unknown HTTPS hosts do not fall through to an unrelated
  # public edge-proxy vhost like budget.maxschaefer.me.
  services.nginx.virtualHosts."00-reject-unknown-https" = {
    default = true;
    rejectSSL = true;
    listen = [
      {
        addr = "0.0.0.0";
        port = 443;
      }
      {
        addr = "[::]";
        port = 443;
      }
    ];
  };

  services.grafana.settings = {
    security = {
      csrf_trusted_origins = lib.mkForce [
        "https://monitoring.maxschaefer.me"
        "http://monitoring.zt.maxschaefer.me"
      ];
      cookie_secure = lib.mkForce true;
    };
    server = {
      domain = lib.mkForce "monitoring.maxschaefer.me";
      root_url = lib.mkForce "https://monitoring.maxschaefer.me/grafana/";
      serve_from_sub_path = lib.mkForce true;
    };
  };

  # Work around two issues in the current monitoring stack rollout:
  # 1. Clan's PostgreSQL helper generates invalid OWNER SQL for CREATE DATABASE.
  # 2. This host's existing template1 collation metadata is stale, so creating
  #    a database via the default template1 path fails during activation.
  #
  # Creating Grafana from template0 avoids template1 entirely, and the native
  # NixOS PostgreSQL setup service still assigns ownership correctly.
  clan.core.postgresql.databases.grafana.create.options = lib.mkForce {
    TEMPLATE = "template0";
  };
  services.postgresql = {
    ensureDatabases = [ "grafana" ];
    ensureUsers = [
      {
        name = "grafana";
        ensureDBOwnership = true;
      }
    ];
  };

  # Server-specific security settings - temporarily disabled

  # Host config

  networking.hostName = "max-hetzner-nix"; # Define your hostname.

  # Warning!
  system.stateVersion = "25.05"; # Did you read the comment?

}
