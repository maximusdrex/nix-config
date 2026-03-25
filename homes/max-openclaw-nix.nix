{ ... }:
{
  imports = [ ./common.nix ];

  home.username = "max";
  home.homeDirectory = "/home/max";
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;

  home.file.".openclaw/openclaw.json".force = true;
  systemd.user.services.openclaw-gateway.Install.WantedBy = [ "default.target" ];

  programs.openclaw = {
    enable = true;
    documents = ../machines/max-openclaw-nix/documents;
    exposePluginPackages = false;
    bundledPlugins = {
      summarize.enable = true;
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
        bind = "loopback";
        controlUi.allowInsecureAuth = true;
        controlUi.allowedOrigins = [ "https://openclaw.maxschaefer.me" ];
        auth = {
          mode = "token";
          token = builtins.getEnv "OPENCLAW_GATEWAY_TOKEN";
        };
      };
      channels.telegram = {
        tokenFile = builtins.getEnv "OPENCLAW_TELEGRAM_TOKEN_FILE";
        allowFrom = [ 12345678 ];
      };
      env.vars = {
        ANTHROPIC_API_KEY = builtins.getEnv "ANTHROPIC_API_KEY";
        CODEX_HOME = builtins.getEnv "CODEX_HOME";
      };
    };
  };
}
