{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # utils

    file
    which
    tree
    gnused
    gnutar
    gawk
    zstd
    gnupg
 
    # nix

    direnv
    nix-output-monitor
  ];

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  programs.oh-my-posh = {
     enable = true;
     useTheme = "easy-term";
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin"
    '';

    # set some aliases, feel free to add more or remove some
    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
    };
  };

}
