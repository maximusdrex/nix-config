{ config, pkgs, ... }:

{

  services.emacs = {
    enable=true;
    defaultEditor=true;
  };

  programs.emacs = {
    enable=true;
    package=pkgs.emacs;
    extraPackages= epkgs: [
      epkgs.org
      epkgs.nixfmt
      epkgs.nix-mode
    ];
  };

  home.packages = with pkgs; [
    # networking tools

    mtr # A network diagnostic tool
    iperf3
    dnsutils  # `dig` + `nslookup`
    ldns # replacement of `dig`, it provide the command `drill`
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    socat # replacement of openbsd-netcat
    nmap # A utility for network discovery and security auditing
    ipcalc  # it is a calculator for the IPv4/v6 addresses
    fd

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
    # jstest-gtk build failed
    linuxConsoleTools

    # Python
    python3
    uv

    # Dev tools
    gcc_multi
    cmake
    gnumake
    ninja
    just
    inetutils

    wishlist
    go
    pkg-config
    pcsclite

    devcontainer
    wl-clipboard-rs
  ];
}
