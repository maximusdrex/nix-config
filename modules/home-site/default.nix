{ lib, config, pkgs, inputs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types;

  cfg = config.services.maxHomeSite;

  releasePackage = inputs.home-site.packages.${pkgs.stdenv.hostPlatform.system}.home-site;

in
{
  imports = [ inputs.home-site.nixosModules.default ];

  options.services.maxHomeSite = {
    enable = mkEnableOption "Home Site Phoenix + LiveView deployment";

    domain = mkOption {
      type = types.str;
      description = "Public domain that should serve the Phoenix application.";
    };

    listenPort = mkOption {
      type = types.port;
      default = 4000;
      description = "Port that the Phoenix release will listen on.";
    };

    secretEnvFile = mkOption {
      type = types.str;
      default = "/var/lib/home-site/secrets/env";
      description = "Environment file that contains SECRET_KEY_BASE and related secrets.";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables passed to the Phoenix release.";
    };

    databaseName = mkOption {
      type = types.str;
      default = "home_site";
      description = "Name of the Postgres database backing the application.";
    };

    databaseUser = mkOption {
      type = types.str;
      default = "home-site";
      description = "Database role for the Phoenix application.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.domain != "";
        message = "services.maxHomeSite.domain must be set to the public hostname.";
      }
    ];

    systemd.tmpfiles.rules = [
      (let secretDir = lib.dirOf cfg.secretEnvFile; in "d ${secretDir} 0750 root root - -")
    ];

    services.homeSite = {
      enable = true;
      package = releasePackage;
      host = "127.0.0.1";
      port = cfg.listenPort;
      secretKeyBaseFile = cfg.secretEnvFile;
      environment = ({ PHX_HOST = cfg.domain; } // cfg.extraEnvironment);

      nginx = {
        enable = true;
        serverName = cfg.domain;
        enableACME = true;
        forceSSL = true;
      };

      database = {
        createLocally = true;
        name = cfg.databaseName;
        user = cfg.databaseUser;
      };
    };
  };
}
