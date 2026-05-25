{
  imports = [
    ./hardware-configuration.nix
    ../../roles/desktop-laptop.nix
  ];

  networking.hostName = "max-fw-modal";
  system.stateVersion = "24.11";
}
