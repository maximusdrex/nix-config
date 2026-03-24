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

  services.timesyncd.enable = true;

  virtualisation.oci-containers.backend = "podman"; # or "docker" if that’s what you use
  virtualisation.oci-containers.containers.matter-server = {
    image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
    autoStart = true;
  
    # 1) Host net so mDNS/commissioning uses the LAN
    extraOptions = [
      "--network=host"
      # 2) Explicit DNS for the container (avoid systemd-resolved stub)
      "--dns=1.1.1.1"
      "--dns=9.9.9.9"
    ];
  
    # 3) Force storage path and primary interface
    # (MATTER_STORAGE_PATH is honored by the python-matter-server image)
    environment = {
      MATTER_STORAGE_PATH = "/data";
    };
    # If you added this earlier, keep it; otherwise add now:
    cmd = [ "--primary-interface" "enp3s0" ];
  
    # 4) Persist data (fabric keys, cached PAA/DCL, etc.)
    volumes = [
      "/var/lib/matter-server:/data"
      # Also cover the alt path you saw in logs—belt & suspenders:
      "/var/lib/matter-server:/root/.matter_server"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/matter-server 0750 root root -"
  ];

  services.localHomeAssistant = {
    enable = true;
    openFirewall = false;
    trustedProxyWireGuardIP = "10.20.0.1";  # Hetzner VPS per wg-hosts.nix
    # listenAddress = "0.0.0.0";            # default is fine
    # port = 8123;                           # default is fine
  };

  # Host config

  networking.hostName = "max-richard-nix"; # Define your hostname.

  # Warning!
  system.stateVersion = "25.05"; # Did you read the comment?

}
