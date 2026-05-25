{
  imports = [
    ./hardware-configuration.nix
    ../../roles/desktop-laptop.nix
  ];

  networking.hostName = "max-xps-modal";
  system.stateVersion = "24.11";
}
