{ config, pkgs, ... }:

{
  # Packages that should be installed to all devices
  home.packages = with pkgs; [
    neofetch
    nnn # terminal file manager
    
    # archives

    zip
    xz
    unzip
    p7zip

    ripgrep # recursively searches directories for a regex pattern
    jq # A lightweight and flexible command-line JSON processor
    yq-go # yaml processor https://github.com/mikefarah/yq
    eza # A modern replacement for ‘ls’
    fzf # A command-line fuzzy finder
    curl

    ffmpeg

  ];

  # basic configuration of git
  # TODO: make host-specific
  programs.git = {
    enable = true;
    userName = "Maxwell Schaefer";
    userEmail = "maxwell.schafer@modalai.com";
  };

}
