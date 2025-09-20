{ config, pkgs, ... }:

########################
# Host-specific config
########################

{
  # Import auto-configured hardware settings
  imports =
    [ 
       ./hardware-configuration.nix
       ../../common/server
       ../../modules/wireguard
       ../../modules/home-assistant
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

  services.localHomeAssistant = {
    enable = true;
    openFirewall = true;
    trustedProxyWireGuardIP = "10.20.0.1";  # Hetzner VPS per wg-hosts.nix
    # listenAddress = "0.0.0.0";            # default is fine
    # port = 8123;                           # default is fine
  };

  # Host config

  networking.hostName = "max-richard-nix"; # Define your hostname.

  # Warning!
  system.stateVersion = "25.05"; # Did you read the comment?

}
