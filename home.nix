{ config, pkgs, ... }:

{
  home.username = "max";
  home.homeDirectory = "/home/max";

  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    neofetch
    nnn # terminal file manager
    google-chrome

    # archives
    zip
    xz
    unzip
    p7zip

    # utils
    ripgrep # recursively searches directories for a regex pattern
    jq # A lightweight and flexible command-line JSON processor
    yq-go # yaml processor https://github.com/mikefarah/yq
    eza # A modern replacement for ‘ls’
    fzf # A command-line fuzzy finder

    # networking tools
    mtr # A network diagnostic tool
    iperf3
    dnsutils  # `dig` + `nslookup`
    ldns # replacement of `dig`, it provide the command `drill`
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    socat # replacement of openbsd-netcat
    nmap # A utility for network discovery and security auditing
    ipcalc  # it is a calculator for the IPv4/v6 addresses

    # misc
    cowsay
    file
    which
    tree
    gnused
    gnutar
    gawk
    zstd
    gnupg

    # nix related
    #
    # it provides the command `nom` works just like `nix`
    # with more details log output
    nix-output-monitor
    direnv

    # productivity
    hugo # static site generator
    glow # markdown previewer in terminal

    btop  # replacement of htop/nmon
    iotop # io monitoring
    iftop # network monitoring

    # system call monitoring
    strace # system call monitoring
    ltrace # library call monitoring
    lsof # list open files

    # system tools
    sysstat
    lm_sensors # for `sensors` command
    ethtool
    pciutils # lspci
    usbutils # lsusb
    jstest-gtk
    linuxConsoleTools

    # Dev tools
    jetbrains.clion
    jetbrains.pycharm-professional
    gcc-arm-embedded
    gcc_multi
    cmake
    gnumake
    ninja
    openocd
    just
    stlink
    inetutils
    wireshark
    distrobox
    distrobox-tui
    dive
    podman-tui
    podman-compose
    runc
    conmon
    skopeo
    platformio
    saleae-logic-2
    python3Full
    uv
    dpkg
    curl

    # Work
    slack
    thunderbird
    qgroundcontrol
    ffmpeg
    gpu-screen-recorder-gtk
    stm32cubemx
    qgis
    lxi-tools

    # Customization
    catppuccin-kvantum

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

    # Personal
    spotify
    spicetify-cli
    keepassxc
    rerun
    gdrive
    cbonsai

    # RF
    gnuradio
    gnuradioPackages.fosphor
    gnuradioPackages.osmosdr
    gnuradioPackages.lora_sdr
    rtl-sdr-osmocom
    soapysdr
    soapyrtlsdr
  ];

  # basic configuration of git
  programs.git = {
    enable = true;
    userName = "Maxwell Schaefer";
    userEmail = "maxwell.schafer@modalai.com";
  };

  services.kdeconnect.enable = true;

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  programs.onedrive.enable = true;

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


  # This value determines the home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update home Manager without changing this value. See
  # the home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "24.11";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
