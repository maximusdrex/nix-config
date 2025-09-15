{ config, pkgs, ... }:

{
  imports = [
    ./kde.nix
  ];

  # Packages that should be installed to all devices
  home.packages = with pkgs; [
    google-chrome
    discord
    
    # Dev
    #(jetbrains.clion.override {
    #  jdk = pkgs.openjdk21;
    #})
    #(jetbrains.pycharm-professional.override {
    #  jdk = pkgs.openjdk21;
    #})
    # jetbrains.rust-rover
    jetbrains-toolbox
    jetbrains.clion
    jetbrains.pycharm-professional
    distrobox
    distrobox-tui
    wireshark

    # Work
    slack
    thunderbird
    qgroundcontrol
    gpu-screen-recorder-gtk
    stm32cubemx
    segger-jlink
    
    betaflight-configurator

    # Customization
    catppuccin-kvantum

    # Personal
    spotify
    spicetify-cli
    keepassxc
    rerun
    gdrive
    cbonsai
    qalculate-qt
    anytype
    nom
    codex
    arduino-ide

    vlc
  ];

  programs.jetbrains-remote = {
    enable = true;
    ides = with pkgs.jetbrains; [ clion pycharm-professional ];
  };

  programs.vscode.enable = true;
}
