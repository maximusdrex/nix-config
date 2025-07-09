{ config, pkgs, ... }:

{

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    openocd
    stlink
    gcc-arm-embedded
    platformio
    saleae-logic-2
    stm32cubemx
    lxi-tools
  ];

}
