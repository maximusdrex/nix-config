{ lib, pkgs, ... }:
let
  localPackagesOverlay = import ../overlays/default.nix;
in
{
  imports = [
    ./base.nix
  ];

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

  fonts.packages = lib.optionals berkeleyMonoTry.success [
    berkeleyMonoTry.value
  ];

  environment.systemPackages = [
    pkgs.active-firmware-tools
  ];

  programs.kde-pim.enable = true;
  programs.kde-pim.kontact = true;
  programs.kde-pim.kmail = true;
}
kmail = true;
}
