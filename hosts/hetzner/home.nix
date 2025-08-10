{ config, pkgs, ... }:

{
  # Boilerplate
  home.username = "max";
  home.homeDirectory = "/home/max";

  home.stateVersion = "25.05";
  programs.home-manager.enable = true;

  # Imports
  imports = [
    # Generic Programs
    ../../programs
    ../../programs/shell
    ../../programs/dev
    ../../programs/container
    ../../programs/onedrive
  ];
}
