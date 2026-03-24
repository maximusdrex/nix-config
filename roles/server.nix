{ ... }:
{
  imports = [
    ./base.nix
    ../modules/ssh
  ];

  users.users.max = {
    isNormalUser = true;
    description = "Max Schaefer";
    extraGroups = [ "wheel" "docker" ];
  };

  networking.firewall.enable = false;
}
