{ config, pkgs, ... }:

#######################
# Desktop Specific Configuration
# (Used by all laptops and desktops meant 
#   for interactive graphical use)
#######################

{
  imports = [
    ../common.nix
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
  # 4. General Linux Config
  ######################

  users.users.max = {
    isNormalUser = true;
    description = "Max Schaefer";
    extraGroups = [ "wheel" "docker" ];
  };


  ######################
  # 5. Nix Config
  ######################

  ######################
  # 6. Other
  ######################

  # networking.firewall = rec {
  #   allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
  #   allowedUDPPortRanges = allowedTCPPortRanges;
  # };
  networking.firewall.enable = false;

  # Install some programs.
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = false;
      AllowUsers = null;
      UseDns = true;
    };
  };

  users.users.max.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPrjeSJQjWhKrB2hsescG3Jktvs8WUvgkXui268elzIw max@max-xps-modal"
  ];
}
