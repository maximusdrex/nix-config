{ lib, pkgs, modulesPath, ... }:
let
  payloadPath = ../bootstrap/payload.age;
  identityPath = ../bootstrap/yubikey-identity.txt;
  unlockScript = pkgs.writeShellScriptBin "bootstrap-unlock" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    PAYLOAD="/etc/bootstrap/payload.age"
    OUT_DIR="/opt/nix-config"
    DEFAULT_IDENTITY="/etc/bootstrap/yubikey-identity.txt"

    if [[ ! -f "$PAYLOAD" ]]; then
      echo "ERROR: $PAYLOAD not found on installer media"
      exit 1
    fi

    IDENTITY_FILE="''${IDENTITY_FILE:-$DEFAULT_IDENTITY}"
    if [[ ! -f "$IDENTITY_FILE" ]]; then
      echo "No identity file found at $IDENTITY_FILE"
      echo "If using yubikey plugin identities, place one there or pass IDENTITY_FILE=/path/to/identity.txt"
      echo "You can also decrypt manually with age and extract to $OUT_DIR"
      exit 1
    fi

    mkdir -p "$OUT_DIR"
    ${pkgs.age}/bin/age -d -i "$IDENTITY_FILE" "$PAYLOAD" | ${pkgs.gnutar}/bin/tar -xzf - -C "$OUT_DIR"

    echo "Decrypted bootstrap payload into $OUT_DIR"
    echo "Next:"
    echo "  cd $OUT_DIR"
    echo "  export SOPS_AGE_KEY_FILE=\$HOME/.config/sops/age/keys.txt"
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
