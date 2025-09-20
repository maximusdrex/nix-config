{ lib, config, pkgs, ... }:

let
  cfg = config.services.localHomeAssistant;
in
{
  options.services.localHomeAssistant = {
    enable = lib.mkEnableOption "Home Assistant with Matter & discovery for LAN";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall for HA UI (8123), mDNS/SSDP, and Matter (5540).";
    };

    # WireGuard IP (on the VPS) that will run the reverse proxy later.
    trustedProxyWireGuardIP = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.20.0.1";
      description = "WireGuard IP of the VPS reverse proxy; used in http.trusted_proxies.";
    };

    extraComponents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ 
        "matter" "zeroconf" "ssdp" 
        "upnp"
        "dlna_dmr"
        "cast"           # Chromecast
        "webostv"
        "met"            # Norwegian Met weather
        "radio_browser"
        "litterrobot"
        "homekit"
        "zeroconf"
      ];
      description = "Home Assistant integrations to compile in.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address HA binds to (http.server_host).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Home Assistant HTTP port (http.server_port).";
    };
  };

  config = lib.mkIf cfg.enable {

    ############################
    # Home Assistant
    ############################
    services.home-assistant = {
      enable = true;

      # Home Assistant YAML (merged into configuration.yaml)
      config = {
        default_config = {};

        http = {
          server_host = cfg.listenAddress;
          server_port = cfg.port;

          # Only set proxy bits when a proxy IP is provided
          use_x_forwarded_for = cfg.trustedProxyWireGuardIP != null;
          trusted_proxies =
            lib.mkIf (cfg.trustedProxyWireGuardIP != null)
              [ cfg.trustedProxyWireGuardIP ];
        };
      };

      extraComponents = cfg.extraComponents;
    };

    ############################
    # Discovery (mDNS/SSDP)
    ############################
    services.avahi = {
      enable = true;
      nssmdns = true;
      openFirewall = cfg.openFirewall;
      # Keep discovery chat on LAN, not over WireGuard
      extraConfig = ''
        [server]
        deny-interfaces=wg0
      '';
    };

    ############################
    # Firewall
    ############################
    networking.firewall = lib.mkIf cfg.openFirewall {
      enable = true;
      allowedTCPPorts = [ cfg.port 5540 21063 ];
      allowedUDPPorts = [ 1900 5353 5540 5353 ];
    };

    networking.enableIPv6 = lib.mkDefault true;
  };
}

