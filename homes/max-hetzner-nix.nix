{ ... }:
{
  imports = [ ./common.nix ];

  home.username = "max";
  home.homeDirectory = "/home/max";
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;
}
