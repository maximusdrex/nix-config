{ config, pkgs, lib, ... }:

{
  home.username = "max";
  home.homeDirectory = "/home/max";

  home.stateVersion = "25.05";
  programs.home-manager.enable = true;

  imports = [
    ../../programs
    ../../programs/shell
    ../../programs/dev
    ../../programs/container
    ../../programs/onedrive
  ];

  programs.openclaw = {
    enable = true;
    documents = ./documents;
    config = {
      gateway = {
        mode = "local";
        bind = "lan";
        auth = {
          mode = "token";
          token = lib.strings.fileContents ../../secrets/openclaw/gateway-token;
        };
      };
      channels.telegram = {
        tokenFile = toString ../../secrets/openclaw/telegram-token;
        allowFrom = [ 12345678 ];
      };
      env.vars = {
        ANTHROPIC_API_KEY = lib.strings.fileContents ../../secrets/openclaw/anthropic-api-key;
      };
    };
  };
}
