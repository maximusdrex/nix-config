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

    trustedProxyIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "IP addresses of reverse proxies allowed to forward requests to Home Assistant.";
    };

    # Legacy singular option retained during the WireGuard -> Clan migration.
    trustedProxyWireGuardIP = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.20.0.1";
      description = "Legacy single trusted proxy IP.";
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
    services.home-assistant =
      let
        trustedProxyIPs = cfg.trustedProxyIPs ++ lib.optional (cfg.trustedProxyWireGuardIP != null) cfg.trustedProxyWireGuardIP;
      in
      {

        ############################
        # Home Assistant
        ############################
        enable = true;

        # Home Assistant YAML (merged into configuration.yaml)
        config = {
          default_config = {};

          http = {
            server_host = cfg.listenAddress;
            server_port = cfg.port;

            # Only set proxy bits when trusted proxy IPs are configured.
            use_x_forwarded_for = trustedProxyIPs != [ ];
            trusted_proxies = lib.mkIf (trustedProxyIPs != [ ]) trustedProxyIPs;
          };
        };

        extraComponents = cfg.extraComponents;
      };

    ############################
    # Discovery (mDNS/SSDP)
    ############################
    services.avahi = {
      enable = true;
      nssmdns4 = true;
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
