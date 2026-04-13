{ pkgs, ... }:
{
  imports = [ ./common.nix ];

  home.username = "max";
  home.homeDirectory = "/home/max";
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    # KDE tools
    kdePackages.kalk
    kdePackages.calligra
    kdePackages.cantor
    kdePackages.filelight
    kdePackages.isoimagewriter
    kdePackages.kalarm
    kdePackages.kalgebra
    kdePackages.kamera
    kdePackages.kbackup
    kdePackages.kcron
    kdePackages.kdf
    kdePackages.kdialog
    kdePackages.keysmith
    kdePackages.kfind
    kdePackages.kget
    kdePackages.kgpg
    kdePackages.kgraphviewer
    kdePackages.kigo
    kdePackages.kio-admin
    kdePackages.kio-fuse
    kdePackages.kio-extras
    kdePackages.kio-gdrive
    kdePackages.kio-zeroconf
    kdePackages.kjournald
    kdePackages.kleopatra
    # kdePackages.kmail
    kdePackages.kmousetool
    kdePackages.kmplot
    kdePackages.koko
    kdePackages.kompare
    kdePackages.korganizer
    # kdePackages.kqtquickcharts
    kdePackages.kpmcore
    kdePackages.krfb
    kdePackages.ksystemlog
    kdePackages.ktimer
    kdePackages.partitionmanager
    kdePackages.kaccounts-integration
    kdePackages.kaccounts-providers
    kdePackages.qtstyleplugin-kvantum
    kdePackages.qt6ct
    kdePackages.signond
    kdePackages.extra-cmake-modules
    kdePackages.plymouth-kcm
    kdePackages.breeze-plymouth
    kdePackages.kio-extras-kf5
    kdePackages.bluedevil
    kdePackages.discover
    kdePackages.drkonqi
    kdePackages.flatpak-kcm
    kdePackages.kactivitymanagerd
    kdePackages.kde-cli-tools
    kdePackages.kde-gtk-config
    kdePackages.kdecoration
    kdePackages.kdeplasma-addons
    kdePackages.kinfocenter
    kdePackages.kglobalacceld
    kdePackages.ksystemstats
    kdePackages.kwallet-pam
    kdePackages.kwayland
    kdePackages.plasma-systemmonitor
    kdePackages.xdg-desktop-portal-kde
    kdePackages.karousel
    kdePackages.krohnkite
    kdePackages.kzones
    kdePackages.pimcommon
    kdePackages.kdepim-runtime
    kdePackages.kdepim-addons
    kdePackages.akonadi
    kdePackages.akonadi-search
    kdePackages.akonadi-calendar-tools
    kdePackages.akonadi-calendar
    kdePackages.akonadi-contacts
    kdePackages.akonadi-mime
    kdePackages.akonadiconsole
    kdePackages.akonadi-import-wizard
    catppuccin-kde
  ];

  services.kdeconnect.enable = true;

  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    themes = { catppuccin-mocha = {
      background = "1e1e2e";
      cursor-color = "f5e0dc";
      foreground = "cdd6f4";
      palette = [
        "0=#45475a"
        "1=#f38ba8"
        "2=#a6e3a1"
        "3=#f9e2af"
        "4=#89b4fa"
        "5=#f5c2e7"
        "6=#94e2d5"
        "7=#bac2de"
        "8=#585b70"
        "9=#f38ba8"
        "10=#a6e3a1"
        "11=#f9e2af"
        "12=#89b4fa"
        "13=#f5c2e7"
        "14=#94e2d5"
        "15=#a6adc8"
      ];
      selection-background = "353749";
      selection-foreground = "cdd6f4";
    }; };
    settings = {
      # gtk-titlebar = true;
      # window-decoration = "client";
      background-opacity = 0.6;
      background-blur = true;
      font-family = "Berkeley Mono";
    };
  };

  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhs;
  };

  services.emacs = {
    enable=true;
    defaultEditor=true;
  };

  programs.emacs = {
    enable=true;
    package=pkgs.emacs;
  };

}
