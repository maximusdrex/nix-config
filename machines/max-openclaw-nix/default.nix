{ config, lib, pkgs, inputs, ... }:
let
  zerotierIPv6 = lib.strings.removeSuffix "\n" (
    builtins.readFile ../../vars/per-machine/max-openclaw-nix/zerotier/zerotier-ip/value
  );
in
{
  imports = [
    ./hardware-configuration.nix
    ../../roles/server.nix
  ];

  nixpkgs.overlays = [ inputs.nix-openclaw.overlays.default ];

  networking.firewall = {
    enable = lib.mkForce true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ 33333 ];
  };

  networking.hostName = "max-openclaw-nix";

  systemd.sockets.openclaw-zerotier-proxy = {
    description = "OpenClaw ZeroTier IPv6 listener";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "[${zerotierIPv6}]:18789" ];
    socketConfig = {
      BindIPv6Only = "ipv6-only";
      FreeBind = true;
      NoDelay = true;
    };
  };

  systemd.services.openclaw-zerotier-proxy = {
    description = "Proxy ZeroTier IPv6 OpenClaw traffic to localhost";
    requires = [ "openclaw-zerotier-proxy.socket" ];
    after = [ "openclaw-zerotier-proxy.socket" ];
    serviceConfig = {
      Type = "notify";
      ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:18789";
      DynamicUser = true;
      PrivateTmp = true;
    };
  };

  system.stateVersion = "25.05";
}
