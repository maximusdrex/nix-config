{ lib, ... }:
let
  inherit (lib) mkOption;
  inherit (lib.types)
    bool
    enum
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
}
