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

  users.extraGroups.plugdev = { };
  users.extraUsers.max.extraGroups = [ "plugdev" "dialout" ];

  users.users.max = {
    isNormalUser = true;
    description = "Max Schaefer";
    extraGroups = [ "networkmanager" "wheel" "adbusers" "wireshark" "docker" ];
  };


  ######################
  # 5. Nix Config
  ######################

  ######################
  # 6. Other
  ######################

  # Enable sound with pipewire.
  # Using host config because linux sound is always host-specific...
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  networking.firewall = rec {
    allowedTCPPortRanges = [ { from = 1714; to = 1764; } ];
    allowedUDPPortRanges = allowedTCPPortRanges;
  };

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
    berkeley-mono = pkgs.callPackage ../../packages/berkeley-mono { };
    active-firmware-tools = pkgs.callPackage ../../packages/active { };
  };

  environment.systemPackages = with pkgs; [
    berkeley-mono
    active-firmware-tools 
  ];

}
