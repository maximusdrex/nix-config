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
    htop
 
    gum

    # nix

    direnv
    # nix-output-monitor

    benhsm-minesweeper
  ];

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  programs.oh-my-posh = {
     enable = true;
     # useTheme = "montys";
     settings = builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile ./omp_style.json));
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

      sls = "_sysls --system";
      uls = "_sysls --user";

      sstart = "sudo systemctl start $(sls static,disabled,failed)";
      sre =    "sudo systemctl restart $(sls running,disabled,failed,static)";
      sstop =  "sudo systemctl stop  $(sls running,failed)";
      ustart = "systemctl --user start $(sls static,disabled,failed)";
      ure =    "systemctl --user restart $(sls running,disabled,failed,static)";
      ustop =  "systemctl --user stop  $(sls running,failed)";

      glog-short = "git log --sparse --abbrev-commit --oneline";
      glog = "git log --sparse --abbrev-commit --stat=60";
    };

    initExtra = ''
      _sysls() {
        WIDE=$1
        [ -n "$2" ] && STATE="--state=$2"
        cat \
            <(echo 'UNIT/FILE LOAD/STATE ACTIVE/PRESET SUB DESCRIPTION') \
            <(systemctl $WIDE list-units --quiet $STATE) \
            <(systemctl $WIDE list-unit-files --quiet $STATE) \
        | sed 's/●/ /' \
        | grep . \
        | column --table --table-columns-limit=5 \
        | fzf --header-lines=1 \
              --accept-nth=1 \
              --no-hscroll \
              --preview="SYSTEMD_COLORS=1 systemctl $WIDE status {1}" \
              --preview-window=down
      }
    '';
  };

}
