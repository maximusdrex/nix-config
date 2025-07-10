{ config, pkgs, ... }:

{
  networking.networkmanager.ensureProfiles.profiles = {
    "Wired connection 2" = {
      connection = {
        autoconnect-priority = "1";
        id = "Wavemux";
        interface-name = "wmx0";
        type = "ethernet";
        uuid = "d8644757-47df-3162-8177-5b4f8453e10b";
      };
      ethernet = {
        mtu = 256;
      };
      ipv4 = {
        address1 = "10.0.5.2/24";
        method = "manual";
      };
      ipv6 = {
        method = "disabled";
      };
      proxy = { };
    };
  };
}
