{ ... }:
{
  imports = [
    ./base.nix
  ];

  users.users.max = {
    isNormalUser = true;
    description = "Max Schaefer";
    extraGroups = [ "networkmanager" "wheel" "adbusers" "wireshark" "docker" "plugdev" "dialout" ];
    # Temporary fallback admin key while the SSH certificate flow is being tested.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC/qDFl92Ao8C4LVIbBsZQmlTzXa8+/lglFfIpD7VKp7 max@max-g14-nix"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFI8YFza97xCDAjC5c254wp2jtjyHOaWLJueVFqZp86r max@max-g14-nix"
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIKpPHAJv43ptCfwDPXvYfNhpX9WnkBx9azKbTTJH/E+pAAAABHNzaDo= max-fido-main"
    ];
  };

  networking.firewall.enable = false;
}
