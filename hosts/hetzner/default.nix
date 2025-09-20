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
       ../../modules/edge-proxy
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

  services.edgeProxy = {
    enable = true;
    acmeEmail = "max@theschaefers.com";        # change to your email
    sites."home.maxschaefer.me" = {
      upstreamHost = "max-richard-nix";   # resolves to max-richard-nix.wg via the module
      upstreamPort = 8123;                # Home Assistant
    };
    # Add more sites later by extending 'sites'
  };

  # Host config

  networking.hostName = "max-hetzner-nix"; # Define your hostname.

  # Warning!
  system.stateVersion = "25.05"; # Did you read the comment?

}
