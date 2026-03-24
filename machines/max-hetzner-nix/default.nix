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

  # services.edgeProxy = {
  #   enable = true;
  #   acmeEmail = "max@theschaefers.com";        # change to your email
  #   sites."home.maxschaefer.me" = {
  #     upstreamHost = "max-richard-nix";   
  #     upstreamPort = 8123;                # Home Assistant
  #   };
  #   sites."budget.maxschaefer.me" = {
  #     upstreamHost = "max-hetzner-nix";
  #     upstreamPort = 5006;
  #   };
  #   sites."openclaw.maxschaefer.me" = {
  #     upstreamHost = "max-openclaw-nix";
  #     upstreamPort = 18789;
  #   };
  #   # Add more sites later by extending 'sites'
  # };

  services.actual = {
    enable = true;
    settings = {
      port = 5006;
      hostname = "0.0.0.0";
    };
  };

  users.users.nginx.extraGroups = [ "acme" ];

  # Server-specific security settings - temporarily disabled

  # Host config

  networking.hostName = "max-hetzner-nix"; # Define your hostname.

  # Warning!
  system.stateVersion = "25.05"; # Did you read the comment?

}
