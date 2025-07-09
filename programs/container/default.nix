{ config, pkgs, ... }:

{

  home.packages = with pkgs; [
    # Container tools
    dive
    podman-tui
    podman-compose
    runc
    conmon
    skopeo
  ];

}
