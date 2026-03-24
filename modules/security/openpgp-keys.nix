{ config, lib, pkgs, ... }:

let
  cfg = config.security.unifiedAuth;
  pgpCfg = config.security.unifiedAuth.openpgp;
in
{
  options.security.unifiedAuth.openpgp = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable OpenPGP key management";
    };

    keyringPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/gpg";
      description = "System-wide GPG keyring path";
    };

    deviceKeyId = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Device identifier for OpenPGP operations";
    };

    publicKeysPath = lib.mkOption {
      type = lib.types.str;
      default = "secrets/pgp/public-keys";
      description = "Path to public keys directory in repository";
    };

    autoImport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically import public keys from repository";
    };

    cardReaderSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable smart card reader support for OpenPGP cards";
    };

    gitCryptKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/git-crypt/keys/default";
      description = "Path to git-crypt key file";
    };
  };

  config = lib.mkIf pgpCfg.enable {
    # Required packages and helper scripts
    environment.systemPackages = with pkgs; [
      gnupg
      paperkey
      qrencode
      pinentry-curses
      pinentry-gtk2
    ] ++ lib.optionals pgpCfg.cardReaderSupport [
      pcsclite
      ccid
    ] ++ [
      # Helper scripts for key management
      (pkgs.writeShellScriptBin "pgp-setup" ''
        set -euo pipefail

        GPG_HOME="${pgpCfg.keyringPath}"
        export GNUPGHOME="$GPG_HOME"

        echo "Setting up OpenPGP infrastructure..."

        # Initialize GPG directory
        mkdir -p "$GPG_HOME"
        chmod 700 "$GPG_HOME"

        # Check for smart card
        ${lib.optionalString pgpCfg.cardReaderSupport ''
        if ${pkgs.gnupg}/bin/gpg --card-status >/dev/null 2>&1; then
          echo "Smart card detected!"
          ${pkgs.gnupg}/bin/gpg --card-status
        else
          echo "No smart card detected. Insert your OpenPGP card and run again."
        fi
        ''}
        ${lib.optionalString (!pgpCfg.cardReaderSupport) ''
        echo "Smart card support disabled in configuration"
        ''}

        echo "GPG setup complete. GPG home: $GPG_HOME"
      '')

      (pkgs.writeShellScriptBin "git-crypt-unlock" ''
        set -euo pipefail

        REPO_ROOT="''${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
        export GNUPGHOME="${pgpCfg.keyringPath}"

        echo "Unlocking git-crypt repository with device key..."

        cd "$REPO_ROOT"

        # Git-crypt will automatically use any available private key that can decrypt
        if ${pkgs.git-crypt}/bin/git-crypt unlock; then
          echo "Repository unlocked successfully!"
        else
          echo "Failed to unlock repository. Possible causes:"
          echo "  1. No OpenPGP private key available for this device"
          echo "  2. Device key not added to git-crypt"
          echo "  3. Security key not inserted or unlocked"
          exit 1
        fi
      '')

      (pkgs.writeShellScriptBin "git-crypt-add-device" ''
        set -euo pipefail

        DEVICE_NAME="''${1:-${pgpCfg.deviceKeyId}}"
        REPO_ROOT="''${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
        export GNUPGHOME="${pgpCfg.keyringPath}"

        echo "Adding device '$DEVICE_NAME' to git-crypt..."

        cd "$REPO_ROOT"

        # Check if repository is git-crypt enabled
        if [ ! -d ".git/git-crypt" ]; then
          echo "Repository not initialized with git-crypt. Run: git-crypt init"
          exit 1
        fi

        # Get the device's public key
        PUBKEY_FILE="${pgpCfg.publicKeysPath}/$DEVICE_NAME.asc"

        if [ -f "$PUBKEY_FILE" ]; then
          echo "Using existing public key: $PUBKEY_FILE"
          # Import the public key
          ${pkgs.gnupg}/bin/gpg --import "$PUBKEY_FILE"
        else
          echo "Public key not found at: $PUBKEY_FILE"
          echo "Export your public key first with: gpg-export-device-key"
          exit 1
        fi

        # Get the key ID
        KEY_ID=$(${pkgs.gnupg}/bin/gpg --list-keys --with-colons "$DEVICE_NAME" | grep '^pub:' | head -1 | cut -d: -f5)

        if [ -z "$KEY_ID" ]; then
          echo "Could not find key ID for device: $DEVICE_NAME"
          exit 1
        fi

        echo "Adding key $KEY_ID to git-crypt..."

        # Add the key to git-crypt
        ${pkgs.git-crypt}/bin/git-crypt add-gpg-user "$KEY_ID"

        echo "Device '$DEVICE_NAME' added to git-crypt successfully!"
        echo "Commit the changes with: git commit -m 'Add $DEVICE_NAME to git-crypt'"
      '')

      (pkgs.writeShellScriptBin "gpg-export-device-key" ''
        set -euo pipefail

        DEVICE_NAME="''${1:-${pgpCfg.deviceKeyId}}"
        REPO_ROOT="''${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
        export GNUPGHOME="${pgpCfg.keyringPath}"

        echo "Exporting public key for device: $DEVICE_NAME"

        # Create public keys directory
        PUBKEY_DIR="$REPO_ROOT/${pgpCfg.publicKeysPath}"
        mkdir -p "$PUBKEY_DIR"

        PUBKEY_FILE="$PUBKEY_DIR/$DEVICE_NAME.asc"

        # Export public key
        if ${pkgs.gnupg}/bin/gpg --armor --export "$DEVICE_NAME" > "$PUBKEY_FILE"; then
          echo "Public key exported to: $PUBKEY_FILE"
          echo "Commit this file to the repository:"
          echo "  git add $PUBKEY_FILE"
          echo "  git commit -m 'Add public key for $DEVICE_NAME'"
        else
          echo "Failed to export public key for: $DEVICE_NAME"
          echo "Make sure you have a key for this device in your keyring"
          exit 1
        fi
      '')

      (pkgs.writeShellScriptBin "openpgp-backup" ''
        set -euo pipefail

        export GNUPGHOME="${pgpCfg.keyringPath}"
        BACKUP_DIR="/var/backups/openpgp"
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)

        mkdir -p "$BACKUP_DIR"

        echo "Creating OpenPGP backup..."

        # Export all keys
        ${pkgs.gnupg}/bin/gpg --export --armor > "$BACKUP_DIR/public-keys-$TIMESTAMP.asc"
        ${pkgs.gnupg}/bin/gpg --export-secret-keys --armor > "$BACKUP_DIR/secret-keys-$TIMESTAMP.asc"

        # Create paper backup
        if command -v ${pkgs.paperkey}/bin/paperkey >/dev/null; then
          ${pkgs.gnupg}/bin/gpg --export-secret-keys | \
            ${pkgs.paperkey}/bin/paperkey --output "$BACKUP_DIR/paperkey-$TIMESTAMP.txt"

          # Create QR codes for paper backup
          if command -v ${pkgs.qrencode}/bin/qrencode >/dev/null; then
            ${pkgs.qrencode}/bin/qrencode -t PNG -o "$BACKUP_DIR/paperkey-$TIMESTAMP.png" \
              < "$BACKUP_DIR/paperkey-$TIMESTAMP.txt"
          fi
        fi

        # Set proper permissions
        chmod 600 "$BACKUP_DIR"/*-$TIMESTAMP.*

        echo "Backup created in: $BACKUP_DIR"
        echo "Files created:"
        ls -la "$BACKUP_DIR"/*-$TIMESTAMP.*
      '')
    ];

    # GPG agent configuration
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = if config.services.xserver.enable
        then pkgs.pinentry-gtk2
        else pkgs.pinentry-curses;
    };

    # Smart card support
    services.pcscd.enable = pgpCfg.cardReaderSupport;

    # Create system GPG directory
    systemd.tmpfiles.rules = [
      "d ${pgpCfg.keyringPath} 0700 root root - -"
      "d ${builtins.dirOf pgpCfg.gitCryptKeyPath} 0700 root root - -"
    ];

    # GPG configuration for system use
    environment.etc."gpg/gpg.conf".text = ''
      # Security settings
      personal-cipher-preferences AES256 AES192 AES
      personal-digest-preferences SHA512 SHA384 SHA256
      personal-compress-preferences ZLIB BZIP2 ZIP Uncompressed
      default-preference-list SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed
      cert-digest-algo SHA512
      s2k-digest-algo SHA512
      s2k-cipher-algo AES256
      charset utf-8
      fixed-list-mode
      no-comments
      no-emit-version
      keyid-format 0xlong
      list-options show-uid-validity
      verify-options show-uid-validity
      with-fingerprint
      require-cross-certification
      no-symkey-cache
      use-agent
      throw-keyids

      # Keyserver settings
      keyserver hkps://keys.openpgp.org
      keyserver-options no-honor-keyserver-url include-revoked

      # Smart card settings
      ${lib.optionalString pgpCfg.cardReaderSupport ''
      reader-port "$(pcscd)"
      card-timeout 5
      ''}
    '';

    environment.etc."gpg/gpg-agent.conf".text = ''
      pinentry-program ${if config.services.xserver.enable
        then "${pkgs.pinentry-gtk2}/bin/pinentry-gtk2"
        else "${pkgs.pinentry-curses}/bin/pinentry-curses"}

      default-cache-ttl 600
      max-cache-ttl 7200
      enable-ssh-support

      ${lib.optionalString pgpCfg.cardReaderSupport ''
      scdaemon-program ${pkgs.gnupg}/libexec/scdaemon
      ''}
    '';

    # Helper scripts are now included in the main systemPackages list above

    # Systemd service for key synchronization
    systemd.services.openpgp-sync = {
      description = "Synchronize OpenPGP keys from repository";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.writeShellScript "sync-openpgp-keys" ''
          set -euo pipefail

          export GNUPGHOME="${pgpCfg.keyringPath}"

          # Import public keys from repository if available
          REPO_ROOT="$(systemctl show --property=WorkingDirectory git-deploy@main | cut -d= -f2)"
          if [ -d "$REPO_ROOT/secrets/pgp" ]; then
            for pubkey in "$REPO_ROOT"/secrets/pgp/*.asc; do
              [ -f "$pubkey" ] && ${pkgs.gnupg}/bin/gpg --import "$pubkey" 2>/dev/null || true
            done
            echo "OpenPGP keys synchronized from repository"
          fi
        ''}";
      };
    };

    # GPG environment for all users
    environment.sessionVariables = {
      GNUPGHOME = lib.mkDefault pgpCfg.keyringPath;
    };

    # Ensure GPG agent starts
    systemd.user.services.gpg-agent = {
      wantedBy = [ "default.target" ];
    };
  };
}