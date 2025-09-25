{ lib, config, ... }:

let
  # Single source of truth: your existing list
  peers = import ./wg-hosts.nix;
in
{
  options.networking.wireguardPeers = lib.mkOption {
    # Allow arbitrary extra keys per peer (e.g. pubkeyFile), but ensure hostname/ip exist.
    type = lib.types.listOf (lib.types.submodule {
      freeformType = lib.types.attrs;  # accept any extra attrs from wg-hosts.nix

      options = {
        hostname = lib.mkOption {
          type = lib.types.str;
          description = "WG peer hostname (from wg-hosts.nix)";
        };
        ip = lib.mkOption {
          type = lib.types.str;
          description = "WG peer IP (e.g., 10.20.0.X)";
        };
      };
    });

    default = [ ];
    description = "Export of WireGuard peers derived from modules/wireguard/wg-hosts.nix";
  };

  config.networking.wireguardPeers = peers;
}

