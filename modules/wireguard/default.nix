{ config, pkgs, ... }:

let
  wg-hosts = import ./wg-hosts.nix;
  lookup = { host-list, host }: builtins.head (builtins.filter (x: x.hostname == host) host-list);
  hostname = config.networking.hostName;
in
{
  # Client config
  # Keepalive may not always be quite so necessary...

  networking.wireguard.enable = true;
  networking.wireguard.interfaces.wg0 = {
    privateKeyFile = "/etc/wireguard/privatekey"; # TODO: verify this is allowed
    ips = [ ((lookup { host-list = wg-hosts; host = hostname; }).ip + "/24") ];
    listenPort = 33333;
    peers = if (lookup { host-list = wg-hosts; host = hostname; }).server
      then
        builtins.map (host: {
          name = host.hostname;
          publicKey = 
            (builtins.readFile (../../secrets/wireguard + host.pubkeyFile));
          allowedIPs = [ (host.ip + "/32") ];
        }) (builtins.filter (host: !host.server) wg-hosts)
      else [
        { 
          name = "maxschaefer.me";
          endpoint = "maxschaefer.me:33333";
          publicKey = (builtins.readFile ../../secrets/wireguard/public/max-hetzner-nix);
          allowedIPs = [ "10.20.0.0/24" ];
          persistentKeepalive = 20;
        }
      ];
    
  };

  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
}
