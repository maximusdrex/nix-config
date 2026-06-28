{ inputs, lib, pkgs, ... }:
let
  localPackagesOverlay = import ../overlays/default.nix;
  berkeleyMonoArchive = ../packages/berkeley-mono/berkeley-mono-1.009.zip;
  berkeleyMonoPkg =
    if builtins.pathExists berkeleyMonoArchive then
      pkgs.callPackage ../packages/berkeley-mono/default.nix { src = berkeleyMonoArchive; }
    else
      null;
in
{
  imports = [
    ./base.nix
    inputs.lab-bar.nixosModules.default
    inputs.codex-nix.nixosModules.default
  ];

  programs.lab-bar.enable = true;
  services.codex-nix.enable = true;

  environment.profileRelativeSessionVariables.QML_IMPORT_PATH = [ "/lib/qt-6/qml" ];

  nixpkgs.overlays = lib.mkAfter [ localPackagesOverlay ];

  nixpkgs.config.permittedInsecurePackages = [
    "segger-jlink-qt4-874"
  ];
  nixpkgs.config.segger-jlink.acceptLicense = true;

  networking.networkmanager.enable = true;

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  nixpkgs.config.qt6.enable = true;
  nixpkgs.config.qt5.enable = true;

  services.printing.enable = true;

  users.extraGroups.plugdev = { };
  users.users.max = {
    isNormalUser = true;
    description = "Max Schaefer";
    extraGroups = [ "networkmanager" "wheel" "adbusers" "wireshark" "docker" "plugdev" "dialout" ];
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  networking.firewall.enable = false;

  systemd.tmpfiles.rules = [
    "d /home/max/.codex 0700 max users -"
    "d /home/max/.config 0700 max users -"
    "d /home/max/.gnupg 0700 max users -"
    "d /home/max/.local 0700 max users -"
    "d /home/max/.local/share 0700 max users -"
    "d /home/max/.local/state 0700 max users -"
    "d /home/max/.ssh 0700 max users -"
    "d /home/max/Desktop 0755 max users -"
    "d /home/max/Documents 0755 max users -"
    "d /home/max/Downloads 0755 max users -"
    "d /home/max/MODELS 0755 max users -"
    "d /home/max/Music 0755 max users -"
    "d /home/max/Pictures 0755 max users -"
    "d /home/max/Public 0755 max users -"
    "d /home/max/RADIO 0755 max users -"
    "d /home/max/Templates 0755 max users -"
    "d /home/max/Videos 0755 max users -"
    "d /home/max/bin 0755 max users -"
    "d /home/max/nix-config 0755 max users -"
  ];

  clan.core.state.desktop-home.folders = [
    "/home/max/.codex"
    "/home/max/.config"
    "/home/max/.gnupg"
    "/home/max/.local/share"
    "/home/max/.local/state"
    "/home/max/.ssh"
    "/home/max/Desktop"
    "/home/max/Documents"
    "/home/max/MODELS"
    "/home/max/Music"
    "/home/max/Pictures"
    "/home/max/RADIO"
    "/home/max/Videos"
    "/home/max/bin"
    "/home/max/nix-config"
  ];

  programs.firefox.enable = true;
  hardware.saleae-logic.enable = true;
  programs.nix-ld.enable = true;
  programs.wireshark.enable = true;

  services.udev.packages = [ pkgs.openocd pkgs.rtl-sdr ];
  services.udev.extraRules = ''
    ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="55de", MODE="660", GROUP="plugdev", TAG+="uaccess"
  '';

  hardware.rtl-sdr.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  services.thermald.enable = true;

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  fonts.packages = lib.optionals (berkeleyMonoPkg != null) [
    berkeleyMonoPkg
  ];

  environment.systemPackages = [
    # pkgs.active-firmware-tools
  ];

  programs.kde-pim.enable = true;
  programs.kde-pim.kontact = true;
  programs.kde-pim.kmail = true;
}
