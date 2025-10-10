{ config, lib, pkgs, ... }:

let
  cfg = config.security.unifiedAuth;
  rotationCfg = config.security.unifiedAuth.keyRotation;
in
{
  options.security.unifiedAuth.keyRotation = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable automated key rotation";
    };

    schedules = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          keyType = lib.mkOption {
            type = lib.types.enum [ "ssh" "wireguard" "all" ];
            description = "Type of keys to rotate";
          };

          intervalDays = lib.mkOption {
            type = lib.types.int;
            default = 90;
            description = "Rotation interval in days";
          };

          calendar = lib.mkOption {
            type = lib.types.str;
            default = "monthly";
            description = "Systemd calendar specification for rotation";
          };

          hostPattern = lib.mkOption {
            type = lib.types.str;
            default = "*";
            description = "Host pattern to match for rotation";
          };

          notifyEmail = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Email address to notify of rotation events";
          };
        };
      });
      default = {
        monthly = {
          keyType = "all";
          intervalDays = 90;
          calendar = "monthly";
          hostPattern = "*";
        };
      };
      description = "Key rotation schedules";
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run in dry-run mode (don't actually rotate keys)";
    };

    backupPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/backups/key-rotation";
      description = "Path to store key rotation backups";
    };

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nix-deploy/work";
      description = "Path to the NixOS configuration repository";
    };
  };

  config = lib.mkIf rotationCfg.enable {
    # Required packages and key rotation script
    environment.systemPackages = with pkgs; [
      git
      openssh
      wireguard-tools
    ] ++ [
      (pkgs.writeShellScriptBin "rotate-keys" ''
        set -euo pipefail

        SCHEDULE="''${1:-monthly}"
        DRY_RUN="${lib.boolToString rotationCfg.dryRun}"
        REPO_PATH="${rotationCfg.repoPath}"
        BACKUP_PATH="${rotationCfg.backupPath}"

        echo "Starting key rotation for schedule: $SCHEDULE"
        echo "Dry run mode: $DRY_RUN"

        if [ ! -d "$REPO_PATH" ]; then
          echo "Repository not found at: $REPO_PATH"
          exit 1
        fi

        cd "$REPO_PATH"

        # Create backup directory
        BACKUP_DIR="$BACKUP_PATH/$(date +%Y%m%d-%H%M%S)-$SCHEDULE"
        mkdir -p "$BACKUP_DIR"

        # Get schedule configuration
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: schedule: ''
        if [ "$SCHEDULE" = "${name}" ]; then
          KEY_TYPE="${schedule.keyType}"
          INTERVAL_DAYS="${toString schedule.intervalDays}"
          HOST_PATTERN="${schedule.hostPattern}"
          NOTIFY_EMAIL="${if schedule.notifyEmail != null then schedule.notifyEmail else ""}"
        fi
        '') rotationCfg.schedules)}

        if [ -z "''${KEY_TYPE:-}" ]; then
          echo "Unknown schedule: $SCHEDULE"
          echo "Available schedules: ${lib.concatStringsSep " " (lib.attrNames rotationCfg.schedules)}"
          exit 1
        fi

        echo "Schedule: $SCHEDULE"
        echo "Key type: $KEY_TYPE"
        echo "Interval: $INTERVAL_DAYS days"
        echo "Host pattern: $HOST_PATTERN"

        ROTATED_HOSTS=()
        FAILED_HOSTS=()

        # Function to check if key needs rotation
        needs_rotation() {
          local key_file="$1"
          local interval="$2"

          if [ ! -f "$key_file" ]; then
            return 1  # File doesn't exist, can't rotate
          fi

          local age_days=$(( ($(date +%s) - $(stat -c %Y "$key_file")) / 86400 ))
          [ "$age_days" -gt "$interval" ]
        }

        # Function to backup and rotate SSH key
        rotate_ssh_key() {
          local hostname="$1"

          echo "Checking SSH key for $hostname..."

          local pub_key="secrets/ssh/public/$hostname"
          local priv_key_enc="secrets/ssh/private/$hostname.asc"
          local priv_key_plain="secrets/ssh/private/$hostname"

          if needs_rotation "$pub_key" "$INTERVAL_DAYS"; then
            echo "SSH key for $hostname needs rotation (age: $(( ($(date +%s) - $(stat -c %Y "$pub_key")) / 86400 )) days)"

            # Backup existing keys
            if [ -f "$pub_key" ]; then
              cp "$pub_key" "$BACKUP_DIR/ssh-public-$hostname"
            fi
            if [ -f "$priv_key_enc" ]; then
              cp "$priv_key_enc" "$BACKUP_DIR/ssh-private-$hostname.asc"
            elif [ -f "$priv_key_plain" ]; then
              cp "$priv_key_plain" "$BACKUP_DIR/ssh-private-$hostname"
            fi

            if [ "$DRY_RUN" = "false" ]; then
              # Generate new SSH key
              echo "Generating new SSH key for $hostname..."

              ssh-keygen -t ed25519 -f "/tmp/ssh_$hostname" -N "" -C "$hostname@$(date +%Y%m%d)-rotated"

              # Replace public key
              mv "/tmp/ssh_$hostname.pub" "$pub_key"

              # Replace private key (encrypted if possible)
              if command -v gpg >/dev/null && [ -n "''${GPGKEY:-}" ]; then
                export GNUPGHOME="${if config.security.unifiedAuth.openpgp.enable then config.security.unifiedAuth.openpgp.keyringPath else "/etc/gpg"}"
                gpg --encrypt --armor --recipient "''${GPGKEY}" \
                  --output "$priv_key_enc" "/tmp/ssh_$hostname"
                rm "/tmp/ssh_$hostname"
                # Remove old plaintext key if it exists
                [ -f "$priv_key_plain" ] && rm "$priv_key_plain"
              else
                mv "/tmp/ssh_$hostname" "$priv_key_plain"
                chmod 600 "$priv_key_plain"
                # Remove old encrypted key if it exists
                [ -f "$priv_key_enc" ] && rm "$priv_key_enc"
              fi

              echo "SSH key rotated for $hostname"
              return 0
            else
              echo "DRY RUN: Would rotate SSH key for $hostname"
              return 0
            fi
          else
            echo "SSH key for $hostname is still fresh"
            return 1
          fi
        }

        # Function to backup and rotate WireGuard key
        rotate_wireguard_key() {
          local hostname="$1"

          echo "Checking WireGuard key for $hostname..."

          local pub_key="secrets/wireguard/public/$hostname"
          local priv_key_enc="secrets/wireguard/private/$hostname.asc"
          local priv_key_plain="secrets/wireguard/private/$hostname"

          if needs_rotation "$pub_key" "$INTERVAL_DAYS"; then
            echo "WireGuard key for $hostname needs rotation (age: $(( ($(date +%s) - $(stat -c %Y "$pub_key")) / 86400 )) days)"

            # Backup existing keys
            if [ -f "$pub_key" ]; then
              cp "$pub_key" "$BACKUP_DIR/wg-public-$hostname"
            fi
            if [ -f "$priv_key_enc" ]; then
              cp "$priv_key_enc" "$BACKUP_DIR/wg-private-$hostname.asc"
            elif [ -f "$priv_key_plain" ]; then
              cp "$priv_key_plain" "$BACKUP_DIR/wg-private-$hostname"
            fi

            if [ "$DRY_RUN" = "false" ]; then
              # Generate new WireGuard key
              echo "Generating new WireGuard key for $hostname..."

              WG_PRIVATE=$(wg genkey)
              WG_PUBLIC=$(echo "$WG_PRIVATE" | wg pubkey)

              # Replace public key
              echo "$WG_PUBLIC" > "$pub_key"

              # Replace private key (encrypted if possible)
              if command -v gpg >/dev/null && [ -n "''${GPGKEY:-}" ]; then
                export GNUPGHOME="${if config.security.unifiedAuth.openpgp.enable then config.security.unifiedAuth.openpgp.keyringPath else "/etc/gpg"}"
                echo "$WG_PRIVATE" | gpg --encrypt --armor --recipient "''${GPGKEY}" \
                  --output "$priv_key_enc"
                # Remove old plaintext key if it exists
                [ -f "$priv_key_plain" ] && rm "$priv_key_plain"
              else
                echo "$WG_PRIVATE" > "$priv_key_plain"
                chmod 600 "$priv_key_plain"
                # Remove old encrypted key if it exists
                [ -f "$priv_key_enc" ] && rm "$priv_key_enc"
              fi

              echo "WireGuard key rotated for $hostname"
              return 0
            else
              echo "DRY RUN: Would rotate WireGuard key for $hostname"
              return 0
            fi
          else
            echo "WireGuard key for $hostname is still fresh"
            return 1
          fi
        }

        # Find hosts matching pattern
        HOSTS=()
        if [ "$HOST_PATTERN" = "*" ]; then
          # Get all hosts from SSH and WireGuard directories
          for dir in secrets/ssh/public secrets/wireguard/public; do
            if [ -d "$dir" ]; then
              for key_file in "$dir"/*; do
                [ -f "$key_file" ] && HOSTS+=($(basename "$key_file"))
              done
            fi
          done
          # Remove duplicates
          HOSTS=($(printf '%s\n' "''${HOSTS[@]}" | sort -u))
        else
          # Use pattern matching
          for dir in secrets/ssh/public secrets/wireguard/public; do
            if [ -d "$dir" ]; then
              for key_file in "$dir"/$HOST_PATTERN; do
                [ -f "$key_file" ] && HOSTS+=($(basename "$key_file"))
              done
            fi
          done
          HOSTS=($(printf '%s\n' "''${HOSTS[@]}" | sort -u))
        fi

        echo "Found hosts: ''${HOSTS[*]}"

        # Process each host
        for hostname in "''${HOSTS[@]}"; do
          echo
          echo "Processing host: $hostname"

          ROTATED=false

          if [ "$KEY_TYPE" = "ssh" ] || [ "$KEY_TYPE" = "all" ]; then
            if rotate_ssh_key "$hostname"; then
              ROTATED=true
            fi
          fi

          if [ "$KEY_TYPE" = "wireguard" ] || [ "$KEY_TYPE" = "all" ]; then
            if rotate_wireguard_key "$hostname"; then
              ROTATED=true
            fi
          fi

          if [ "$ROTATED" = true ]; then
            ROTATED_HOSTS+=("$hostname")
          fi
        done

        # Commit changes if not dry run and there were rotations
        if [ "$DRY_RUN" = "false" ] && [ "''${#ROTATED_HOSTS[@]}" -gt 0 ]; then
          echo
          echo "Committing rotated keys..."

          git add secrets/
          git commit -m "Rotate keys for hosts: ''${ROTATED_HOSTS[*]}

Rotation schedule: $SCHEDULE
Key type: $KEY_TYPE
Rotated on: $(date -Is)

Backup stored in: $BACKUP_DIR

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

          echo "Keys committed to repository"
        fi

        # Summary
        echo
        echo "Key rotation summary:"
        echo "Schedule: $SCHEDULE"
        echo "Dry run: $DRY_RUN"
        echo "Hosts processed: ''${#HOSTS[@]}"
        echo "Hosts rotated: ''${#ROTATED_HOSTS[@]}"
        echo "Backup directory: $BACKUP_DIR"

        if [ "''${#ROTATED_HOSTS[@]}" -gt 0 ]; then
          echo "Rotated hosts: ''${ROTATED_HOSTS[*]}"
        fi

        if [ "''${#FAILED_HOSTS[@]}" -gt 0 ]; then
          echo "Failed hosts: ''${FAILED_HOSTS[*]}"
        fi

        # Send notification if configured
        if [ -n "$NOTIFY_EMAIL" ] && [ "''${#ROTATED_HOSTS[@]}" -gt 0 ]; then
          if command -v mail >/dev/null; then
            {
              echo "Key rotation completed:"
              echo "Schedule: $SCHEDULE"
              echo "Rotated hosts: ''${ROTATED_HOSTS[*]}"
              echo "Backup: $BACKUP_DIR"
            } | mail -s "Key rotation: $SCHEDULE" "$NOTIFY_EMAIL"
          fi
        fi
      '')
    ];

    # Create backup directory
    systemd.tmpfiles.rules = [
      "d ${rotationCfg.backupPath} 0700 root root - -"
    ];

    # Systemd services for each rotation schedule
    systemd.services = lib.mapAttrs' (name: schedule:
      lib.nameValuePair "key-rotation-${name}" {
        description = "Key rotation: ${name}";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          ExecStart = "${pkgs.bash}/bin/bash -c 'rotate-keys ${name}'";
        };
      }
    ) rotationCfg.schedules;

    # Systemd timers for each rotation schedule
    systemd.timers = lib.mapAttrs' (name: schedule:
      lib.nameValuePair "key-rotation-${name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = schedule.calendar;
          Persistent = true;
        };
      }
    ) rotationCfg.schedules;
  };
}