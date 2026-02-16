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

  home.file.".openclaw/openclaw.json".force = true;
  systemd.user.services.openclaw-gateway.Install.WantedBy = [ "default.target" ];

  programs.openclaw = {
    enable = true;
    documents = ./documents;
    exposePluginPackages = false;
    bundledPlugins = {
      summarize.enable = true;
      oracle.enable = true;
    };
    config = {
      agents.defaults.model.primary = "openai-codex/gpt-5.3-codex";
      auth = {
        profiles = {
          "openai-codex:default" = {
            provider = "openai-codex";
            mode = "oauth";
          };
        };
        order = {
          "openai-codex" = [ "openai-codex:default" ];
        };
      };
      gateway = {
        mode = "local";
        bind = "lan";
        controlUi = {
          allowInsecureAuth = true;
        };
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
        CODEX_HOME = toString ../../secrets/openclaw/codex;
      };
    };
  };
}
