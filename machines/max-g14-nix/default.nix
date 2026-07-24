{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../roles/desktop-laptop.nix
  ];

  environment.systemPackages = [ pkgs.bottles ];

  networking.hostName = "max-g14-nix";
  system.stateVersion = "24.11";
}
