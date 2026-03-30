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

    if [[ -f "$TMPDIR/bootstrap-secrets/sops-age-key.txt" ]]; then
      $SUDO install -Dm600 "$TMPDIR/bootstrap-secrets/sops-age-key.txt" /var/lib/sops-nix/key.txt
      $SUDO install -Dm600 "$TMPDIR/bootstrap-secrets/sops-age-key.txt" /home/nixos/.config/sops/age/keys.txt
      $SUDO chown -R nixos:users /home/nixos/.config/sops || true

      if [[ -d /mnt ]]; then
        $SUDO install -Dm600 "$TMPDIR/bootstrap-secrets/sops-age-key.txt" /mnt/var/lib/sops-nix/key.txt || true
      fi

      echo "Installed sops age key to /var/lib/sops-nix/key.txt"
      echo "Installed sops age key to /home/nixos/.config/sops/age/keys.txt"
      echo "(and /mnt/var/lib/sops-nix/key.txt if /mnt is present)"
    else
      echo "WARNING: payload did not include bootstrap-secrets/sops-age-key.txt"
    fi

    echo "Bootstrap payload installed. Next:"
    echo "  cd /opt/nix-config"
    echo "  nix develop .#bootstrap"
    echo "  just switch <target>"
  '';
in {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix")
  ];

  networking.hostName = "bootstrap-installer";
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    git
    just
    age
    sops
    ykman
    age-plugin-yubikey
    disko
    unlockScript
  ];

  environment.etc = lib.mkMerge [
    (lib.optionalAttrs (builtins.pathExists payloadPath) {
      "bootstrap/payload.age".source = payloadPath;
    })
    (lib.optionalAttrs (builtins.pathExists identityPath) {
      "bootstrap/yubikey-identity.txt".source = identityPath;
    })
  ];

  users.users.nixos.initialPassword = "nixos";
  isoImage.isoName = "max-bootstrap-installer.iso";
  system.stateVersion = "24.11";
}
