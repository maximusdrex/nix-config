{ pkgs, ... }:
{
  imports = [
    ./desktop.nix
    ../modules/sigrok
  ];

  boot.plymouth = {
    enable = true;
    theme = "rings";
    themePackages = with pkgs; [
      (adi1090x-plymouth-themes.override {
        selected_themes = [ "rings" ];
      })
    ];
  };

  boot.blacklistedKernelModules = [ "dvb_usb_rtl28xxu" ];

  networking.firewall.allowedUDPPorts = [
    33333
    1234
  ];

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

  programs.kde-pim.merkuro = true;
  programs.fuse.enable = true;

  services.udev.packages = [ pkgs.rtl-sdr ];
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="0002", NAME="wmx0"
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="607[df]", GROUP="plugdev", MODE="0666"
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="2b04", ATTRS{idProduct}=="[cd]00?", GROUP="plugdev", MODE="0666"

    SUBSYSTEM!="usb|usb_device", GOTO="sipeed_rules_end"
    ACTION!="add", GOTO="sipeed_rules_end"
    ATTRS{idVendor}=="359f", MODE="0666", GROUP="plugdev", TAG+="uaccess"
    ENV{ID_MM_DEVICE_IGNORE}="1"
    LABEL="sipeed_rules_end"
  '';
  hardware.rtl-sdr.enable = true;

  systemd.user.services.mpris-proxy = {
    description = "Mpris proxy";
    after = [
      "network.target"
      "sound.target"
    ];
    wantedBy = [ "default.target" ];
    serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;
  services.thermald.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  environment.systemPackages = with pkgs; [
    protonup-qt
    umu-launcher
    vkd3d-proton
    dxvk
    waydroid-helper
  ];

  virtualisation.waydroid.enable = true;
  virtualisation.waydroid.package = pkgs.waydroid-nftables;
}
