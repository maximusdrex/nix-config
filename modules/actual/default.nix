{ lib, config, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types removePrefix hasPrefix optionalAttrs;

  cfg = config.services.actual;
in
{
  options.services.actual = {
    enable = mkEnableOption "Actual budgeting server";

    package = mkOption {
      type = types.package;
      default = pkgs.actual-server;
      description = "Actual server package to run.";
    };

    user = mkOption {
      type = types.str;
      default = "actual";
      description = "System user running the Actual service.";
    };

    group = mkOption {
      type = types.str;
      default = "actual";
      description = "System group running the Actual service.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/actual";
      description = "Persistent data directory for Actual.";
    };

    port = mkOption {
      type = types.port;
      default = 5006;
      description = "Port that Actual listens on.";
    };

    hostname = mkOption {
      type = types.str;
      default = "::";
      description = "Hostname/interface Actual should bind to.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for the Actual service.";
    };
  };

  config = mkIf cfg.enable {
    users.groups.${cfg.group} = { };

    users.users.${cfg.user} = {
      isSystemUser = true;
      createHome = true;
      home = cfg.dataDir;
      group = cfg.group;
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' 0750 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.actual = {
      description = "Actual Budgeting Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/actual-server";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        RestartSec = 5;
      } // optionalAttrs (hasPrefix "/var/lib/" cfg.dataDir) {
        StateDirectory = removePrefix "/var/lib/" cfg.dataDir;
      };

      environment = {
        ACTUAL_DATA_DIR = cfg.dataDir;
        ACTUAL_PORT = toString cfg.port;
        ACTUAL_HOSTNAME = cfg.hostname;
      } // cfg.environment;
    };
  };
}
