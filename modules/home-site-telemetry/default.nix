{ lib, pkgs, config, ... }:

let
  cfg = config.services.homeSiteTelemetry;
  inherit (lib) mkIf mkOption mkEnableOption types;

  stateDir = cfg.stateDir;
  curlPkg = cfg.curlPackage;

  deviceHostname = if cfg.deviceStatus.hostname != null
    then cfg.deviceStatus.hostname
    else config.networking.hostName;

  devicePendingFile = if cfg.deviceStatus.pendingFile != null
    then cfg.deviceStatus.pendingFile
    else "${stateDir}/device-status.json";

  deviceStateFile = if cfg.deviceStatus.stateFile != null
    then cfg.deviceStatus.stateFile
    else "${stateDir}/device-status.sha";

  deploySourceFile = if cfg.deployReport.sourceFile != null
    then cfg.deployReport.sourceFile
    else "${stateDir}/deploy-report.json";

  deployStateFile = if cfg.deployReport.stateFile != null
    then cfg.deployReport.stateFile
    else "${stateDir}/deploy-report.sha";

  branchJSON = builtins.toJSON cfg.deviceStatus.branch;
  modeJSON = builtins.toJSON cfg.deviceStatus.mode;
  statusJSON = builtins.toJSON cfg.deviceStatus.status;
  hostnameJSON = builtins.toJSON deviceHostname;

  deploySender = pkgs.writeShellApplication {
    name = "home-site-deploy-report-send";
    runtimeInputs = [ curlPkg pkgs.coreutils ];
    text = ''
      set -euo pipefail

      SRC=${lib.escapeShellArg deploySourceFile}
      STATE=${lib.escapeShellArg deployStateFile}
      ENDPOINT=${lib.escapeShellArg (cfg.baseUrl + "/api/deploy/report")}

      if [ ! -s "$SRC" ]; then
        exit 0
      fi

      state_dir="$(${pkgs.coreutils}/bin/dirname "$STATE")"
      ${pkgs.coreutils}/bin/mkdir -p "$state_dir"

      digest="$(${pkgs.coreutils}/bin/sha256sum "$SRC" | ${pkgs.coreutils}/bin/cut -d' ' -f1)"

      last=""
      if [ -f "$STATE" ]; then
        last="$(${pkgs.coreutils}/bin/cat "$STATE")"
      fi

      if [ "$digest" = "$last" ]; then
        exit 0
      fi

      if ${curlPkg}/bin/curl \
          --silent --show-error --fail-with-body \
          --connect-timeout 10 --max-time 60 \
          -H 'Content-Type: application/json' \
          -X POST "$ENDPOINT" \
          --data-binary @"$SRC"; then
        echo "$digest" > "$STATE"
      else
        exit 1
      fi
    '';
  };

  deviceSender = pkgs.writeShellApplication {
    name = "home-site-device-status-send";
    runtimeInputs = [ curlPkg pkgs.coreutils ];
    text = ''
      set -euo pipefail

      SRC=${lib.escapeShellArg devicePendingFile}
      STATE=${lib.escapeShellArg deviceStateFile}
      ENDPOINT=${lib.escapeShellArg (cfg.baseUrl + "/api/deploy/device_status")}

      if [ ! -s "$SRC" ]; then
        exit 0
      fi

      state_dir="$(${pkgs.coreutils}/bin/dirname "$STATE")"
      ${pkgs.coreutils}/bin/mkdir -p "$state_dir"

      digest="$(${pkgs.coreutils}/bin/sha256sum "$SRC" | ${pkgs.coreutils}/bin/cut -d' ' -f1)"

      last=""
      if [ -f "$STATE" ]; then
        last="$(${pkgs.coreutils}/bin/cat "$STATE")"
      fi

      if [ "$digest" = "$last" ]; then
        exit 0
      fi

      if ${curlPkg}/bin/curl \
          --silent --show-error --fail-with-body \
          --connect-timeout 10 --max-time 60 \
          -H 'Content-Type: application/json' \
          -X POST "$ENDPOINT" \
          --data-binary @"$SRC"; then
        echo "$digest" > "$STATE"
      else
        exit 1
      fi
    '';
  };

in {
  options.services.homeSiteTelemetry = {
    enable = mkEnableOption "upload deploy telemetry to home-site";

    baseUrl = mkOption {
      type = types.str;
      default = "https://maxschaefer.me";
      description = "Base URL for the home-site telemetry API.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/home-site-telemetry";
      description = "Directory for telemetry state and pending payloads.";
    };

    curlPackage = mkOption {
      type = types.package;
      default = pkgs.curl;
      description = "Curl package used for telemetry uploads.";
    };

    deployReport = {
      enable = mkEnableOption "ship deploy reports to the API";

      sourceFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to the JSON deploy report that should be uploaded.";
      };

      stateFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Override path to store the last-sent deploy report digest.";
      };

      interval = mkOption {
        type = types.str;
        default = "5min";
        description = "Repeat interval for retrying deploy report uploads.";
      };
    };

    deviceStatus = {
      enable = mkEnableOption "report per-device status updates";

      branch = mkOption {
        type = types.str;
        default = "main";
        description = "Git branch associated with this device.";
      };

      mode = mkOption {
        type = types.str;
        default = "switch";
        description = "Deploy mode reported with the device status.";
      };

      status = mkOption {
        type = types.str;
        default = "success";
        description = "Status string to send with device status updates.";
      };

      hostname = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional override for the hostname reported to the API.";
      };

      pendingFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to write the latest device status payload.";
      };

      stateFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Override path to store the last-sent device status digest.";
      };

      interval = mkOption {
        type = types.str;
        default = "5min";
        description = "Repeat interval for retrying device status uploads.";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 root root - -"
    ];

    systemd.services.home-site-telemetry-device-status = mkIf cfg.deviceStatus.enable {
      description = "Upload device status to home-site telemetry";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${deviceSender}/bin/home-site-device-status-send";
      };
    };

    systemd.timers.home-site-telemetry-device-status = mkIf cfg.deviceStatus.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.deviceStatus.interval;
        AccuracySec = "30s";
        Persistent = true;
      };
    };

    system.activationScripts.homeSiteTelemetryDeviceStatus = mkIf cfg.deviceStatus.enable (lib.mkAfter ''
      set -euo pipefail

      dir=${lib.escapeShellArg (builtins.dirOf devicePendingFile)}
      ${pkgs.coreutils}/bin/mkdir -p "$dir"

      commit_full=${lib.escapeShellArg (config.system.configurationRevision or "")}
      if [ -z "$commit_full" ]; then
        echo "home-site telemetry: configurationRevision not set; skipping device status payload" >&2
        exit 0
      fi
      commit_short="$(${pkgs.coreutils}/bin/printf '%s' "$commit_full" | ${pkgs.coreutils}/bin/cut -c1-12)"

      tmp="$(${pkgs.coreutils}/bin/mktemp -p "$dir" device-status.json.XXXXXX)"
      timestamp="$(${pkgs.coreutils}/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"
      cat >"$tmp" <<EOF
{
  "timestamp": "''${timestamp}",
  "branch": ${branchJSON},
  "commit": "''${commit_short}",
  "mode": ${modeJSON},
  "hostname": ${hostnameJSON},
  "status": ${statusJSON}
}
EOF
      ${pkgs.coreutils}/bin/chmod 0640 "$tmp"
      ${pkgs.coreutils}/bin/mv "$tmp" ${lib.escapeShellArg devicePendingFile}

      if command -v systemctl >/dev/null 2>&1; then
        systemctl start home-site-telemetry-device-status.service || true
      fi
    '');

    systemd.services.home-site-telemetry-deploy-report = mkIf cfg.deployReport.enable {
      description = "Upload deploy report to home-site telemetry";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${deploySender}/bin/home-site-deploy-report-send";
      };
    };

    systemd.timers.home-site-telemetry-deploy-report = mkIf cfg.deployReport.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = cfg.deployReport.interval;
        AccuracySec = "30s";
        Persistent = true;
      };
    };
  };
}
