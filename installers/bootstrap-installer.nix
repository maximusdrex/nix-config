{ lib, pkgs, modulesPath, inputs, ... }:
let
  payloadPath = ../bootstrap/payload.age;
  operatorFidoStubPath = ../sops/users/max/fido-identities.txt;

  unlockScript = pkgs.writeShellScriptBin "bootstrap-unlock" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    PAYLOAD="/etc/bootstrap/payload.age"
    DEFAULT_FIDO_IDENTITY="/etc/bootstrap/fido-identities.txt"
    export PATH="${lib.makeBinPath [ pkgs.age-plugin-fido2-hmac pkgs.age pkgs.gnutar pkgs.coreutils ]}:$PATH"

    SUDO=""
    if [[ "$(id -u)" -ne 0 ]]; then
      SUDO="sudo"
    fi

    if [[ ! -f "$PAYLOAD" ]]; then
      echo "ERROR: $PAYLOAD not found on installer media"
      echo "If this USB was built before payload embedding fix, rebuild with: just write flash /dev/sdX"
      exit 1
    fi

    TMPDIR="$(mktemp -d /tmp/bootstrap-unlock.XXXXXX)"
    trap 'rm -rf "$TMPDIR"' EXIT

    identity_file="''${AGE_IDENTITY_FILE:-''${AGE_KEYFILE:-}}"
    if [[ -z "$identity_file" && -f "$DEFAULT_FIDO_IDENTITY" ]]; then
      identity_file="$DEFAULT_FIDO_IDENTITY"
    fi

    if [[ -n "$identity_file" ]]; then
      if [[ ! -f "$identity_file" ]]; then
        echo "ERROR: explicit age identity file is set but not readable: $identity_file"
        exit 1
      fi
      echo "Decrypting payload with age identity file: $identity_file"
      ${pkgs.age}/bin/age -d -i "$identity_file" "$PAYLOAD" | ${pkgs.gnutar}/bin/tar -xzf - -C "$TMPDIR"
    else
      echo "ERROR: no age identity available for bootstrap payload unlock"
      echo "Expected one of:"
      echo "  - /etc/bootstrap/fido-identities.txt on the installer media"
      echo "  - AGE_IDENTITY_FILE=/path/to/recovery.agekey"
      echo "  - AGE_KEYFILE=/path/to/recovery.agekey"
      exit 1
    fi

    $SUDO mkdir -p /opt
    $SUDO rm -rf /opt/nix-config
    $SUDO cp -a "$TMPDIR/opt/nix-config" /opt/

    echo "NOTE: bootstrap no longer installs a shared operator secret key."
    echo "The normal flow now expects the target to be prepared in the main repo with:"
    echo "  clan vars generate <target>"

    if [[ -f "$TMPDIR/bootstrap-secrets/berkeley-mono-1.009.zip" ]]; then
      $SUDO install -Dm644 "$TMPDIR/bootstrap-secrets/berkeley-mono-1.009.zip" /opt/nix-config/bootstrap/berkeley-mono-1.009.zip
      $SUDO install -Dm644 "$TMPDIR/bootstrap-secrets/berkeley-mono-1.009.zip" /opt/nix-config/packages/berkeley-mono/berkeley-mono-1.009.zip
      echo "Installed Berkeley Mono archive at:"
      echo "  /opt/nix-config/bootstrap/berkeley-mono-1.009.zip"
      echo "  /opt/nix-config/packages/berkeley-mono/berkeley-mono-1.009.zip"
      echo "If needed, pre-register in store with:"
      echo "  nix-store --add-fixed sha256 /opt/nix-config/packages/berkeley-mono/berkeley-mono-1.009.zip"
    fi

    echo "Bootstrap payload installed. Next:"
    echo "  bootstrap-install <target> <disk>"
    echo
    echo "Manual fallback helpers are also available:"
    echo "  bootstrap-verify-target <target>"
    echo "  bootstrap-disko <target> <disk>"
    echo "  bootstrap-capture-hardware <target>"
    echo "  bootstrap-populate-secrets <target>"
    echo "  bootstrap-install-system <target>"
  '';

  verifyTargetScript = pkgs.writeShellScriptBin "bootstrap-verify-target" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    TARGET="''${1:-}"
    if [[ -z "$TARGET" ]]; then
      echo "Usage: bootstrap-verify-target <target-machine>"
      exit 1
    fi

    if [[ ! -d /opt/nix-config ]]; then
      echo "ERROR: /opt/nix-config not found. Run bootstrap-unlock first."
      exit 1
    fi

    export CLAN_DIR=/opt/nix-config
    if [[ -z "''${AGE_KEYFILE:-}" && -f /opt/nix-config/sops/users/max/fido-identities.txt ]]; then
      export AGE_KEYFILE=/opt/nix-config/sops/users/max/fido-identities.txt
    fi

    echo "Checking that target '$TARGET' exists in the repo..."
    ${pkgs.nix}/bin/nix eval --raw "/opt/nix-config#nixosConfigurations.$TARGET.config.networking.hostName" >/dev/null

    machine_key_dir="/opt/nix-config/secrets/age-keys/machines/$TARGET"
    if [[ ! -s "$machine_key_dir/key.age" || ! -s "$machine_key_dir/pub" ]]; then
      echo "ERROR: missing managed machine key for $TARGET in $machine_key_dir"
      echo "Run 'clan vars generate $TARGET' on the operator machine and rebuild the installer USB."
      exit 1
    fi

    echo "Checking Clan vars for $TARGET..."
    ${inputs.clan-core.packages.${pkgs.system}.clan-cli}/bin/clan vars check "$TARGET"

    echo "Checking operator access to target secrets..."
    ${inputs.clan-core.packages.${pkgs.system}.clan-cli}/bin/clan vars get "$TARGET" user-password-max/user-password-hash >/dev/null

    echo "Target preflight passed for $TARGET."
  '';

  diskoScript = pkgs.writeShellScriptBin "bootstrap-disko" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    TARGET="''${1:-}"
    DISK="''${2:-}"

    if [[ -z "$TARGET" || -z "$DISK" ]]; then
      echo "Usage: bootstrap-disko <target-machine> <disk-device>"
      echo "Example: bootstrap-disko max-g14-nix /dev/nvme0n1"
      exit 1
    fi

    if [[ ! -d /opt/nix-config ]]; then
      echo "ERROR: /opt/nix-config not found. Run bootstrap-unlock first."
      exit 1
    fi

    if [[ ! -b "$DISK" ]]; then
      echo "ERROR: $DISK is not a block device"
      exit 1
    fi

    if [[ "''${BOOTSTRAP_YES:-0}" != "1" ]]; then
      echo "About to WIPE and partition $DISK for target $TARGET"
      read -r -p "Type YES to continue: " confirm
      [[ "$confirm" == "YES" ]] || { echo "Aborted"; exit 1; }
    fi

    set +e
    ${pkgs.disko}/bin/disko --mode disko \
      /opt/nix-config#"$TARGET" \
      --argstr mainDisk "$DISK"
    rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
      echo "Target-specific disko failed or is not defined; falling back to default desktop layout."
      ${pkgs.disko}/bin/disko --mode disko \
        /opt/nix-config/installers/disko-desktop-default.nix \
        --argstr disk "$DISK"
    fi

    echo "Disko finished. /mnt should now be mounted."
  '';

  captureHardwareScript = pkgs.writeShellScriptBin "bootstrap-capture-hardware" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    TARGET="''${1:-}"
    if [[ -z "$TARGET" ]]; then
      echo "Usage: bootstrap-capture-hardware <target-machine>"
      exit 1
    fi

    if [[ ! -d /opt/nix-config ]]; then
      echo "ERROR: /opt/nix-config not found. Run bootstrap-unlock first."
      exit 1
    fi

    if [[ ! -d /mnt ]]; then
      echo "ERROR: /mnt not present. Run bootstrap-disko first."
      exit 1
    fi

    sudo nixos-generate-config --root /mnt

    SRC="/mnt/etc/nixos/hardware-configuration.nix"
    DST="/opt/nix-config/machines/$TARGET/hardware-configuration.nix"

    if [[ ! -f "$SRC" ]]; then
      echo "ERROR: $SRC not found after nixos-generate-config"
      exit 1
    fi

    if [[ -f "$DST" ]]; then
      sudo cp "$DST" "$DST.bak.$(date +%Y%m%d%H%M%S)"
    fi

    sudo install -Dm644 "$SRC" "$DST"
    sudo chown nixos:users "$DST" || true

    echo "Updated hardware config: $DST"
  '';

  provisionHostAgeKeyScript = pkgs.writeShellScriptBin "bootstrap-provision-host-age-key" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    TARGET="''${1:-}"
    if [[ -z "$TARGET" ]]; then
      echo "Usage: bootstrap-provision-host-age-key <target-machine>"
      exit 1
    fi

    if [[ ! -d /opt/nix-config ]]; then
      echo "ERROR: /opt/nix-config not found. Run bootstrap-unlock first."
      exit 1
    fi

    if [[ ! -d /mnt ]]; then
      echo "ERROR: /mnt not present. Run bootstrap-disko first."
      exit 1
    fi

    key_dst="/mnt/etc/secret-vars/key.txt"
    machine_key_dir="/opt/nix-config/secrets/age-keys/machines/$TARGET"

    if [[ -f "$key_dst" ]]; then
      echo "WARNING: existing host key found at $key_dst"
      read -r -p "Overwrite with newly generated key? Type YES to continue: " confirm
      [[ "$confirm" == "YES" ]] || { echo "Aborted"; exit 1; }
    fi

    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT

    ${pkgs.age}/bin/age-keygen -o "$tmp" >/dev/null
    pub="$(grep '^# public key:' "$tmp" | sed -E 's/^# public key: (.*)$/\1/')"

    if [[ -z "$pub" ]]; then
      echo "ERROR: failed to parse generated public key"
      exit 1
    fi

    sudo install -Dm600 "$tmp" "$key_dst"

    sudo install -d "$machine_key_dir"
    printf '%s\n' "$pub" | sudo tee "$machine_key_dir/pub" >/dev/null

    mapfile -t recipients < <(${pkgs.nix}/bin/nix eval --raw --file /opt/nix-config/scripts/print-operator-age-recipients.nix)
    if [[ "''${#recipients[@]}" -eq 0 ]]; then
      echo "ERROR: no operator recipients found in /opt/nix-config/sops/users"
      exit 1
    fi

    age_args=()
    for recipient in "''${recipients[@]}"; do
      [[ -n "$recipient" ]] || continue
      age_args+=("-r" "$recipient")
    done

    sudo ${pkgs.age}/bin/age --armor "''${age_args[@]}" -o "$machine_key_dir/key.age" "$key_dst"
    printf '%s\n' "''${recipients[@]}" | sed '/^$/d' | sort -u | sudo tee "$machine_key_dir/key.age.recipients" >/dev/null
    sudo chown nixos:users "$machine_key_dir/pub" "$machine_key_dir/key.age" "$machine_key_dir/key.age.recipients" || true

    echo "Provisioned runtime age key at: $key_dst"
    echo "Updated age backend machine key dir: $machine_key_dir"
    echo "New machine recipient: $pub"
    echo "Next: commit and push machine key updates from /opt/nix-config"
  '';

  populateSecretsScript = pkgs.writeShellScriptBin "bootstrap-populate-secrets" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    TARGET="''${1:-}"
    if [[ -z "$TARGET" ]]; then
      echo "Usage: bootstrap-populate-secrets <target-machine>"
      exit 1
    fi

    if [[ ! -d /opt/nix-config ]]; then
      echo "ERROR: /opt/nix-config not found. Run bootstrap-unlock first."
      exit 1
    fi

    if [[ ! -d /mnt/etc ]]; then
      echo "ERROR: /mnt does not look like an installed target root."
      echo "Run bootstrap-disko first, then retry."
      exit 1
    fi

    machine_key_dir="/opt/nix-config/secrets/age-keys/machines/$TARGET"

    if [[ ! -s "$machine_key_dir/key.age" ]]; then
      echo "ERROR: missing managed machine key for $TARGET in $machine_key_dir"
      echo "Run 'clan vars generate $TARGET' on the operator machine and rebuild the installer payload."
      exit 1
    fi

    if [[ -z "''${AGE_KEYFILE:-}" && -f /opt/nix-config/sops/users/max/fido-identities.txt ]]; then
      export AGE_KEYFILE=/opt/nix-config/sops/users/max/fido-identities.txt
    fi

    export CLAN_DIR=/opt/nix-config

    sudo rm -rf /mnt/etc/secret-vars
    sudo install -d -m 700 /mnt/etc/secret-vars

    echo "Populating /mnt/etc/secret-vars for $TARGET through Clan age backend..."
    sudo --preserve-env=AGE_KEYFILE,CLAN_DIR \
      ${inputs.clan-core.packages.${pkgs.system}.clan-cli}/bin/clan vars upload \
      "$TARGET" --directory /mnt/etc/secret-vars

    if [[ ! -s /mnt/etc/secret-vars/key.txt ]]; then
      echo "ERROR: clan vars upload did not produce /mnt/etc/secret-vars/key.txt"
      exit 1
    fi
  '';

  installSystemScript = pkgs.writeShellScriptBin "bootstrap-install-system" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    TARGET="''${1:-}"
    if [[ -z "$TARGET" ]]; then
      echo "Usage: bootstrap-install-system <target-machine>"
      exit 1
    fi

    if [[ ! -d /opt/nix-config ]]; then
      echo "ERROR: /opt/nix-config not found. Run bootstrap-unlock first."
      exit 1
    fi

    if [[ ! -d /mnt/etc ]]; then
      echo "ERROR: /mnt does not look like an installed target root."
      echo "Run bootstrap-disko or partition/mount manually, then retry."
      exit 1
    fi

    key_dst="/mnt/etc/secret-vars/key.txt"

    if [[ ! -s "$key_dst" ]]; then
      echo "ERROR: missing runtime host AGE key at $key_dst"
      echo "Run bootstrap-populate-secrets $TARGET before bootstrap-install-system."
      exit 1
    fi

    if [[ -f /opt/nix-config/packages/berkeley-mono/berkeley-mono-1.009.zip ]]; then
      echo "Registering Berkeley Mono archive in Nix store..."
      bm_file="/opt/nix-config/packages/berkeley-mono/berkeley-mono-1.009.zip"
      expected_hash="1wz76zjayd0acyialrcd8dbbb3sa2qdm9ib92nzsw9hi9pjys5hg"
      actual_hash="$(nix hash file --type sha256 --base32 "$bm_file")"
      echo "Berkeley Mono hash expected: $expected_hash"
      echo "Berkeley Mono hash actual  : $actual_hash"
      if [[ "$actual_hash" == "$expected_hash" ]]; then
        nix-store --add-fixed sha256 "$bm_file" >/dev/null
      else
        echo "WARNING: Berkeley Mono archive hash mismatch; continuing without Berkeley Mono font package"
      fi
    fi

    echo "Installing target '$TARGET' from /opt/nix-config ..."
    nixos-install --flake /opt/nix-config#"$TARGET" --root /mnt
  '';

  installScript = pkgs.writeShellScriptBin "bootstrap-install" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    TARGET="''${1:-}"
    DISK="''${2:-}"

    if [[ -z "$TARGET" || -z "$DISK" ]]; then
      echo "Usage: bootstrap-install <target-machine> <disk-device>"
      echo "Example: bootstrap-install max-g14-nix /dev/nvme0n1"
      exit 1
    fi

    if [[ ! -b "$DISK" ]]; then
      echo "ERROR: $DISK is not a block device"
      exit 1
    fi

    if [[ ! -d /opt/nix-config ]]; then
      bootstrap-unlock
    fi

    bootstrap-verify-target "$TARGET"

    if [[ "''${BOOTSTRAP_YES:-0}" != "1" ]]; then
      echo "About to install '$TARGET' onto '$DISK'."
      echo "This will wipe the disk, capture hardware, populate /etc/secret-vars, and run nixos-install."
      read -r -p "Type YES to continue: " confirm
      [[ "$confirm" == "YES" ]] || { echo "Aborted"; exit 1; }
    fi

    if command -v nm-online >/dev/null; then
      if ! nm-online -q --timeout=5; then
        echo "No active network connection detected."
        echo "Launching nmtui so you can connect before install..."
        if command -v nmtui >/dev/null; then
          nmtui || true
        fi
        nm-online -q --timeout=10 || {
          echo "ERROR: network is still unavailable."
          echo "Connect networking manually, then rerun bootstrap-install."
          exit 1
        }
      fi
    fi

    BOOTSTRAP_YES=1 bootstrap-disko "$TARGET" "$DISK"
    bootstrap-capture-hardware "$TARGET"
    bootstrap-populate-secrets "$TARGET"
    bootstrap-install-system "$TARGET"

    updates_dir="/mnt/var/lib/bootstrap/nix-config-updates"
    sudo install -d "$updates_dir/machines/$TARGET"
    if [[ -f "/opt/nix-config/machines/$TARGET/hardware-configuration.nix" ]]; then
      sudo install -Dm644 \
        "/opt/nix-config/machines/$TARGET/hardware-configuration.nix" \
        "$updates_dir/machines/$TARGET/hardware-configuration.nix"
    fi
    sudo tee "$updates_dir/README.txt" >/dev/null <<EOF
Generated during bootstrap install for $TARGET.

Copy these files back into your main nix-config repo after first boot:
- machines/$TARGET/hardware-configuration.nix

The machine runtime key itself comes from the repo-managed Clan age backend.
If you prepared the target with 'clan vars generate $TARGET' before building
the installer image, the installed machine now has the correct /etc/secret-vars/key.txt.
EOF

    echo
    echo "Bootstrap install completed for $TARGET."
    echo "A copy of generated repo updates was saved at:"
    echo "  /var/lib/bootstrap/nix-config-updates"
  '';
in {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  networking.hostName = "bootstrap-installer";
  services.openssh.enable = true;
  networking.networkmanager.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    inputs.clan-core.packages.${pkgs.system}.clan-cli
    git
    just
    age
    age-plugin-fido2-hmac
    fido2-manage
    disko
    networkmanager
    iwd
    iw
    wirelesstools
    wpa_supplicant
    unlockScript
    verifyTargetScript
    diskoScript
    captureHardwareScript
    provisionHostAgeKeyScript
    populateSecretsScript
    installSystemScript
    installScript
  ];

  environment.etc = lib.mkMerge [
    (lib.optionalAttrs (builtins.pathExists payloadPath) {
      "bootstrap/payload.age".source = payloadPath;
    })
    (lib.optionalAttrs (builtins.pathExists operatorFidoStubPath) {
      "bootstrap/fido-identities.txt".source = operatorFidoStubPath;
    })
    {
      "bootstrap-quickstart.txt".text = ''
        Bootstrap USB quickstart:
          1) Prepare the target in your main repo before building the USB:
             - add the machine config/inventory entry
             - run: clan vars generate <target>
             - rebuild/write the installer USB
          2) Connect network if needed:
             - nmtui
          3) Run:
             - bootstrap-install <target> <disk>

        Notes:
          - Flakes are enabled in this live environment.
          - Decrypted repo path: /opt/nix-config
          - bootstrap-unlock uses the repo-tracked FIDO identity stub embedded on the installer media
          - Set AGE_IDENTITY_FILE or AGE_KEYFILE only for a recovery/software key override
          - bootstrap-install uses target disko config when available, else a default EFI+ext4 desktop layout
          - bootstrap-provision-host-age-key is now only an advanced/manual rekey path
      '';
    }
  ];

  image.fileName = "max-bootstrap-installer.iso";
  system.stateVersion = "24.11";
}
