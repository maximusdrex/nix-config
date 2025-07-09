{ config, pkgs, ... }:

{
  # Boilerplate
  home.username = "max";
  home.homeDirectory = "/home/max";

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  # Imports
  imports = [
    ../../programs
    ../../programs/shell
    ../../programs/terminal
    ../../programs/desktop
    ../../programs/dev
    ../../programs/container
    ../../programs/embedded
    ../../programs/rf
    ../../programs/onedrive
  ];
}
