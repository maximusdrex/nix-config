{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../roles/desktop-laptop.nix
  ];

  networking.hostName = "max-fw-modal";
  boot.loader.timeout = lib.mkForce 5;
  system.stateVersion = "24.11";
}
