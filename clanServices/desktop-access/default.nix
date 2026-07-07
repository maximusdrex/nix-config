{
  clanLib,
  directory,
  lib,
  ...
}:
let
  inherit (lib) types;

  generatorName = instanceName: "desktop-access-${instanceName}";
  accessOptions = {
    user = lib.mkOption {
      type = types.str;
      default = "max";
      description = "Primary local user that receives desktop client authorized keys.";
    };

    users = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Additional local users that receive desktop client authorized keys.
        If empty, only `user` is authorized.
      '';
    };
  };

  publicKeyFor =
    instanceName: machineName:
    clanLib.getPublicValue {
      flake = directory;
      machine = machineName;
      generator = generatorName instanceName;
      file = "id_ed25519.pub";
      default = null;
    };

  formatListenAddress =
    addr:
    if lib.hasInfix ":" addr && !(lib.hasPrefix "[" addr) then
      "[${addr}]"
    else
      addr;

  authorizedKeysModule =
    {
      instanceName,
      roleName,
      roles,
      settings,
    }:
    let
      clientMachineNames = lib.attrNames (roles.client.machines or { });
      authorizedUsers = lib.unique ([ settings.user ] ++ settings.users);
      clientKeys = map (
        machineName:
        {
          inherit machineName;
          publicKey = publicKeyFor instanceName machineName;
        }
      ) clientMachineNames;
      missingClientKeys = lib.filter (entry: entry.publicKey == null) clientKeys;
    in
    {
      assertions = [
        {
          assertion = missingClientKeys == [ ];
          message = ''
            desktop-access ${roleName} needs generated client public keys for:
            ${builtins.concatStringsSep ", " (map (entry: entry.machineName) missingClientKeys)}

            Run `clan vars generate ${builtins.concatStringsSep " " (map (entry: entry.machineName) missingClientKeys)}`.
          '';
        }
      ];

      users.users = lib.genAttrs authorizedUsers (_user: {
        openssh.authorizedKeys.keys = lib.mkAfter (
          map (entry: entry.publicKey) (lib.filter (entry: entry.publicKey != null) clientKeys)
        );
      });
    };
in
{
  _class = "clan.service";
  manifest.name = "desktop-access";
  manifest.description = "Recoverable per-desktop SSH keys for access to server hosts";
  manifest.categories = [
    "Security"
    "System"
  ];
  manifest.readme = builtins.readFile ./README.md;

  roles.client = {
    description = "Generates and installs a recoverable SSH key for the max user.";

    interface =
      { lib, ... }:
      {
        options = {
          user = lib.mkOption {
            type = types.str;
            default = "max";
            description = "Local user that receives the managed SSH private key.";
          };

          keyName = lib.mkOption {
            type = types.str;
            default = "id_clan_desktop";
            description = "Filename for the managed key under the user's .ssh directory.";
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
      {
        nixosModule =
          { config, pkgs, ... }:
          let
            generator = generatorName instanceName;
            user = config.users.users.${settings.user};
            sshDir = "${user.home}/.ssh";
            privateKeyPath = "${sshDir}/${settings.keyName}";
            publicKeyPath = "${privateKeyPath}.pub";
            secretPrivateKey = config.clan.core.vars.generators.${generator}.files."id_ed25519".path;
          in
          {
            assertions = [
              {
                assertion = builtins.hasAttr settings.user config.users.users;
                message = "desktop-access client '${machine.name}' needs local user '${settings.user}'.";
              }
            ];

            clan.core.vars.generators.${generator} = {
              files = {
                "id_ed25519" = {
                  neededFor = "services";
                };
                "id_ed25519.pub" = {
                  deploy = false;
                  secret = false;
                };
              };
              runtimeInputs = [ pkgs.openssh ];
              script = ''
                ssh-keygen -t ed25519 -N "" -C "${settings.user}@${machine.name}" -f "$out"/id_ed25519
              '';
            };

            system.activationScripts.desktopAccessKey = lib.stringAfter [
              "users"
              "groups"
              "setupSecrets"
            ] ''
              install -d -m 0700 -o ${settings.user} -g ${user.group} ${sshDir}
              install -m 0600 -o ${settings.user} -g ${user.group} ${secretPrivateKey} ${privateKeyPath}
              ${pkgs.openssh}/bin/ssh-keygen -y -f ${privateKeyPath} > ${publicKeyPath}
              chown ${settings.user}:${user.group} ${publicKeyPath}
              chmod 0644 ${publicKeyPath}
            '';

            programs.ssh.extraConfig = ''
              Match localuser ${settings.user}
                IdentityFile ${privateKeyPath}
                IdentitiesOnly no
            '';
          };
      };
  };

  roles.server = {
    description = "Authorizes desktop-access client keys for server logins.";

    interface = { ... }: { options = accessOptions; };

    perInstance =
      {
        instanceName,
        roles,
        settings,
        ...
      }:
      {
        nixosModule = authorizedKeysModule {
          inherit instanceName roles settings;
          roleName = "server";
        };
      };
  };

  roles.desktop = {
    description = "Authorizes desktop-access client keys for desktop logins and restricts SSH to Clan networks.";

    interface =
      { lib, ... }:
      {
        options = accessOptions // {
          restrictSshToClanNetworks = lib.mkOption {
            type = types.bool;
            default = true;
            description = "Bind sshd only to loopback and clan.core.networking.internalListenAddresses.";
          };
        };
      };

    perInstance =
      {
        instanceName,
        roles,
        settings,
        ...
      }:
      {
        nixosModule =
          { config, lib, ... }:
          let
            internalListenAddresses = config.clan.core.networking.internalListenAddresses;
            listenAddresses =
              [
                {
                  addr = "127.0.0.1";
                  port = 22;
                }
                {
                  addr = "[::1]";
                  port = 22;
                }
              ]
              ++ map (addr: {
                addr = formatListenAddress addr;
                port = 22;
              }) internalListenAddresses;
          in
          lib.mkMerge [
            (authorizedKeysModule {
              inherit instanceName roles settings;
              roleName = "desktop";
            })
            (lib.mkIf settings.restrictSshToClanNetworks {
              assertions = [
                {
                  assertion = internalListenAddresses != [ ];
                  message = "desktop-access desktop restrictSshToClanNetworks requires clan.core.networking.internalListenAddresses to be non-empty.";
                }
              ];

              services.openssh = {
                enable = true;
                startWhenNeeded = true;
                listenAddresses = lib.mkForce listenAddresses;
                settings = {
                  PermitRootLogin = lib.mkForce "prohibit-password";
                  PasswordAuthentication = lib.mkForce false;
                  KbdInteractiveAuthentication = lib.mkForce false;
                };
              };

              systemd.sockets.sshd.socketConfig.FreeBind = true;
            })
          ];
      };
  };
}
