{ config, pkgs, ... }:

{
  # Boilerplate
  home.username = "max";
  home.homeDirectory = "/home/max";

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  # Imports
  imports = [
    # Generic Programs
    ../../programs
    ../../programs/shell
    ../../programs/dev
    ../../programs/container
    ../../programs/onedrive
    # Desktop Programs
    ../../programs/desktop
    ../../programs/terminal
    ../../programs/embedded
    ../../programs/rf
  ];

  home.packages = with pkgs; [
    rclone
    keepassxc
    fastfetch
    neo-cowsay
    nix-tree
    caligula
    wireguard-tools
    vlc
    libreoffice-qt6-fresh
    discord
    pulseview
    # openscad-unstable
    nvc
    particle-cli
  ];
}
