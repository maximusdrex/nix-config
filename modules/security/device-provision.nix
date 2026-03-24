{ config, lib, pkgs, ... }:

let
  cfg = config.security.unifiedAuth;
  provisionCfg = config.security.unifiedAuth.deviceProvision;
in
{
  options.security.unifiedAuth.deviceProvision = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable automated device provisioning";
    };

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nix-deploy/work";
      description = "Path to the NixOS configuration repository";
    };

    generateSSHKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically generate SSH keys for this device";
    };

    generateWireGuardKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically generate WireGuard keys for this device";
    };

    keyRotationDays = lib.mkOption {
      type = lib.types.int;
      default = 90;
      description = "Days before rotating generated keys";
    };

    autoCommit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Automatically commit generated keys to repository";
    };
  };

  config = lib.mkIf provisionCfg.enable {
    # Required packages and helper scripts for device provisioning
    environment.systemPackages = with pkgs; [
      openssh
      wireguard-tools
      git
    ] ++ [
      (pkgs.writeShellScriptBin "provision-device" ''
        set -euo pipefail

        HOSTNAME="''${1:-$(hostname)}"
        REPO_PATH="${provisionCfg.repoPath}"
        FORCE="''${2:-false}"

        echo "Provisioning device: $HOSTNAME"

        if [ ! -d "$REPO_PATH" ]; then
          echo "Repository not found at: $REPO_PATH"
          echo "Run git-deploy first to set up the repository"
          exit 1
        fi

        cd "$REPO_PATH"

        # Check if device already has keys
        SSH_KEY_EXISTS=false
        WG_KEY_EXISTS=false

        if [ -f "secrets/ssh/public/$HOSTNAME" ]; then
          SSH_KEY_EXISTS=true
          echo "SSH key already exists for $HOSTNAME"
        fi

        if [ -f "secrets/wireguard/public/$HOSTNAME" ]; then
          WG_KEY_EXISTS=true
          echo "WireGuard key already exists for $HOSTNAME"
        fi

        if [ "$SSH_KEY_EXISTS" = true ] && [ "$WG_KEY_EXISTS" = true ] && [ "$FORCE" != "true" ]; then
          echo "Device already provisioned. Use 'provision-device $HOSTNAME true' to force re-provisioning"
          exit 0
        fi

        CHANGES_MADE=false

        # Generate SSH key
        ${lib.optionalString provisionCfg.generateSSHKeys ''
        if [ "$SSH_KEY_EXISTS" = false ] || [ "$FORCE" = "true" ]; then
          echo "Generating SSH key for $HOSTNAME..."

          # Create directories
          mkdir -p secrets/ssh/public secrets/ssh/private

          # Generate key
          ssh-keygen -t ed25519 -f "/tmp/ssh_$HOSTNAME" -N "" -C "$HOSTNAME@$(date +%Y%m%d)"

          # Move public key to repository
          mv "/tmp/ssh_$HOSTNAME.pub" "secrets/ssh/public/$HOSTNAME"

          # Store private key securely (encrypted with OpenPGP if available)
          if command -v gpg >/dev/null && [ -n "''${GPGKEY:-}" ]; then
            export GNUPGHOME="${config.security.unifiedAuth.openpgp.keyringPath or "/etc/gpg"}"
            gpg --encrypt --armor --recipient "''${GPGKEY}" \
              --output "secrets/ssh/private/$HOSTNAME.asc" "/tmp/ssh_$HOSTNAME"
            rm "/tmp/ssh_$HOSTNAME"
          else
            echo "WARNING: No OpenPGP key available, storing private key unencrypted"
            mv "/tmp/ssh_$HOSTNAME" "secrets/ssh/private/$HOSTNAME"
            chmod 600 "secrets/ssh/private/$HOSTNAME"
          fi

          echo "SSH key generated for $HOSTNAME"
          CHANGES_MADE=true
        fi
        ''}

        # Generate WireGuard key
        ${lib.optionalString provisionCfg.generateWireGuardKeys ''
        if [ "$WG_KEY_EXISTS" = false ] || [ "$FORCE" = "true" ]; then
          echo "Generating WireGuard key for $HOSTNAME..."

          # Create directories
          mkdir -p secrets/wireguard/public secrets/wireguard/private

          # Generate key pair
          WG_PRIVATE=$(wg genkey)
          WG_PUBLIC=$(echo "$WG_PRIVATE" | wg pubkey)

          # Store public key
          echo "$WG_PUBLIC" > "secrets/wireguard/public/$HOSTNAME"

          # Store private key securely
          if command -v gpg >/dev/null && [ -n "''${GPGKEY:-}" ]; then
            export GNUPGHOME="${config.security.unifiedAuth.openpgp.keyringPath or "/etc/gpg"}"
            echo "$WG_PRIVATE" | gpg --encrypt --armor --recipient "''${GPGKEY}" \
              --output "secrets/wireguard/private/$HOSTNAME.asc"
          else
            echo "WARNING: No OpenPGP key available, storing private key unencrypted"
            echo "$WG_PRIVATE" > "secrets/wireguard/private/$HOSTNAME"
            chmod 600 "secrets/wireguard/private/$HOSTNAME"
          fi

          echo "WireGuard key generated for $HOSTNAME"
          CHANGES_MADE=true
        fi
        ''}

        # Commit changes if requested
        ${lib.optionalString provisionCfg.autoCommit ''
        if [ "$CHANGES_MADE" = true ]; then
          echo "Committing new keys to repository..."

          git add secrets/
          git commit -m "Add keys for device: $HOSTNAME

Generated on $(date -Is) by automated provisioning

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"

          echo "Keys committed to repository"
        fi
        ''}

        if [ "$CHANGES_MADE" = true ]; then
          echo "Device provisioning complete for $HOSTNAME"
          echo "New keys generated and stored in repository"

          ${lib.optionalString (!provisionCfg.autoCommit) ''
          echo "Remember to commit the changes:"
          echo "  cd $REPO_PATH"
          echo "  git add secrets/"
          echo "  git commit -m 'Add keys for device: $HOSTNAME'"
          ''}
        else
          echo "No changes needed for $HOSTNAME"
        fi
      '')

      (pkgs.writeShellScriptBin "install-device-keys" ''
        set -euo pipefail

        HOSTNAME="''${1:-$(hostname)}"
        REPO_PATH="${provisionCfg.repoPath}"

        echo "Installing keys for device: $HOSTNAME"

        if [ ! -d "$REPO_PATH" ]; then
          echo "Repository not found at: $REPO_PATH"
          exit 1
        fi

        cd "$REPO_PATH"

        # Install SSH private key
        ${lib.optionalString provisionCfg.generateSSHKeys ''
        SSH_PRIVATE_ENC="secrets/ssh/private/$HOSTNAME.asc"
        SSH_PRIVATE_PLAIN="secrets/ssh/private/$HOSTNAME"

        if [ -f "$SSH_PRIVATE_ENC" ]; then
          echo "Installing encrypted SSH private key..."
          export GNUPGHOME="${config.security.unifiedAuth.openpgp.keyringPath or "/etc/gpg"}"

          mkdir -p /etc/ssh/host_keys
          gpg --decrypt --quiet --batch --output "/etc/ssh/host_keys/ssh_host_ed25519_key" "$SSH_PRIVATE_ENC"
          chmod 600 "/etc/ssh/host_keys/ssh_host_ed25519_key"

          # Generate public key from private key
          ssh-keygen -y -f "/etc/ssh/host_keys/ssh_host_ed25519_key" > "/etc/ssh/host_keys/ssh_host_ed25519_key.pub"

          echo "SSH private key installed"
        elif [ -f "$SSH_PRIVATE_PLAIN" ]; then
          echo "Installing plaintext SSH private key..."
          mkdir -p /etc/ssh/host_keys
          cp "$SSH_PRIVATE_PLAIN" "/etc/ssh/host_keys/ssh_host_ed25519_key"
          chmod 600 "/etc/ssh/host_keys/ssh_host_ed25519_key"

          # Generate public key from private key
          ssh-keygen -y -f "/etc/ssh/host_keys/ssh_host_ed25519_key" > "/etc/ssh/host_keys/ssh_host_ed25519_key.pub"

          echo "SSH private key installed"
        else
          echo "No SSH private key found for $HOSTNAME"
        fi
        ''}

        # Install WireGuard private key
        ${lib.optionalString provisionCfg.generateWireGuardKeys ''
        WG_PRIVATE_ENC="secrets/wireguard/private/$HOSTNAME.asc"
        WG_PRIVATE_PLAIN="secrets/wireguard/private/$HOSTNAME"

        if [ -f "$WG_PRIVATE_ENC" ]; then
          echo "Installing encrypted WireGuard private key..."
          export GNUPGHOME="${config.security.unifiedAuth.openpgp.keyringPath or "/etc/gpg"}"

          mkdir -p /etc/wireguard
          gpg --decrypt --quiet --batch --output "/etc/wireguard/privatekey" "$WG_PRIVATE_ENC"
          chmod 600 "/etc/wireguard/privatekey"

          echo "WireGuard private key installed"
        elif [ -f "$WG_PRIVATE_PLAIN" ]; then
          echo "Installing plaintext WireGuard private key..."
          mkdir -p /etc/wireguard
          cp "$WG_PRIVATE_PLAIN" "/etc/wireguard/privatekey"
          chmod 600 "/etc/wireguard/privatekey"

          echo "WireGuard private key installed"
        else
          echo "No WireGuard private key found for $HOSTNAME"
        fi
        ''}

        echo "Key installation complete for $HOSTNAME"
      '')

      (pkgs.writeShellScriptBin "rotate-device-keys" ''
        set -euo pipefail

        HOSTNAME="''${1:-$(hostname)}"
        DAYS="''${2:-${toString provisionCfg.keyRotationDays}}"

        echo "Checking if key rotation is needed for $HOSTNAME (>$DAYS days old)"

        REPO_PATH="${provisionCfg.repoPath}"
        cd "$REPO_PATH"

        NEEDS_ROTATION=false

        # Check SSH key age
        if [ -f "secrets/ssh/public/$HOSTNAME" ]; then
          SSH_AGE=$(( ($(date +%s) - $(stat -c %Y "secrets/ssh/public/$HOSTNAME")) / 86400 ))
          echo "SSH key age: $SSH_AGE days"
          if [ "$SSH_AGE" -gt "$DAYS" ]; then
            NEEDS_ROTATION=true
          fi
        fi

        # Check WireGuard key age
        if [ -f "secrets/wireguard/public/$HOSTNAME" ]; then
          WG_AGE=$(( ($(date +%s) - $(stat -c %Y "secrets/wireguard/public/$HOSTNAME")) / 86400 ))
          echo "WireGuard key age: $WG_AGE days"
          if [ "$WG_AGE" -gt "$DAYS" ]; then
            NEEDS_ROTATION=true
          fi
        fi

        if [ "$NEEDS_ROTATION" = true ]; then
          echo "Key rotation needed for $HOSTNAME"
          provision-device "$HOSTNAME" true
        else
          echo "Keys are still fresh for $HOSTNAME"
        fi
      '')
    ];

    # Systemd service for automated key rotation
    systemd.services.device-key-rotation = {
      description = "Rotate device keys if needed";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.bash}/bin/bash -c 'rotate-device-keys'";
      };
    };

    # Weekly key rotation check
    systemd.timers.device-key-rotation = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };

    # Ensure required directories exist
    systemd.tmpfiles.rules = [
      "d /etc/ssh/host_keys 0700 root root - -"
      "d /etc/wireguard 0700 root root - -"
    ];
  };
}