{ config, pkgs, lib, ... }:

let
  wg-hosts = import ./wg-hosts.nix;
  lookup = { host-list, host }: builtins.head (builtins.filter (x: x.hostname == host) host-list);
  hostname = config.networking.hostName;
  selfHost = lookup { host-list = wg-hosts; host = hostname; };
  isServer = selfHost.server;
in
{
  # Client config
  # Keepalive may not always be quite so necessary...

  networking.wireguard.enable = true;
  networking.wireguard.interfaces.wg0 = {
    privateKeyFile = "/etc/wireguard/privatekey"; # TODO: verify this is allowed
    ips = [ (selfHost.ip + "/24") ];
    listenPort = 33333;
    peers = if isServer
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
          dynamicEndpointRefreshSeconds = 30;
        }
      ];
    
  };

  networking.firewall.extraCommands = lib.mkIf isServer ''
    iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i wg0 -j ACCEPT
    iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o wg0 -j ACCEPT
  '';

  boot.kernel.sysctl = lib.mkIf isServer {
    "net.ipv4.ip_forward" = 1;
  };

  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
}
