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


  ######################
  # 2. Kernel
  ######################

  ######################
  # 3. Networking
  ######################

  services.avahi = {
    enable = true;
    nssmdns = true;
    allowPointToPoint = true;
    openFirewall = true;
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

  hardware.graphics.extraPackages = with pkgs; [ vaapiIntel intel-media-driver ];

  services.thermald.enable = true;

  # Desktop-specific security settings
  security.unifiedAuth = {
    # Enable encrypted drive FIDO2 support (configure when keys arrive)
    encryptedDrive = {
      enable = false;  # Enable once security keys are available

      # Example configuration for encrypted root - adjust device path as needed
      devices = {
        root = {
          device = "/dev/nvme0n1p2";  # Check with lsblk - adjust to your setup
          enableFIDO2 = true;
          enablePassword = true;  # Keep password fallback
          enableRecovery = true;
          fidoDevices = [ "auto" ];
        };
      };

      recoveryKeyPath = "/etc/luks-recovery";
      timeout = 30;
    };
  };

  # Host config

  networking.hostName = "max-xps-modal"; # Define your hostname.

  # Warning!
  system.stateVersion = "24.11"; # Did you read the comment?

}
