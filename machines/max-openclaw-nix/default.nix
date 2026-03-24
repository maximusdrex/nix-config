{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../roles/server.nix
  ];

  nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];

  networking.firewall = {
    enable = lib.mkForce true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ 33333 ];
  };

  networking.hostName = "max-openclaw-nix";
  system.stateVersion = "25.05";
}
