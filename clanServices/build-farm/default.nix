{
  clanLib,
  directory,
  lib,
  ...
}:
let
  inherit (lib) types;

  formatHost = host: if lib.hasInfix ":" host then "[${host}]" else host;

  baseGeneratorName = instanceName: "build-farm-${instanceName}";
  builderSSHGeneratorName = instanceName: "${baseGeneratorName instanceName}-builder-ssh";
  builderSSHPrivateGeneratorName = instanceName: "${baseGeneratorName instanceName}-builder-ssh-private";
  cacheKeyGeneratorName = instanceName: "${baseGeneratorName instanceName}-cache-key";
  cacheKeyPrivateGeneratorName = instanceName: "${baseGeneratorName instanceName}-cache-key-private";

  zerotierIPFor =
    machineName:
    clanLib.getPublicValue {
      flake = directory;
      machine = machineName;
      generator = "zerotier";
      file = "zerotier-ip";
      default = null;
    };

  cacheURLFor =
    cacheSettings: zerotierIP:
    "http://${formatHost zerotierIP}:${builtins.toString cacheSettings.port}?priority=${builtins.toString cacheSettings.priority}";

  varsForInstance =
    instanceName: pkgs:
    {
      clan.core.vars.generators = {
        "${builderSSHGeneratorName instanceName}" = {
          share = true;

          files = {
            "id_ed25519" = {
              deploy = false;
            };
            "id_ed25519.pub" = {
              deploy = false;
              secret = false;
            };
          };

          runtimeInputs = [ pkgs.openssh ];
          script = ''
            ssh-keygen -t ed25519 -N "" -C "build-farm-${instanceName}" -f "$out"/id_ed25519
          '';
        };

        "${cacheKeyGeneratorName instanceName}" = {
          share = true;

          files = {
            "secret-key" = {
              deploy = false;
            };
            "public-key" = {
              deploy = false;
              secret = false;
            };
          };

          runtimeInputs = [ pkgs.nix ];
          script = ''
            ${pkgs.nix}/bin/nix-store --generate-binary-cache-key \
              build-farm-${instanceName}-1 \
              "$out"/secret-key \
              "$out"/public-key
          '';
        };
      };
    };
in
{
  _class = "clan.service";
  manifest.name = "build-farm";
  manifest.description = "Remote Nix builders and an internal Harmonia cache over ZeroTier";
  manifest.categories = [
    "Development"
    "System"
  ];
  manifest.readme = builtins.readFile ./README.md;

  roles.builder = {
    description = "Accepts remote Nix builds over SSH.";
    interface =
      { lib, ... }:
      {
        options = {
          sshUser = lib.mkOption {
            type = types.str;
            default = "nixremote";
            description = "Dedicated SSH user for remote Nix builds.";
          };

          sshHost = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Optional SSH hostname override for this builder. If null, clients
              derive the SSH hostname from `<machine>.<builderDomain>`.
            '';
          };

          systems = lib.mkOption {
            type = types.listOf types.str;
            default = [ "x86_64-linux" ];
            description = "Systems this builder can execute.";
          };

          maxJobs = lib.mkOption {
            type = types.int;
            default = 8;
            description = "Maximum concurrent jobs clients should schedule on this builder.";
          };

          speedFactor = lib.mkOption {
            type = types.int;
            default = 20;
            description = "Relative builder speed used by Nix scheduling.";
          };

          supportedFeatures = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Features advertised to Nix for this builder.";
          };

          mandatoryFeatures = lib.mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Mandatory features required for this builder to be selected.";
          };
        };
      };

    perInstance =
      { instanceName, settings, ... }:
      {
        nixosModule =
          { config, pkgs, ... }:
          {
            imports = [ (varsForInstance instanceName pkgs) ];

            users.groups.${settings.sshUser} = { };
            users.users.${settings.sshUser} = {
              isNormalUser = true;
              createHome = true;
              group = settings.sshUser;
              home = "/var/lib/${settings.sshUser}";
              useDefaultShell = true;
              hashedPassword = "!";
              openssh.authorizedKeys.keys = [
                config.clan.core.vars.generators.${builderSSHGeneratorName instanceName}.files."id_ed25519.pub".value
              ];
            };

            nix.settings.builders-use-substitutes = true;
            nix.settings.trusted-users = lib.mkAfter [ settings.sshUser ];
          };
      };
  };

  roles.cache = {
    description = "Serves the local Nix store as an internal signed binary cache over ZeroTier.";
    interface =
      { lib, ... }:
      {
        options = {
          port = lib.mkOption {
            type = types.port;
            default = 5000;
            description = "TCP port used by the Harmonia cache.";
          };

          priority = lib.mkOption {
            type = types.int;
            default = 25;
            description = "Advertised cache priority in nix-cache-info.";
          };
        };
      };

    perInstance =
      {
        instanceName,
        machine,
        settings,
        ...
      }:
      let
        zerotierIP = zerotierIPFor machine.name;
      in
      {
        nixosModule =
          { config, pkgs, ... }:
          {
            imports = [ (varsForInstance instanceName pkgs) ];

            assertions = [
              {
                assertion = zerotierIP != null;
                message = ''
                  build-farm cache machine '${machine.name}' is missing a published ZeroTier IP.
                '';
              }
            ];

            clan.core.vars.generators.${cacheKeyPrivateGeneratorName instanceName} = {
              dependencies = [ (cacheKeyGeneratorName instanceName) ];
              files."secret-key" = { };
              script = ''
                cp $in/${cacheKeyGeneratorName instanceName}/secret-key $out/secret-key
              '';
            };

            networking.firewall.allowedTCPPorts = [ settings.port ];

            services.harmonia.cache = {
              enable = true;
              signKeyPaths = [
                config.clan.core.vars.generators.${cacheKeyPrivateGeneratorName instanceName}.files."secret-key".path
              ];
              settings = {
                bind = "${formatHost zerotierIP}:${builtins.toString settings.port}";
                priority = settings.priority;
              };
            };

            systemd.services.harmonia = {
              after = [
                "network-online.target"
                "zerotierone.service"
              ];
              requires = [ "zerotierone.service" ];
              wants = [ "network-online.target" ];
            };
          };
      };
  };

  roles.client = {
    description = "Uses remote builders and internal binary caches provided by the build farm.";
    interface =
      { lib, ... }:
      {
        options = {
          builderDomain = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Domain appended to builder machine names for SSH connections, such
              as `zt.example.com`. Required unless every builder sets `sshHost`.
            '';
          };

          offloadLocalBuilds = lib.mkOption {
            type = types.bool;
            default = false;
            description = "If true, set local Nix max-jobs to 0 so builds are offloaded.";
          };
        };
      };

    perInstance =
      {
        instanceName,
        machine,
        roles,
        settings,
        ...
      }:
      let
        allBuilderMachines = roles.builder.machines or { };
        allCacheMachines = roles.cache.machines or { };
        remoteBuilders = lib.filterAttrs (builderMachineName: _: builderMachineName != machine.name) allBuilderMachines;
        remoteBuilderNames = lib.attrNames remoteBuilders;

        buildersMissingDomainOverride = lib.filter (
          builderMachineName: remoteBuilders.${builderMachineName}.settings.sshHost == null
        ) remoteBuilderNames;

        cacheEntries = map (
          cacheMachineName:
          let
            cacheSettings = allCacheMachines.${cacheMachineName}.settings;
            zerotierIP = zerotierIPFor cacheMachineName;
          in
          {
            machineName = cacheMachineName;
            inherit cacheSettings zerotierIP;
          }
        ) (lib.attrNames allCacheMachines);

        cachesMissingZeroTierIP = lib.filter (entry: entry.zerotierIP == null) cacheEntries;
      in
      {
        nixosModule =
          { config, pkgs, ... }:
          let
            cacheURLs = map (entry: cacheURLFor entry.cacheSettings entry.zerotierIP) (
              lib.filter (entry: entry.zerotierIP != null) cacheEntries
            );
          in
          {
            imports = [ (varsForInstance instanceName pkgs) ];

            assertions = [
              {
                assertion = settings.builderDomain != null || buildersMissingDomainOverride == [ ];
                message = ''
                  build-farm client '${machine.name}' needs `builderDomain` or per-builder `sshHost`
                  settings for remote builders:
                  ${builtins.concatStringsSep ", " buildersMissingDomainOverride}
                '';
              }
              {
                assertion = cachesMissingZeroTierIP == [ ];
                message = ''
                  build-farm instance '${instanceName}' has cache machines without a published ZeroTier IP:
                  ${
                    builtins.concatStringsSep ", " (
                      map (entry: entry.machineName) cachesMissingZeroTierIP
                    )
                  }
                '';
              }
            ];

            clan.core.vars.generators.${builderSSHPrivateGeneratorName instanceName} =
              lib.mkIf (remoteBuilderNames != [ ]) {
                dependencies = [ (builderSSHGeneratorName instanceName) ];
                files."id_ed25519" = { };
                script = ''
                  cp $in/${builderSSHGeneratorName instanceName}/id_ed25519 $out/id_ed25519
                '';
              };

            nix.distributedBuilds = remoteBuilderNames != [ ];
            nix.buildMachines = map (
              builderMachineName:
              let
                builderSettings = remoteBuilders.${builderMachineName}.settings;
              in
              {
                hostName =
                  if builderSettings.sshHost != null then
                    builderSettings.sshHost
                  else
                    "${builderMachineName}.${settings.builderDomain}";
                protocol = "ssh-ng";
                sshUser = builderSettings.sshUser;
                sshKey =
                  config.clan.core.vars.generators.${builderSSHPrivateGeneratorName instanceName}.files."id_ed25519".path;
                systems = builderSettings.systems;
                maxJobs = builderSettings.maxJobs;
                speedFactor = builderSettings.speedFactor;
                supportedFeatures = builderSettings.supportedFeatures;
                mandatoryFeatures = builderSettings.mandatoryFeatures;
              }
            ) remoteBuilderNames;

            nix.settings.builders-use-substitutes = true;
            nix.settings.substituters = lib.mkAfter cacheURLs;
            nix.settings.trusted-public-keys = lib.mkAfter (
              lib.optional (cacheURLs != [ ]) (
                config.clan.core.vars.generators.${cacheKeyGeneratorName instanceName}.files."public-key".value
              )
            );
            nix.settings.trusted-substituters = lib.mkAfter cacheURLs;

            nix.settings.max-jobs = lib.mkIf settings.offloadLocalBuilds 0;
          };
      };
  };
}
