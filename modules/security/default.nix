{ config, lib, pkgs, ... }:

{
  imports = [
    ./fido2-pam.nix
    ./openpgp-keys.nix
    ./device-provision.nix
    ./key-rotation.nix
    ./encrypted-drive.nix
  ];

  # Security-wide configuration
  options.security.unifiedAuth = {
    enable = lib.mkEnableOption "unified FIDO2/OpenPGP authentication";

    enforceHardwareKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enforce hardware key authentication (disable for setup phase)";
    };

    keyDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of FIDO2 device paths or 'auto' for auto-detection";
      example = [ "auto" "/dev/hidraw0" ];
    };

    gpgKeyId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "OpenPGP master key ID for operations";
      example = "1234567890ABCDEF";
    };
  };

  config = lib.mkIf config.security.unifiedAuth.enable {
    # Base packages needed for unified auth
    environment.systemPackages = with pkgs; [
      libfido2
      gnupg
      pinentry-curses
      pinentry-gtk2
    ];

    # GPG configuration is handled by the OpenPGP module

    # Ensure required services are available
    services.pcscd.enable = true;  # Smart card daemon for OpenPGP
    services.udev.packages = [ pkgs.libfido2 ];  # FIDO2 device rules
  };
}