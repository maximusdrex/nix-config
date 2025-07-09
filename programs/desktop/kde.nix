{ config, pkgs, ... }:

{
  # Packages that should be installed to all devices
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


  ];

  services.kdeconnect.enable = true;
}
