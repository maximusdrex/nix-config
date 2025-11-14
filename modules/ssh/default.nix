{ config, pkgs, ... }:

let
  ssh-keys = import ./ssh-keys.nix { inherit pkgs; };
  lookup = { host-list, host }: builtins.head (builtins.filter (x: x.hostname == host) host-list);
  hostname = config.networking.hostName;
in
{
  # Install some programs.
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = false;
      AllowUsers = null;
      UseDns = true;
    };
  };

  users.users.max.openssh.authorizedKeys.keys = ssh-keys;
}
