{ ... }:
{
  imports = [
    ./base.nix
  ];

  users.users.max = {
    isNormalUser = true;
    description = "Max Schaefer";
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC/qDFl92Ao8C4LVIbBsZQmlTzXa8+/lglFfIpD7VKp7 max@max-g14-nix"
    ];
  };

  networking.firewall.enable = false;
}
