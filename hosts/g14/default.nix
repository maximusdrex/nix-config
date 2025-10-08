{ config, pkgs, ... }:

########################
# Host-specific config
########################

{
  # Import auto-configured hardware settings
  imports =
    [ 
       ./hardware-configuration.nix
       ../../common/desktop
       ../../modules/wavemux
       ../../modules/wireguard
    ];

  ######################
  # 1. Bootloader
  ######################

  boot.plymouth = {
    enable = true;
    theme = "rings";
    themePackages = with pkgs; [
      # By default we would install all themes
      (adi1090x-plymouth-themes.override {
        selected_themes = [ "rings" ];
      })
    ];
  };

  boot.blacklistedKernelModules = [ "dvb_usb_rtl28xxu" ];

  ######################
  # 2. Kernel
  ######################

  ######################
  # 3. Networking
  ######################

  networking.firewall = {
    allowedUDPPorts = [ 33333 1234 ];
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  ######################
  # 4. General Config
  ######################

  programs.kde-pim.merkuro = true;

  ######################
  # 6. Other
  ######################

  # RTL-SDR

  services.udev.packages = [ pkgs.rtl-sdr ];
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="0002", NAME="wmx0"
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="607[df]", GROUP="plugdev", MODE="0666"
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="2b04", ATTRS{idProduct}=="[cd]00?", GROUP="plugdev", MODE="0666"
  '';
  hardware.rtl-sdr.enable = true;


  # Bluetooth

  systemd.user.services.mpris-proxy = {
    description = "Mpris proxy";
    after = [ "network.target" "sound.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
  };

  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot
  services.blueman.enable = true;

  # Hardware Adjustments

  services.thermald.enable = true;

  # Steam (TODO: move to module)

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  # Enable OpenGL
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # services.xserver.videoDrivers = [ "nvidia" ];

  environment.systemPackages = with pkgs; [
    mangohud
    protonup-qt
    lutris
    bottles
    heroic
    umu-launcher
    vkd3d-proton
    dxvk
  ];

  services.homeSiteTelemetry = {
    enable = true;
    baseUrl = "https://maxschaefer.me";
    deviceStatus = {
     enable = true;
     repoPath = "/home/max/nixos";
    };
  };

  # Host config

  networking.hostName = "max-g14-nix"; # Define your hostname.

  # Warning!
  system.stateVersion = "24.11"; # Did you read the comment?

}
