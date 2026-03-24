{ config, lib, pkgs, ... }:

let
  cfg = config.security.unifiedAuth;
  driveCfg = config.security.unifiedAuth.encryptedDrive;
in
{
  options.security.unifiedAuth.encryptedDrive = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable FIDO2 encrypted drive support";
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          device = lib.mkOption {
            type = lib.types.str;
            description = "Block device path (e.g., /dev/nvme0n1p2)";
            example = "/dev/nvme0n1p2";
          };

          enableFIDO2 = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable FIDO2 unlock for this device";
          };

          enablePassword = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Keep password unlock as fallback";
          };

          enableRecovery = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable recovery key";
          };

          fidoDevices = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "auto" ];
            description = "FIDO2 device paths or 'auto' for auto-detection";
          };

          keySlot = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "LUKS key slot for FIDO2 credential";
          };

          passwordSlot = lib.mkOption {
            type = lib.types.int;
            default = 1;
            description = "LUKS key slot for password";
          };

          recoverySlot = lib.mkOption {
            type = lib.types.int;
            default = 2;
            description = "LUKS key slot for recovery key";
          };
        };
      });
      default = {};
      description = "Encrypted devices to configure";
      example = {
        root = {
          device = "/dev/nvme0n1p2";
          enableFIDO2 = true;
          enablePassword = true;
          enableRecovery = true;
        };
      };
    };

    recoveryKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/luks-recovery";
      description = "Path to store encrypted recovery keys";
    };

    timeout = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "FIDO2 unlock timeout in seconds";
    };
  };

  config = lib.mkIf driveCfg.enable {
    # Required packages and helper scripts for FIDO2 LUKS support
    environment.systemPackages = with pkgs; [
      systemd  # systemd-cryptenroll
      cryptsetup
      libfido2
    ] ++ [
      (pkgs.writeShellScriptBin "luks-setup-fido2" ''
        set -euo pipefail

        DEVICE="''${1:-}"
        CONFIG_NAME="''${2:-}"

        if [ -z "$DEVICE" ]; then
          echo "Usage: luks-setup-fido2 <device> [config-name]"
          echo "Example: luks-setup-fido2 /dev/nvme0n1p2 root"
          exit 1
        fi

        if [ ! -b "$DEVICE" ]; then
          echo "Device $DEVICE does not exist or is not a block device"
          exit 1
        fi

        # Check if device is already LUKS formatted
        if ! cryptsetup isLuks "$DEVICE"; then
          echo "Device $DEVICE is not LUKS formatted"
          echo "Format it first with: cryptsetup luksFormat $DEVICE"
          exit 1
        fi

        echo "Setting up FIDO2 unlock for $DEVICE"

        # Get configuration if provided
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: deviceCfg: ''
        if [ "$CONFIG_NAME" = "${name}" ]; then
          FIDO_DEVICES="${lib.concatStringsSep " " deviceCfg.fidoDevices}"
          KEY_SLOT="${toString deviceCfg.keySlot}"
          PASSWORD_SLOT="${toString deviceCfg.passwordSlot}"
          RECOVERY_SLOT="${toString deviceCfg.recoverySlot}"
          ENABLE_PASSWORD="${lib.boolToString deviceCfg.enablePassword}"
          ENABLE_RECOVERY="${lib.boolToString deviceCfg.enableRecovery}"
        fi
        '') driveCfg.devices)}

        # Set defaults if no config provided
        FIDO_DEVICES="''${FIDO_DEVICES:-auto}"
        KEY_SLOT="''${KEY_SLOT:-0}"
        PASSWORD_SLOT="''${PASSWORD_SLOT:-1}"
        RECOVERY_SLOT="''${RECOVERY_SLOT:-2}"
        ENABLE_PASSWORD="''${ENABLE_PASSWORD:-true}"
        ENABLE_RECOVERY="''${ENABLE_RECOVERY:-true}"

        echo "Configuration:"
        echo "  FIDO2 devices: $FIDO_DEVICES"
        echo "  FIDO2 key slot: $KEY_SLOT"
        echo "  Password slot: $PASSWORD_SLOT"
        echo "  Recovery slot: $RECOVERY_SLOT"
        echo "  Enable password: $ENABLE_PASSWORD"
        echo "  Enable recovery: $ENABLE_RECOVERY"

        # Backup existing LUKS header
        BACKUP_FILE="${driveCfg.recoveryKeyPath}/luks-header-$(basename "$DEVICE")-$(date +%Y%m%d-%H%M%S).img"
        echo "Backing up LUKS header to: $BACKUP_FILE"
        cryptsetup luksHeaderBackup "$DEVICE" --header-backup-file "$BACKUP_FILE"

        # Enroll FIDO2 device
        echo "Enrolling FIDO2 device(s)..."
        echo "Touch your security key when it blinks..."

        if [ "$FIDO_DEVICES" = "auto" ]; then
          systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=false "$DEVICE"
        else
          for fido_device in $FIDO_DEVICES; do
            systemd-cryptenroll --fido2-device="$fido_device" --fido2-with-client-pin=false "$DEVICE"
          done
        fi

        echo "FIDO2 enrollment complete!"

        # Generate recovery key if enabled
        if [ "$ENABLE_RECOVERY" = "true" ]; then
          echo "Generating recovery key..."
          RECOVERY_KEY=$(systemd-cryptenroll --recovery-key "$DEVICE" | grep "Recovery key is" | cut -d: -f2 | tr -d ' ')

          # Store recovery key securely
          RECOVERY_FILE="${driveCfg.recoveryKeyPath}/recovery-$(basename "$DEVICE")-$(date +%Y%m%d-%H%M%S).key"

          # Encrypt recovery key with OpenPGP if available
          if command -v gpg >/dev/null && [ -n "''${GPGKEY:-}" ]; then
            export GNUPGHOME="${config.security.unifiedAuth.openpgp.keyringPath or "/etc/gpg"}"
            echo "$RECOVERY_KEY" | gpg --encrypt --armor --recipient "''${GPGKEY}" \
              --output "$RECOVERY_FILE.asc"
            echo "Recovery key encrypted and stored in: $RECOVERY_FILE.asc"
          else
            echo "$RECOVERY_KEY" > "$RECOVERY_FILE"
            chmod 600 "$RECOVERY_FILE"
            echo "Recovery key stored in: $RECOVERY_FILE"
            echo "WARNING: Recovery key is stored in plaintext!"
          fi

          echo "Recovery key: $RECOVERY_KEY"
          echo "Store this recovery key in a safe place!"
        fi

        # Show current key slots
        echo
        echo "Current LUKS key slots:"
        cryptsetup luksDump "$DEVICE" | grep "Key Slot"

        echo
        echo "FIDO2 setup complete for $DEVICE"
        echo "You can now unlock this device with your security key"
      '')

      (pkgs.writeShellScriptBin "luks-test-fido2" ''
        set -euo pipefail

        DEVICE="''${1:-}"

        if [ -z "$DEVICE" ]; then
          echo "Usage: luks-test-fido2 <device>"
          echo "Example: luks-test-fido2 /dev/nvme0n1p2"
          exit 1
        fi

        if [ ! -b "$DEVICE" ]; then
          echo "Device $DEVICE does not exist or is not a block device"
          exit 1
        fi

        echo "Testing FIDO2 unlock for $DEVICE"
        echo "Touch your security key when it blinks..."

        # Create a temporary mapper name
        MAPPER_NAME="luks-test-$(basename "$DEVICE")"

        # Try to unlock with FIDO2
        if systemd-cryptsetup attach "$MAPPER_NAME" "$DEVICE" - fido2-device=auto,headless=1; then
          echo "SUCCESS: FIDO2 unlock works!"

          # Immediately close the test mapping
          systemd-cryptsetup detach "$MAPPER_NAME"
          echo "Test mapping closed"
        else
          echo "FAILED: FIDO2 unlock failed"
          echo "Check if:"
          echo "  1. FIDO2 device is plugged in"
          echo "  2. FIDO2 credential is enrolled for this device"
          echo "  3. systemd version supports FIDO2 (>= 248)"
        fi
      '')

      (pkgs.writeShellScriptBin "luks-remove-fido2" ''
        set -euo pipefail

        DEVICE="''${1:-}"
        SLOT="''${2:-}"

        if [ -z "$DEVICE" ]; then
          echo "Usage: luks-remove-fido2 <device> [slot]"
          echo "Example: luks-remove-fido2 /dev/nvme0n1p2 0"
          exit 1
        fi

        if [ ! -b "$DEVICE" ]; then
          echo "Device $DEVICE does not exist or is not a block device"
          exit 1
        fi

        echo "Current LUKS key slots:"
        cryptsetup luksDump "$DEVICE" | grep "Key Slot"

        if [ -n "$SLOT" ]; then
          echo "Removing FIDO2 credential from slot $SLOT on $DEVICE"
          systemd-cryptenroll --wipe-slot="$SLOT" "$DEVICE"
        else
          echo "Removing all FIDO2 credentials from $DEVICE"
          systemd-cryptenroll --fido2-device=list "$DEVICE" || true
          systemd-cryptenroll --wipe-slot=fido2 "$DEVICE"
        fi

        echo "FIDO2 credentials removed"
      '')

      (pkgs.writeShellScriptBin "luks-backup-headers" ''
        set -euo pipefail

        BACKUP_DIR="${driveCfg.recoveryKeyPath}/headers"
        mkdir -p "$BACKUP_DIR"

        echo "Backing up LUKS headers for all configured devices..."

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: deviceCfg: ''
        DEVICE="${deviceCfg.device}"
        if [ -b "$DEVICE" ] && cryptsetup isLuks "$DEVICE"; then
          BACKUP_FILE="$BACKUP_DIR/luks-header-${name}-$(date +%Y%m%d-%H%M%S).img"
          echo "Backing up $DEVICE to $BACKUP_FILE"
          cryptsetup luksHeaderBackup "$DEVICE" --header-backup-file "$BACKUP_FILE"
        else
          echo "Skipping $DEVICE (not a LUKS device)"
        fi
        '') driveCfg.devices)}

        echo "LUKS header backups complete"
        echo "Backup directory: $BACKUP_DIR"
        ls -la "$BACKUP_DIR"
      '')
    ];

    # Ensure systemd version supports FIDO2
    assertions = [
      {
        assertion = lib.versionAtLeast pkgs.systemd.version "248";
        message = "FIDO2 LUKS support requires systemd >= 248";
      }
    ];

    # Create recovery key directory
    systemd.tmpfiles.rules = [
      "d ${driveCfg.recoveryKeyPath} 0700 root root - -"
    ];

    # Boot configuration for FIDO2 devices
    boot.initrd.systemd.enable = true;  # Required for FIDO2 support

    # Configure crypttab entries for systemd-cryptsetup
    environment.etc.crypttab.text = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: deviceCfg:
        lib.optionalString deviceCfg.enableFIDO2
          "${name} ${deviceCfg.device} - fido2-device=auto,timeout=${toString driveCfg.timeout}s"
      ) driveCfg.devices
    );

    # Systemd service for FIDO2 device monitoring
    systemd.services.fido2-device-monitor = {
      description = "Monitor FIDO2 devices for encrypted drive unlock";
      serviceConfig = {
        Type = "simple";
        User = "root";
        ExecStart = "${pkgs.writeShellScript "fido2-monitor" ''
          set -euo pipefail

          echo "Starting FIDO2 device monitor..."

          while true; do
            # Check if any FIDO2 devices are available
            DEVICES=$(${pkgs.libfido2}/bin/fido2-token -L 2>/dev/null | wc -l || echo 0)

            if [ "$DEVICES" -gt 0 ]; then
              echo "$(date): $DEVICES FIDO2 device(s) detected"
            else
              echo "$(date): No FIDO2 devices detected"
            fi

            sleep 60
          done
        ''}";
        Restart = "always";
        RestartSec = "10";
      };
      wantedBy = [ "multi-user.target" ];
    };

    # Weekly LUKS header backup
    systemd.services.luks-header-backup = {
      description = "Backup LUKS headers";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.bash}/bin/bash -c 'luks-backup-headers'";
      };
    };

    systemd.timers.luks-header-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };
  };
}