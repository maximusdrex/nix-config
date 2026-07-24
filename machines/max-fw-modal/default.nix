{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../roles/desktop-laptop.nix
  ];

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Spotify and Steam currently generate frequent bus-lock traps on this CPU.
  # Handling every trap adds kernel overhead and floods the persistent journal.
  boot.kernelParams = [ "split_lock_detect=off" ];

  # Clan's local resolver defaults to query-level logging. Keep operational
  # messages while avoiding hundreds of thousands of journal entries per boot.
  services.unbound.settings.server.verbosity = lib.mkForce 1;

  # Avahi already provides mDNS. Letting resolved publish the same hostname
  # makes the two daemons continuously report conflicts with each other.
  services.resolved.settings.Resolve.MulticastDNS = false;

  services.journald.extraConfig = ''
    SystemMaxUse=1G
  '';

  networking.hostName = "max-fw-modal";
  boot.loader.timeout = lib.mkForce 5;
  system.stateVersion = "24.11";
}
