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

  # Host config

  networking.hostName = "max-richard-nix"; # Define your hostname.

  # Warning!
  system.stateVersion = "25.05"; # Did you read the comment?

}
