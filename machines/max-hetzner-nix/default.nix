{ config, pkgs, ... }:

########################
# Host-specific config
########################

{
  # Import auto-configured hardware settings
  imports =
    [ 
       ./hardware-configuration.nix
       ../../roles/server.nix
    ];

  ######################
  # 1. Bootloader
  ######################

  ######################
  # 2. Kernel
  ######################

  ######################
  # 3. Networking
  ######################

  ######################
  # 4. General Config
  ######################

  ######################
  # 6. Other
  ######################

  services.actual = {
    enable = true;
    settings = {
      port = 5006;
      hostname = "0.0.0.0";
    };
  };

  services.nginx.virtualHosts."max-hetzner-nix.maxschaefer.me".serverAliases = [
    "max-hetzner-nix.zt.maxschaefer.me"
    "monitoring.zt.maxschaefer.me"
  ];

  # Server-specific security settings - temporarily disabled

  # Host config

  networking.hostName = "max-hetzner-nix"; # Define your hostname.

  # Warning!
  system.stateVersion = "25.05"; # Did you read the comment?

}
