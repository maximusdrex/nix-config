{ lib, ... }:
let
  inherit (lib) mkOption;
  inherit (lib.types)
    bool
    enum
    ints
    lines
    listOf
    nullOr
    port
    str
    submodule
    ;
in
{
  options.routes = mkOption {
    default = [ ];
    type = listOf (
      submodule {
        options = {
          routeName = mkOption {
            type = str;
          };

          machineName = mkOption {
            type = str;
          };

          fqdn = mkOption {
            type = str;
          };

          path = mkOption {
            type = str;
          };

          port = mkOption {
            type = port;
          };

          scheme = mkOption {
            type = enum [
              "http"
              "https"
            ];
          };

          proxyWebsockets = mkOption {
            type = bool;
          };

          locationExtraConfig = mkOption {
            type = lines;
          };

          upstreamIP = mkOption {
            type = nullOr str;
          };
        };
      }
    );
  };

  options.transports = mkOption {
    default = [ ];
    type = listOf (
      submodule {
        options = {
          routeName = mkOption {
            type = str;
          };

          machineName = mkOption {
            type = str;
          };

          protocol = mkOption {
            type = enum [
              "tcp"
              "udp"
            ];
          };

          publicPort = mkOption {
            type = port;
          };

          upstreamPort = mkOption {
            type = port;
          };

          proxyTimeout = mkOption {
            type = str;
          };

          connectionLimitPerIP = mkOption {
            type = ints.positive;
          };

          upstreamIP = mkOption {
            type = nullOr str;
          };
        };
      }
    );
  };
}
