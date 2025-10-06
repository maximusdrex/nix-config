{ lib, config, pkgs, inputs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkMerge
    mkDefault
    mkAfter
    types
    optionalAttrs
    optionalString
    optionals
    hasPrefix
    removePrefix
    filter
    concatStringsSep
    escapeShellArg
    replaceStrings;

  cfg = config.services.maxHomeSite;

  homeSitePackage = inputs.home-site.packages.${pkgs.stdenv.hostPlatform.system}.home-site;

  dbCfg = cfg.database;

  dbUrl =
    if !dbCfg.enable then null
    else if dbCfg.createLocally then
      let
        encodedSocketDir = lib.replaceStrings [ "/" ] [ "%2F" ] dbCfg.socketDir;
      in
      "postgresql://${dbCfg.user}@${encodedSocketDir}/${dbCfg.name}"
    else dbCfg.url;

  baseEnvironment = {
    MIX_ENV = "prod";
    PHX_SERVER = "true";
    PHX_HOST = cfg.domain;
    PORT = toString cfg.listenPort;
    RELEASE_TMPDIR = "/run/home-site";
  }
  // optionalAttrs (dbCfg.enable && dbUrl != null) {
    DATABASE_URL = dbUrl;
    POOL_SIZE = toString dbCfg.poolSize;
  };

  stateDirName = removePrefix "/var/lib/" cfg.stateDir;

  environmentFiles = filter (file: file != null && file != "")
    (cfg.extraEnvironmentFiles ++ [ cfg.secretEnvFile ]);

in
{
  options.services.maxHomeSite = {
    enable = mkEnableOption "Home Site Phoenix + LiveView deployment";

    domain = mkOption {
      type = types.str;
      description = "Public domain that should serve the Phoenix application.";
    };

    listenPort = mkOption {
      type = types.port;
      default = 4000;
      description = "Port that the Phoenix release listens on.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/home-site";
      description = "State directory used by the release and systemd service.";
    };

    user = mkOption {
      type = types.str;
      default = "home-site";
      description = "System user running the service.";
    };

    group = mkOption {
      type = types.str;
      default = "home-site";
      description = "System group running the service.";
    };

    secretEnvFile = mkOption {
      type = types.str;
      default = "/var/lib/home-site/secrets/env";
      description = "Environment file that should contain SECRET_KEY_BASE and other sensitive variables.";
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional key/value environment variables to provide to the Phoenix release.";
    };

    extraEnvironmentFiles = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional systemd EnvironmentFile paths to source before starting.";
    };

    autoMigrate = mkOption {
      type = types.bool;
      default = true;
      description = "Run database migrations before starting the service.";
    };

    database = mkOption {
      type = types.submodule ({ ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to configure database integration.";
          };

          createLocally = mkOption {
            type = types.bool;
            default = true;
            description = "Provision and manage a local PostgreSQL instance.";
          };

          package = mkOption {
            type = types.package;
            default = pkgs.postgresql_16;
            description = "PostgreSQL package for the managed database.";
          };

          name = mkOption {
            type = types.str;
            default = "home_site";
            description = "Database name.";
          };

          user = mkOption {
            type = types.str;
            default = "home-site";
            description = "Database role.";
          };

          socketDir = mkOption {
            type = types.path;
            default = "/run/postgresql";
            description = "Socket directory used when connecting to the local database.";
          };

          port = mkOption {
            type = types.nullOr types.port;
            default = 5432;
            description = "Port for the managed PostgreSQL instance.";
          };

          url = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Override DATABASE_URL when using an external database.";
          };

          poolSize = mkOption {
            type = types.int;
            default = 10;
            description = "Ecto connection pool size.";
          };
        };
      });
      default = {};
      description = "Database provisioning and connection configuration.";
    };

    nginx = mkOption {
      type = types.submodule ({ ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to configure an nginx virtual host.";
          };

          enableACME = mkOption {
            type = types.bool;
            default = true;
            description = "Request ACME certificates for the virtual host.";
          };

          forceSSL = mkOption {
            type = types.bool;
            default = true;
            description = "Redirect HTTP traffic to HTTPS.";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Extra nginx config appended to the proxied location.";
          };
        };
      });
      default = {};
      description = "nginx configuration for the public endpoint.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.domain != "";
        message = "services.maxHomeSite.domain must be set to the public hostname.";
      }
      {
        assertion = hasPrefix "/var/lib/" cfg.stateDir;
        message = "services.maxHomeSite.stateDir must live under /var/lib for systemd StateDirectory.";
      }
      {
        assertion = !(dbCfg.enable && !dbCfg.createLocally && dbCfg.url == null);
        message = "When not creating a local database, services.maxHomeSite.database.url must be provided.";
      }
    ];

    users = {
      groups.${cfg.group} = {};
      users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        description = "Home Site Phoenix runtime user";
      };
    };

    systemd.tmpfiles.rules = [
      (let secretDir = lib.dirOf cfg.secretEnvFile;
       in "d ${secretDir} 0750 root root - -")
    ];

    services.postgresql = mkIf (dbCfg.enable && dbCfg.createLocally) (mkMerge [
      {
        enable = true;
        package = dbCfg.package;
        ensureDatabases = lib.mkAfter [ dbCfg.name ];
        ensureUsers = lib.mkAfter [{
          name = dbCfg.user;
        }];
        settings = {
          unix_socket_directories = dbCfg.socketDir;
          listen_addresses = lib.mkDefault "";
        } // optionalAttrs (dbCfg.port != null) { port = dbCfg.port; };
      }
    ]);

    systemd.services."home-site-db-owner" = mkIf (dbCfg.enable && dbCfg.createLocally) {
      description = "Ensure ownership for ${dbCfg.name} database";
      wantedBy = [ "multi-user.target" ];
      requires = [ "postgresql-setup.service" ];
      after = [ "postgresql-setup.service" ];

      path = [ dbCfg.package pkgs.gnugrep pkgs.coreutils ];

      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };

      script = ''
        set -euo pipefail

        if ! psql -tAc ${lib.escapeShellArg "SELECT 1 FROM pg_roles WHERE rolname = '${dbCfg.user}'"} | grep -q 1; then
          echo "Role ${dbCfg.user} missing; ensure services.postgresql.ensureUsers covers it." >&2
          exit 1
        fi

        if ! psql -tAc ${lib.escapeShellArg "SELECT 1 FROM pg_database WHERE datname = '${dbCfg.name}'"} | grep -q 1; then
          echo "Database ${dbCfg.name} missing; ensure services.postgresql.ensureDatabases covers it." >&2
          exit 1
        fi

        psql -tAc ${lib.escapeShellArg "ALTER DATABASE \"${dbCfg.name}\" OWNER TO \"${dbCfg.user}\""}
      '';
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = lib.mkDefault true;
      virtualHosts.${cfg.domain} = {
        enableACME = cfg.nginx.enableACME;
        forceSSL = cfg.nginx.forceSSL;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.listenPort}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '' + cfg.nginx.extraConfig;
        };
      };
    };

    systemd.services."home-site" = {
      description = "Home Site Phoenix application";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ]
        ++ lib.optionals (dbCfg.enable && dbCfg.createLocally) [ "postgresql.service" ];
      wants = [ "network-online.target" ]
        ++ lib.optionals (dbCfg.enable && dbCfg.createLocally) [ "postgresql.service" ];
      requires = lib.optionals (dbCfg.enable && dbCfg.createLocally) [ "postgresql.service" ];

      environment = mkMerge [
        baseEnvironment
        cfg.extraEnvironment
        { HOME = cfg.stateDir; }
      ];

      path = [ pkgs.bash pkgs.coreutils ];

      preStart = optionalString (cfg.autoMigrate && dbCfg.enable) ''
        set -euo pipefail
        ${homeSitePackage}/bin/home-site eval 'HomeSite.Release.migrate'
      '';

      serviceConfig = mkMerge ([
        {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.stateDir;
          StateDirectory = stateDirName;
          StateDirectoryMode = "0750";
          RuntimeDirectory = "home-site";
          RuntimeDirectoryMode = "0750";
          Restart = "on-failure";
          RestartSec = 5;
          ExecStart = "${homeSitePackage}/bin/home-site start";
          ExecStop = "${homeSitePackage}/bin/home-site stop";
          UMask = "0027";
        }
      ] ++ lib.optional (environmentFiles != []) {
        EnvironmentFile = environmentFiles;
      });
    };
  };
}
