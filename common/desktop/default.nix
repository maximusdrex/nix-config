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

  # Enable network manager 
  networking.networkmanager.enable = true;

  networking.networkmanager.ensureProfiles.profiles = {
    "Wired connection 2" = {
      connection = {
        autoconnect-priority = "1";
        id = "Wavemux";
        interface-name = "wmx0";
        type = "ethernet";
        uuid = "d8644757-47df-3162-8177-5b4f8453e10b";
      };
      ethernet = {
        mtu = 256;
      };
      ipv4 = {
        address1 = "10.0.5.2/24";
        method = "manual";
      };
      ipv6 = {
        method = "disabled";
      };
      proxy = { };
    };
  };

  ######################
  # 4. General Linux Config
  ######################

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # QT config
  nixpkgs.config.qt6 = {
    enable = true;
  };
  nixpkgs.config.qt5.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  ######################
  # 5. Nix Config
  ######################

  ######################
  # 6. Other
  ######################

  # Install some programs.

  programs.firefox.enable = true;
  programs.adb.enable = true;

  hardware.saleae-logic.enable = true;

  # Setup some custom udev rules and packages

  services.udev.packages = [ pkgs.openocd ];
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="0002", NAME="wmx0"
  '';

  # Custom Packages

  nixpkgs.config.packageOverrides = pkgs: {
    berkeley-mono = pkgs.callPackage ../../packages/berkeley-mono.nix { };
  };

  environment.systemPackages = with pkgs; [
    berkeley-mono
  ];

}
