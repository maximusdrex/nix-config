{ config, pkgs, ... }:

{

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

    # Python
    python3Full
    uv

    # Dev tools
    jetbrains.clion
    jetbrains.pycharm-professional
    distrobox
    distrobox-tui
    gcc_multi
    cmake
    gnumake
    ninja
    just
    inetutils
    wireshark
    wishlist
  ];
}
