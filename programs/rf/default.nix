{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # RF
    gnuradio
    gnuradioPackages.fosphor
    gnuradioPackages.osmosdr
    gnuradioPackages.lora_sdr
    rtl-sdr-osmocom
    soapysdr
    soapyrtlsdr
  ];
}
