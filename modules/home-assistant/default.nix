{ lib, config, pkgs, ... }:

let
  cfg = config.services.localHomeAssistant;
in
{
  options.services.localHomeAssistant = {
    enable = lib.mkEnableOption "Home Assistant with Matter & discovery for LAN";

    # Open the usual HA/discovery/Matter ports. Keeps things easy even if your global firewall is on.
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall for HA UI (8123), mDNS/SSDP, and Matter (5540).";
    };

    # Optional: set the WireGuard peer IP of the VPS so HA trusts X-Forwarded-* later.
    trustedProxyWireGuardIP = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.20.0.1";
      description = "WireGuard IP of the VPS reverse proxy; enables use_x_forwarded_for & trusted_proxies.";
    };

    # Extra HA components compiled in (nixpkgs HA uses this).
    extraComponents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "matter" "zeroconf" "ssdp" ];
      description = "Home Assistant integrations to include in the build.";
    };

    # Optionally pin HA to listen on specific addresses. Default 0.0.0.0 is fine for LAN + WG.
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address HA binds to (0.0.0.0 for all).";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Home Assistant HTTP port.";
    };
  };

  config = lib.mkIf cfg.enable {

    ############################
    # Home Assistant
    ############################
    services.home-assistant = {
      enable = true;

      # Basic config; use UI for most things.
      config = {
        default_config = {};
        # Prepare for reverse proxy later (enabled only if trustedProxyWireGuardIP is set)
        http =
          lib.mkIf (cfg.trustedProxyWireGuardIP != null) {
            use_x_forwarded_for = true;
            trusted_proxies = [ cfg.trustedProxyWireGuardIP ];
          };
      };

      extraComponents = cfg.extraComponents;

      # Bind address/port (works with the nginx on VPS later).
      extraOptions = [
        "--server-host"
        cfg.listenAddress
        "--server-port"
        (toString cfg.port)
      ];
    };

    ############################
    # Discovery (mDNS/SSDP) for Matter bridge commission
    ############################
    services.avahi = {
      enable = true;
      nssmdns = true;
      openFirewall = cfg.openFirewall;
      # Don't advertise over the WireGuard interface
      extraConfig = ''
        [server]
        deny-interfaces=wg0
      '';
    };

    ############################
    # Firewall (LAN + Matter)
    ############################
    networking.firewall = lib.mkIf cfg.openFirewall {
      enable = true;
      allowedTCPPorts = [ cfg.port 5540 ];
      allowedUDPPorts = [ 1900 5353 5540 ];
      # If you want HA UI only over WG later, you can remove cfg.port here and let the VPS reach it via wg0.
      # Alternatively, limit 8123 to your LAN interface with firewall.interfaces.<if>.allowedTCPPorts = [ cfg.port ];
    };

    # Matter likes IPv6 available on LANs.
    networking.enableIPv6 = lib.mkDefault true;
  };
}

