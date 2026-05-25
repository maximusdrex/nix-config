{
  imports = [
    ./hardware-configuration.nix
    ../../roles/desktop-laptop.nix
  ];

  networking.hostName = "max-g14-nix";
  system.stateVersion = "24.11";
}
