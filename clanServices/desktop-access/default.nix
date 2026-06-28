{
  clanLib,
  directory,
  lib,
  ...
}:
let
  inherit (lib) types;

  generatorName = instanceName: "desktop-access-${instanceName}";

  publicKeyFor =
    instanceName: machineName:
    clanLib.getPublicValue {
      flake = directory;
      machine = machineName;
      generator = generatorName instanceName;
      file = "id_ed25519.pub";
      default = null;
    };
in
{
  _class = "clan.service";
  manifest.name = "desktop-access";
  manifest.description = "Recoverable per-desktop SSH keys for max user access to server hosts";
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
    description = "Authorizes desktop-access client keys for max user logins.";

    interface =
      { lib, ... }:
      {
        options.user = lib.mkOption {
          type = types.str;
          default = "max";
          description = "Local user that receives desktop client authorized keys.";
        };
      };

    perInstance =
      {
        instanceName,
        roles,
        settings,
        ...
      }:
      let
        clientMachineNames = lib.attrNames (roles.client.machines or { });
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
        nixosModule = {
          assertions = [
            {
              assertion = missingClientKeys == [ ];
              message = ''
                desktop-access server needs generated client public keys for:
                ${builtins.concatStringsSep ", " (map (entry: entry.machineName) missingClientKeys)}

                Run `clan vars generate ${builtins.concatStringsSep " " (map (entry: entry.machineName) missingClientKeys)}`.
              '';
            }
          ];

          users.users.${settings.user}.openssh.authorizedKeys.keys = lib.mkAfter (
            map (entry: entry.publicKey) (lib.filter (entry: entry.publicKey != null) clientKeys)
          );
        };
      };
  };
}
