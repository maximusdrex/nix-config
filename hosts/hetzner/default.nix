{ config, pkgs, ... }:

########################
# Host-specific config
########################

{
  # Import auto-configured hardware settings
  imports =
    [ 
       ./hardware-configuration.nix
       ../../common/server
       ../../modules/wireguard
       ../../modules/wireguard/peers-export.nix
       ../../modules/edge-proxy
       ../../modules/deploy
       ../../modules/home-site
    ];

  ######################
  # 1. Bootloader
  ######################

  ######################
  # 2. Kernel
  ######################

  ######################
  # 3. Networking
  ######################

  ######################
  # 4. General Config
  ######################

  ######################
  # 6. Other
  ######################

  services.homeSiteTelemetry = {
    enable = true;
    deviceStatus = {
      enable = true;
      branch = "main";
      mode = "switch";
      status = "success";
      repoPath = "/var/lib/nix-deploy/work";
    };
  };

  services.edgeProxy = {
    enable = true;
    acmeEmail = "max@theschaefers.com";        # change to your email
    sites."home.maxschaefer.me" = {
      upstreamHost = "max-richard-nix";   # resolves to max-richard-nix.wg via the module
      upstreamPort = 8123;                # Home Assistant
    };
    # Add more sites later by extending 'sites'
  };

  services.gitDeploy = {
    enable   = true;
    repoUrl  = "git@github.com:maximusdrex/nix-config.git";  # or any git provider
    branch   = "main";
    workTree = "/var/lib/nix-deploy/work";

    webhook = {
      enable = true;
      address = "127.0.0.1";
      port = 9099;
      # This file lives *inside the repo* and is already decrypted by your setup
      secretFilePath = "/var/lib/nix-deploy/work/secrets/deploy/webhook_secret.txt";
    };
    gitCrypt = {
      enable      = true;
      keyFilePath = "/var/lib/nix-deploy/secrets/git-crypt.key";
    };
    sshKeyPath = "/var/lib/nix-deploy/secrets/deploy_key";

    buildAll = false;         # don’t realize any outputs
    switchSelf = false;       # don’t switch the VPS
    validateMode = "dry-run"; # default; or "eval" to be even lighter

    timer.enable = false;        # safety net
    timer.onCalendar = "daily"; # or "hourly"

    report = {
      enable = true;
      file   = "/var/log/nix-deploy/last.json";
      url    = "https://maxschaefer.me/api/deploy/report";
    };
  };

  services.nginx.virtualHosts."maxschaefer.me".locations."/hooks/deploy" = {
    proxyPass = "http://127.0.0.1:9099";
    extraConfig = ''
      limit_except POST { deny all; }
      client_max_body_size 256k;
    '';
  };

  services.maxHomeSite = {
    enable = true;
    domain = "maxschaefer.me";
    secretEnvFile = "/var/lib/home-site/secrets/env";
  };

  users.users.nginx.extraGroups = [ "acme" ];

  # Host config

  networking.hostName = "max-hetzner-nix"; # Define your hostname.

  # Warning!
  system.stateVersion = "25.05"; # Did you read the comment?

}
