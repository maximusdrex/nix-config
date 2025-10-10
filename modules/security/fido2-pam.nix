{ config, lib, pkgs, ... }:

let
  cfg = config.security.unifiedAuth;
  fido2Cfg = config.security.unifiedAuth.fido2;
in
{
  options.security.unifiedAuth.fido2 = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable FIDO2 PAM authentication";
    };

    pamServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "login" "sudo" "polkit-1" ];
      description = "PAM services to enable FIDO2 authentication for";
    };

    requireTouch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require touch confirmation for FIDO2 authentication";
    };

    requirePin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require PIN for FIDO2 authentication";
    };

    fallbackPassword = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow password fallback if FIDO2 fails";
    };

    enableOptionalAuth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable optional FIDO2 authentication when not enforcing hardware keys";
    };

    credentialPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/fido2-credentials";
      description = "Path to store FIDO2 credentials";
    };
  };

  config = lib.mkIf fido2Cfg.enable {
    # Install required packages and helper scripts
    environment.systemPackages = with pkgs; [
      libfido2
      pam_u2f
    ] ++ [
      (pkgs.writeShellScriptBin "fido2-register" ''
        set -euo pipefail

        USER="''${1:-$USER}"
        CRED_FILE="${fido2Cfg.credentialPath}/$USER"

        if [ "$EUID" -ne 0 ] && [ "$USER" != "$USER" ]; then
          echo "Run as root or specify your own username"
          exit 1
        fi

        echo "Registering FIDO2 device for user: $USER"
        echo "Touch your security key when it blinks..."

        mkdir -p "${fido2Cfg.credentialPath}"

        ${pkgs.libfido2}/bin/fido2-token -L
        echo
        read -p "Enter device path (or press enter for auto): " DEVICE
        DEVICE="''${DEVICE:-auto}"

        if [ "$DEVICE" = "auto" ]; then
          ${pkgs.pam_u2f}/bin/pamu2fcfg -u "$USER" > "$CRED_FILE"
        else
          ${pkgs.pam_u2f}/bin/pamu2fcfg -u "$USER" -d "$DEVICE" > "$CRED_FILE"
        fi

        chmod 644 "$CRED_FILE"
        echo "FIDO2 credential registered for $USER"
        echo "Credential stored in: $CRED_FILE"
      '')

      (pkgs.writeShellScriptBin "fido2-test" ''
        set -euo pipefail

        USER="''${1:-$USER}"
        CRED_FILE="${fido2Cfg.credentialPath}/$USER"

        if [ ! -f "$CRED_FILE" ]; then
          echo "No FIDO2 credential found for $USER"
          echo "Run: fido2-register $USER"
          exit 1
        fi

        echo "Testing FIDO2 authentication for $USER"
        echo "Touch your security key when it blinks..."

        ${pkgs.pam_u2f}/bin/pamu2fcfg -u "$USER" -v
      '')
    ];

    # Create credentials directory
    systemd.tmpfiles.rules = [
      "d ${fido2Cfg.credentialPath} 0755 root root - -"
    ];

    # Configure PAM services
    security.pam.services = lib.genAttrs fido2Cfg.pamServices (service: {
      # When enforcing hardware keys, use the built-in u2fAuth
      u2fAuth = lib.mkIf cfg.enforceHardwareKeys true;

      # When not enforcing, add FIDO2 as optional using proper PAM rules
      rules.auth.fido2-optional = lib.mkIf (!cfg.enforceHardwareKeys && fido2Cfg.enableOptionalAuth) {
        order = 10000; # Run before standard auth
        control = "optional"; # Don't block if this fails
        modulePath = "${pkgs.pam_u2f}/lib/security/pam_u2f.so";
        args = [
          "authfile=${fido2Cfg.credentialPath}/%u"
        ] ++ lib.optionals fido2Cfg.requireTouch [ "cue" "touch=1" ]
          ++ lib.optionals fido2Cfg.requirePin [ "pin=1" ];
      };
    });

    # SSH FIDO2 support
    services.openssh.settings = {
      PubkeyAuthOptions = lib.mkIf cfg.enforceHardwareKeys "touch-required,verify-required";
    };

    # Environment for FIDO2 tools
    environment.sessionVariables = {
      FIDO_DEBUG = lib.mkIf (lib.elem "debug" config.boot.kernelParams) "1";
    };

    # Udev rules for FIDO2 devices
    services.udev.extraRules = ''
      # Allow users to access FIDO2 devices
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="2581", MODE="0664", GROUP="users", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="2581", MODE="0664", GROUP="users", TAG+="uaccess"

      # General FIDO2 device rules
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idUsage}=="3f", ATTRS{idUsagePage}=="f1d0", MODE="0664", GROUP="users", TAG+="uaccess"
    '';

    # Systemd service for credential backup (when we have the keys)
    systemd.services.fido2-credential-backup = {
      description = "Backup FIDO2 credentials to encrypted storage";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.writeShellScript "backup-fido2-creds" ''
          set -euo pipefail

          BACKUP_DIR="/var/backups/fido2-credentials"
          CRED_DIR="${fido2Cfg.credentialPath}"

          mkdir -p "$BACKUP_DIR"

          if [ -d "$CRED_DIR" ] && [ -n "$(ls -A "$CRED_DIR" 2>/dev/null)" ]; then
            tar -czf "$BACKUP_DIR/fido2-credentials-$(date +%Y%m%d).tar.gz" -C "$CRED_DIR" .

            # Keep only last 30 days of backups
            find "$BACKUP_DIR" -name "fido2-credentials-*.tar.gz" -mtime +30 -delete

            echo "FIDO2 credentials backed up to $BACKUP_DIR"
          else
            echo "No FIDO2 credentials to backup"
          fi
        ''}";
      };
    };

    # Daily backup timer
    systemd.timers.fido2-credential-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}