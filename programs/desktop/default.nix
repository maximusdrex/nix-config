{ config, pkgs, ... }:

{
  imports = [
    ./kde.nix
  ];

  # Packages that should be installed to all devices
  home.packages = with pkgs; [
    google-chrome
    
    # Work
    slack
    thunderbird
    qgroundcontrol
    gpu-screen-recorder-gtk

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
  ];
}
