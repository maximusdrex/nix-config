{ lib, pkgs, modulesPath, ... }:
let
  payloadPath = ../bootstrap/payload.age;
  identityPath = ../bootstrap/fido2-identity.txt;

  unlockScript = pkgs.writeShellScriptBin "bootstrap-unlock" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    PAYLOAD="/etc/bootstrap/payload.age"
    DEFAULT_IDENTITY="/etc/bootstrap/fido2-identity.txt"

    SUDO=""
    if [[ "$(id -u)" -ne 0 ]]; then
      SUDO="sudo"
    fi

    if [[ ! -f "$PAYLOAD" ]]; then
      echo "ERROR: $PAYLOAD not found on installer media"
      echo "If this USB was built before payload embedding fix, rebuild with: just write flash /dev/sdX"
      exit 1
    fi

    IDENTITY_FILE="''${IDENTITY_FILE:-$DEFAULT_IDENTITY}"
    if [[ ! -f "$IDENTITY_FILE" ]]; then
      echo "ERROR: FIDO2 identity file not found at $IDENTITY_FILE"
      echo "Expected this to be embedded by 'just write flash'."
      exit 1
    fi

    TMPDIR="$(mktemp -d /tmp/bootstrap-unlock.XXXXXX)"
    trap 'rm -rf "$TMPDIR"' EXIT

    echo "Decrypting payload with FIDO2 key (touch/PIN may be required)..."
    ${pkgs.age}/bin/age -d -i "$IDENTITY_FILE" "$PAYLOAD" | ${pkgs.gnutar}/bin/tar -xzf - -C "$TMPDIR"

    $SUDO mkdir -p /opt
    $SUDO rm -rf /opt/nix-config
    $SUDO cp -a "$TMPDIR/opt/nix-config" /opt/

    echo "NOTE: bootstrap no longer installs a shared operator SOPS key."
    echo "After disko, provision a host runtime age key with:"
    echo "  bootstrap-provision-host-age-key <target>"

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
    echo "  bootstrap-disko <target> <disk>"
    echo "  bootstrap-capture-hardware <target>"
    echo "  bootstrap-install <target>"
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

    echo "About to WIPE and partition $DISK for target $TARGET"
    read -r -p "Type YES to continue: " confirm
    [[ "$confirm" == "YES" ]] || { echo "Aborted"; exit 1; }

    set +e
    nix --experimental-features 'nix-command flakes' run github:nix-community/disko -- \
      --mode disko \
      /opt/nix-config#"$TARGET" \
      --argstr mainDisk "$DISK"
    rc=$?
    set -e

    if [[ $rc -ne 0 ]]; then
      echo "Target-specific disko failed or is not defined; falling back to default desktop layout."
      nix --experimental-features 'nix-command flakes' run github:nix-community/disko -- \
        --mode disko \
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

    key_dst="/mnt/var/lib/sops-nix/key.txt"
    machine_key_json="/opt/nix-config/sops/machines/$TARGET/key.json"

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

    if [[ -f "$machine_key_json" ]]; then
      sudo cp "$machine_key_json" "$machine_key_json.bak.$(date +%Y%m%d%H%M%S)"
    fi

    cat > "$tmp" <<EOF
{
  "age": {
    "publickey": "$pub",
    "type": "age"
  }
}
EOF
    sudo install -Dm644 "$tmp" "$machine_key_json"
    sudo chown nixos:users "$machine_key_json" || true

    echo "Provisioned runtime age key at: $key_dst"
    echo "Updated machine recipient file: $machine_key_json"
    echo "New machine recipient: $pub"
    echo "Next: commit and push recipient updates from /opt/nix-config"
  '';

  installScript = pkgs.writeShellScriptBin "bootstrap-install" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    TARGET="''${1:-}"
    if [[ -z "$TARGET" ]]; then
      echo "Usage: bootstrap-install <target-machine>"
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
in {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  networking.hostName = "bootstrap-installer";
  services.openssh.enable = true;
  networking.networkmanager.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    git
    just
    age
    sops
    age-plugin-fido2-hmac
    fido2-manage
    disko
    networkmanager
    iwd
    iw
    wirelesstools
    wpa_supplicant
    unlockScript
    diskoScript
    captureHardwareScript
    provisionHostAgeKeyScript
    installScript
  ];

  environment.etc = lib.mkMerge [
    (lib.optionalAttrs (builtins.pathExists payloadPath) {
      "bootstrap/payload.age".source = payloadPath;
    })
    (lib.optionalAttrs (builtins.pathExists identityPath) {
      "bootstrap/fido2-identity.txt".source = identityPath;
    })
    {
      "bootstrap-quickstart.txt".text = ''
        Bootstrap USB quickstart:
          1) Connect network:
             - nmtui   (easy TUI)
             - nmcli dev wifi list
             - nmcli dev wifi connect <SSID> password <PASS>
          2) bootstrap-unlock
          3) bootstrap-disko <target> <disk>
          4) bootstrap-capture-hardware <target>
          5) bootstrap-provision-host-age-key <target>
          6) bootstrap-install <target>

        Notes:
          - Flakes are enabled in this live environment.
          - Decrypted repo path: /opt/nix-config
          - Provision host runtime key with: bootstrap-provision-host-age-key <target>
          - bootstrap-disko uses target disko config when available, else a default EFI+ext4 desktop layout
      '';
    }
  ];

  image.fileName = "max-bootstrap-installer.iso";
  system.stateVersion = "24.11";
}
