{
  clanLib,
  directory,
  lib,
  ...
}:
let
  inherit (lib) types;

  credentialGeneratorName = instanceName: "anytype-${instanceName}-credentials";
  externalHostType = types.strMatching "^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$";
  stateDirType = types.strMatching "^/.*[^/]$";
  quotaType = types.strMatching "^[1-9][0-9]*(KiB|MiB|GiB|TiB)$";

  formatHost = host: if lib.hasInfix ":" host then "[${host}]" else host;

  zerotierIPFor =
    machineName:
    clanLib.getPublicValue {
      flake = directory;
      generator = "zerotier-ip-${machineName}-zerotier";
      file = "ip";
      default = null;
    };

  credentialsModule =
    instanceName: pkgs:
    {
      clan.core.vars.generators.${credentialGeneratorName instanceName} = {
        share = true;
        files = {
          "minio-access-key".neededFor = "services";
          "minio-secret-key".neededFor = "services";
          "mongo-password".neededFor = "services";
          "mongo-keyfile".neededFor = "services";
          "redis-password".neededFor = "services";
        };
        runtimeInputs = [
          pkgs.coreutils
          pkgs.openssl
        ];
        script = ''
          openssl rand -hex 16 > "$out/minio-access-key"
          openssl rand -hex 32 > "$out/minio-secret-key"
          openssl rand -hex 32 > "$out/mongo-password"
          openssl rand -base64 756 | tr -d '\n' > "$out/mongo-keyfile"
          openssl rand -hex 32 > "$out/redis-password"
        '';
      };
    };

  images = {
    node = "ghcr.io/anyproto/any-sync-node:v0.12.1@sha256:889523e321a996fdc68b78bafad876977a6d971e489ef19182430e05f96cfc10";
    coordinator = "ghcr.io/anyproto/any-sync-coordinator:v0.12.0@sha256:820673882197be81af719029ee121e6baeb05123254761c852bf6ab29a1d076f";
    filenode = "ghcr.io/anyproto/any-sync-filenode:v0.12.0@sha256:4fe75875a8c0e950394340ca67a3097d345a07a5c2a0d8691770571b67ca554b";
    consensus = "ghcr.io/anyproto/any-sync-consensusnode:v0.12.0@sha256:7d2c70d4c9713d013e3c9a597332f49e36935f369c6fff14ab3a0eeb68e29903";
    tools = "ghcr.io/anyproto/any-sync-tools:v0.6.1@sha256:c06a8ace7e16559f7b334b8ea1d27c07a47c5d45b5d0d5249fd9e035d9c62640";
    mongo = "docker.io/library/mongo:7.0.28@sha256:4510cf3d7050003e958745adb25d2deb3fb907430716162d9cc1a92eda2a6047";
    redis = "docker.io/redis/redis-stack-server:7.2.0-v6@sha256:92f0d6f0d2eb2582511f907f5bffbbedf10970e2427f4433ae2d3bec7e409c8b";
    minio = "docker.io/minio/minio:RELEASE.2024-07-04T14-25-45Z@sha256:5db7e40b69f0c3ad5a878521ff5029468e3070ef146c084dc2540e2d492075c4";
    minioClient = "docker.io/minio/mc:RELEASE.2024-07-03T20-17-25Z@sha256:6d38db3154539eb5bb9b6b43bf55ed74cf5d8713972b52a09dccea0483fb811f";
  };
in
{
  _class = "clan.service";
  manifest.name = "anytype";
  manifest.description = "Split Anytype sync network with public nodes and private storage";
  manifest.categories = [ "Network" ];
  manifest.readme = builtins.readFile ./README.md;

  roles.storage = {
    description = "Runs MongoDB, Redis, and MinIO on one private storage host.";

    interface =
      { lib, ... }:
      {
        options = {
          endpointHost = lib.mkOption {
            type = externalHostType;
            description = "ZeroTier DNS host for storage connections and the MongoDB replica member.";
          };

          endpointInterface = lib.mkOption {
            type = types.str;
            description = "Network interface that accepts storage connections.";
            example = "ztc65mo6gt";
          };

          stateDir = lib.mkOption {
            type = stateDirType;
            default = "/var/lib/anytype-public";
            description = "Persistent state directory for Anytype storage services.";
          };

          minioQuota = lib.mkOption {
            type = quotaType;
            default = "100GiB";
            description = "Total quota for the Anytype MinIO bucket.";
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
        nodeMachineNames = lib.attrNames (roles.nodes.machines or { });
        zerotierIP = zerotierIPFor machine.name;
        publishHost = formatHost (if zerotierIP == null then "::1" else zerotierIP);
      in
      {
        nixosModule =
          {
            config,
            inputs,
            pkgs,
            ...
          }:
          let
            credentialGenerator = credentialGeneratorName instanceName;
            credentialFile = name: config.clan.core.vars.generators.${credentialGenerator}.files.${name}.path;
            stateDir = settings.stateDir;
            runtimeDir = "/run/anytype-storage";
            secretsService = "anytype-storage-secrets.service";
            quadlet = config.virtualisation.quadlet;
            network = quadlet.networks.anytype;
            containers = quadlet.containers;

            daemonService = {
              Restart = "on-failure";
              RestartSec = "5s";
              TimeoutStartSec = 900;
            };

            oneShotService = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "no";
              TimeoutStartSec = 900;
            };

            infrastructure = image: dependencies: {
              autoStart = true;
              unitConfig = {
                Requires = dependencies;
                After = dependencies;
              };
              serviceConfig = daemonService;
              containerConfig = {
                inherit image;
                pull = "missing";
                networks = [ network.ref ];
              };
            };

            oneShot = image: dependencies: {
              autoStart = false;
              unitConfig = {
                Requires = dependencies;
                After = dependencies;
              };
              serviceConfig = oneShotService;
              containerConfig = {
                inherit image;
                pull = "missing";
                networks = [ network.ref ];
              };
            };
          in
          {
            imports = [
              inputs.quadlet-nix.nixosModules.quadlet
              (credentialsModule instanceName pkgs)
            ];

            assertions = [
              {
                assertion = zerotierIP != null;
                message = "Anytype storage host '${machine.name}' needs a published ZeroTier IP.";
              }
              {
                assertion = lib.length nodeMachineNames == 1;
                message = ''
                  Anytype instance '${instanceName}' needs exactly one nodes machine, but found:
                  ${builtins.concatStringsSep ", " nodeMachineNames}
                '';
              }
            ];

            systemd.tmpfiles.rules = [
              "d ${stateDir} 0700 root root -"
              "d ${stateDir}/storage 0700 root root -"
              "d ${stateDir}/storage/mongo-1 0700 999 root -"
              "d ${stateDir}/storage/redis 0700 root root -"
              "d ${stateDir}/storage/minio 0700 root root -"
            ];

            networking.firewall.interfaces.${settings.endpointInterface}.allowedTCPPorts = [
              6379
              9000
              27001
            ];

            systemd.services.anytype-storage-secrets = {
              description = "Render Anytype storage credentials";
              path = [ pkgs.coreutils ];
              script = ''
                install -m 0400 -o 999 -g 999 \
                  "$CREDENTIALS_DIRECTORY/mongo-keyfile" \
                  "$RUNTIME_DIRECTORY/mongo-keyfile"

                minio_access_key="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/minio-access-key")"
                minio_secret_key="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/minio-secret-key")"
                mongo_password="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/mongo-password")"
                redis_password="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/redis-password")"

                {
                  printf 'MINIO_ROOT_USER=%s\n' "$minio_access_key"
                  printf 'MINIO_ROOT_PASSWORD=%s\n' "$minio_secret_key"
                  printf 'AWS_ACCESS_KEY_ID=%s\n' "$minio_access_key"
                  printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$minio_secret_key"
                  printf 'MC_HOST_minio=http://%s:%s@minio:9000\n' "$minio_access_key" "$minio_secret_key"
                } > "$RUNTIME_DIRECTORY/minio.env"

                {
                  printf 'MONGO_INITDB_ROOT_USERNAME=anytype\n'
                  printf 'MONGO_INITDB_ROOT_PASSWORD=%s\n' "$mongo_password"
                } > "$RUNTIME_DIRECTORY/mongo.env"

                printf 'REDIS_PASSWORD=%s\n' "$redis_password" > "$RUNTIME_DIRECTORY/redis.env"
                chmod 0600 "$RUNTIME_DIRECTORY"/*.env
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                UMask = "0077";
                RuntimeDirectory = "anytype-storage";
                RuntimeDirectoryMode = "0700";
                LoadCredential = [
                  "minio-access-key:${credentialFile "minio-access-key"}"
                  "minio-secret-key:${credentialFile "minio-secret-key"}"
                  "mongo-password:${credentialFile "mongo-password"}"
                  "mongo-keyfile:${credentialFile "mongo-keyfile"}"
                  "redis-password:${credentialFile "redis-password"}"
                ];
              };
            };

            virtualisation.quadlet = {
              enable = true;
              autoUpdate.enable = false;

              networks.anytype.networkConfig = {
                driver = "bridge";
                interfaceName = "anytype0";
                ipv6 = true;
              };

              containers = {
                anytype-mongo = lib.recursiveUpdate (infrastructure images.mongo [ secretsService ]) {
                  containerConfig = {
                    networkAliases = [
                      "mongo-1"
                      settings.endpointHost
                    ];
                    environmentFiles = [ "${runtimeDir}/mongo.env" ];
                    exec = [
                      "--replSet"
                      "rs0"
                      "--port"
                      "27001"
                      "--bind_ip_all"
                      "--keyFile"
                      "/run/secrets/mongo-keyfile"
                    ];
                    volumes = [
                      "${stateDir}/storage/mongo-1:/data/db:Z"
                      "${runtimeDir}/mongo-keyfile:/run/secrets/mongo-keyfile:ro,Z"
                    ];
                    publishPorts = [
                      "${publishHost}:27001:27001"
                      "127.0.0.1:27001:27001"
                    ];
                    healthCmd = ''mongosh --port 27001 --quiet --username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "try { rs.initiate({_id:'rs0',members:[{_id:0,host:'${settings.endpointHost}:27001'}]}); } catch(e) { } rs.status().ok" | grep -q 1'';
                    healthInterval = "10s";
                    healthStartPeriod = "30s";
                    healthTimeout = "30s";
                    healthRetries = 12;
                    healthOnFailure = "kill";
                    notify = "healthy";
                  };
                };

                anytype-redis = lib.recursiveUpdate (infrastructure images.redis [ secretsService ]) {
                  containerConfig = {
                    networkAliases = [ "redis" ];
                    environmentFiles = [ "${runtimeDir}/redis.env" ];
                    entrypoint = [ "/bin/sh" ];
                    exec = [
                      "-ec"
                      ''
                        exec redis-server \
                          --port 6379 \
                          --dir /data/ \
                          --appendonly yes \
                          --maxmemory 256mb \
                          --maxmemory-policy noeviction \
                          --protected-mode yes \
                          --requirepass "$REDIS_PASSWORD" \
                          --loadmodule /opt/redis-stack/lib/redisbloom.so
                      ''
                    ];
                    volumes = [ "${stateDir}/storage/redis:/data:Z" ];
                    publishPorts = [
                      "${publishHost}:6379:6379"
                      "127.0.0.1:6379:6379"
                    ];
                    healthCmd = ''redis-cli --no-auth-warning -a "$REDIS_PASSWORD" --raw -p 6379 incr ping'';
                    healthInterval = "10s";
                    healthTimeout = "30s";
                    healthRetries = 3;
                    healthOnFailure = "kill";
                    notify = "healthy";
                  };
                };

                anytype-minio = lib.recursiveUpdate (infrastructure images.minio [ secretsService ]) {
                  containerConfig = {
                    networkAliases = [
                      "minio"
                      "minio-bucket.minio"
                    ];
                    environmentFiles = [ "${runtimeDir}/minio.env" ];
                    exec = [
                      "server"
                      "/data"
                      "--console-address"
                      ":9001"
                      "--address"
                      ":9000"
                    ];
                    volumes = [ "${stateDir}/storage/minio:/data:Z" ];
                    publishPorts = [
                      "${publishHost}:9000:9000"
                      "127.0.0.1:9000:9000"
                      "127.0.0.1:9001:9001"
                    ];
                    healthCmd = "bash -c ':> /dev/tcp/127.0.0.1/9000'";
                    healthInterval = "5s";
                    healthTimeout = "10s";
                    healthRetries = 3;
                    healthOnFailure = "kill";
                    notify = "healthy";
                  };
                };

                anytype-create-bucket =
                  lib.recursiveUpdate
                    (oneShot images.minioClient [
                      secretsService
                      containers.anytype-minio.ref
                    ])
                    {
                      containerConfig = {
                        environmentFiles = [ "${runtimeDir}/minio.env" ];
                        entrypoint = [ "/bin/sh" ];
                        exec = [
                          "-ec"
                          ''
                            mc mb --ignore-existing minio/minio-bucket
                            mc quota set minio/minio-bucket --size ${settings.minioQuota}
                          ''
                        ];
                      };
                    };
              };
            };
          };
      };
  };

  roles.nodes = {
    description = "Runs the public Anytype sync, coordinator, file, and consensus nodes.";

    interface =
      { lib, ... }:
      {
        options = {
          externalHosts = lib.mkOption {
            type = types.listOf externalHostType;
            description = "Ordered DNS hosts that Anytype clients use for all sync services.";
            example = [
              "node.zt.example.com"
              "anytype.example.com"
            ];
          };

          stateDir = lib.mkOption {
            type = stateDirType;
            default = "/var/lib/anytype-public";
            description = "Persistent state directory for Anytype nodes.";
          };

          fileDefaultLimit = lib.mkOption {
            type = types.ints.positive;
            default = 10737418240;
            description = "Default file allowance in bytes.";
          };

          sharedSpacesLimit = lib.mkOption {
            type = types.ints.positive;
            default = 100;
            description = "Maximum shared spaces for one account.";
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
        storageMachines = roles.storage.machines or { };
        storageMachineNames = lib.attrNames storageMachines;
        storageMachine =
          if lib.length storageMachineNames == 1 then
            storageMachines.${builtins.head storageMachineNames}
          else
            null;
        storageEndpointHost =
          if storageMachine == null then "invalid" else storageMachine.settings.endpointHost;
        zerotierIP = zerotierIPFor machine.name;
        publishHost = formatHost (if zerotierIP == null then "::1" else zerotierIP);
      in
      {
        nixosModule =
          {
            config,
            inputs,
            pkgs,
            ...
          }:
          let
            credentialGenerator = credentialGeneratorName instanceName;
            credentialFile = name: config.clan.core.vars.generators.${credentialGenerator}.files.${name}.path;
            stateDir = settings.stateDir;
            quadlet = config.virtualisation.quadlet;
            network = quadlet.networks.anytype;
            containers = quadlet.containers;
            renderService = "anytype-render-config.service";

            daemonService = {
              Restart = "on-failure";
              RestartSec = "5s";
              TimeoutStartSec = 900;
            };

            oneShotService = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "no";
              TimeoutStartSec = 900;
            };

            daemon = image: dependencies: {
              autoStart = true;
              unitConfig = {
                Requires = dependencies;
                After = dependencies;
              };
              serviceConfig = daemonService;
              containerConfig = {
                inherit image;
                pull = "missing";
                networks = [ network.ref ];
                memory = "500M";
              };
            };

            oneShot = image: dependencies: {
              autoStart = false;
              unitConfig = {
                Requires = dependencies;
                After = dependencies;
              };
              serviceConfig = oneShotService;
              containerConfig = {
                inherit image;
                pull = "missing";
                networks = [ network.ref ];
              };
            };

            generateScript = ''
              set -eu

              if [ ! -s .networkId ] || [ ! -s .networkSigningKey ]; then
                anyconf create-network
                sed -n 's/^networkId:[[:space:]]*//p' nodes.yml > .networkId
                sed -n 's/^[[:space:]]*signingKey:[[:space:]]*//p' account.yml > .networkSigningKey
              fi

              if [ ! -s account0.yml ] || [ ! -s account1.yml ] || [ ! -s account2.yml ] || [ ! -s account3.yml ]; then
                anyconf generate-nodes \
                  --t tree \
                  --t coordinator \
                  --t file \
                  --t consensus \
                  --addresses any-sync-node-1:1001 \
                  --addresses any-sync-coordinator:1004 \
                  --addresses any-sync-filenode:1005 \
                  --addresses any-sync-consensusnode:1006
              fi

              test -s .networkId
              test -s .networkSigningKey
              test -s nodes.yml
              chmod 0600 .networkId .networkSigningKey ./*.yml
            '';
          in
          {
            imports = [
              inputs.quadlet-nix.nixosModules.quadlet
              (credentialsModule instanceName pkgs)
            ];

            assertions = [
              {
                assertion = zerotierIP != null;
                message = "Anytype nodes host '${machine.name}' needs a published ZeroTier IP.";
              }
              {
                assertion = lib.length storageMachineNames == 1;
                message = ''
                  Anytype instance '${instanceName}' needs exactly one storage machine, but found:
                  ${builtins.concatStringsSep ", " storageMachineNames}
                '';
              }
              {
                assertion = settings.externalHosts != [ ];
                message = "Anytype nodes host '${machine.name}' needs at least one external host.";
              }
              {
                assertion = settings.externalHosts == lib.unique settings.externalHosts;
                message = "Anytype nodes host '${machine.name}' needs unique external hosts.";
              }
            ];

            systemd.tmpfiles.rules = [
              "d ${stateDir} 0755 root root -"
              "d ${stateDir}/identity 0700 root root -"
              "d ${stateDir}/config 0700 root root -"
              "d ${stateDir}/storage 0700 root root -"
              "d ${stateDir}/storage/any-sync-node-1 0700 root root -"
              "d ${stateDir}/storage/anyStorage 0700 root root -"
              "d ${stateDir}/storage/anyStorage/any-sync-node-1 0700 root root -"
              "d ${stateDir}/storage/networkStore 0700 root root -"
              "d ${stateDir}/storage/networkStore/any-sync-node-1 0700 root root -"
              "d ${stateDir}/storage/networkStore/any-sync-coordinator 0700 root root -"
              "d ${stateDir}/storage/networkStore/any-sync-filenode 0700 root root -"
              "d ${stateDir}/storage/networkStore/any-sync-consensusnode 0700 root root -"
            ];

            systemd.services.anytype-render-config = {
              description = "Render the Anytype network configuration";
              requires = [ "anytype-generate.service" ];
              after = [ "anytype-generate.service" ];
              environment = {
                ANYTYPE_STATE_DIR = stateDir;
                ANYTYPE_TEMPLATE_DIR = toString ./templates;
                ANYTYPE_EXTERNAL_HOSTS = builtins.toJSON settings.externalHosts;
                ANYTYPE_STORAGE_HOST = storageEndpointHost;
                ANYTYPE_FILE_DEFAULT_LIMIT = toString settings.fileDefaultLimit;
                ANYTYPE_SHARED_SPACES_LIMIT = toString settings.sharedSpacesLimit;
              };
              path = [
                pkgs.coreutils
                pkgs.findutils
                pkgs.gnugrep
                pkgs.perl
                pkgs.yq-go
              ];
              script = ''
                exec ${pkgs.bash}/bin/bash ${./render-config.sh}
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                UMask = "0077";
                RuntimeDirectory = "anytype";
                RuntimeDirectoryMode = "0700";
                LoadCredential = [
                  "minio-access-key:${credentialFile "minio-access-key"}"
                  "minio-secret-key:${credentialFile "minio-secret-key"}"
                  "mongo-password:${credentialFile "mongo-password"}"
                  "redis-password:${credentialFile "redis-password"}"
                ];
              };
            };

            virtualisation.quadlet = {
              enable = true;
              autoUpdate.enable = false;

              networks.anytype.networkConfig = {
                driver = "bridge";
                interfaceName = "anytype0";
                ipv6 = true;
              };

              containers = {
                anytype-generate = {
                  autoStart = false;
                  serviceConfig = oneShotService;
                  containerConfig = {
                    image = images.tools;
                    pull = "missing";
                    networks = [ "none" ];
                    entrypoint = [ "/bin/sh" ];
                    exec = [
                      "-ec"
                      generateScript
                    ];
                    workdir = "/work";
                    volumes = [ "${stateDir}/identity:/work:Z" ];
                  };
                };

                anytype-coordinator-bootstrap =
                  lib.recursiveUpdate
                    (oneShot images.coordinator [ renderService ])
                    {
                      serviceConfig = oneShotService // {
                        Restart = "on-failure";
                        RestartSec = "5s";
                      };
                      containerConfig = {
                        exec = [
                          "/bin/any-sync-confapply"
                          "-c"
                          "/etc/any-sync-coordinator/config.yml"
                          "-n"
                          "/etc/any-sync-coordinator/network.yml"
                          "-e"
                        ];
                        volumes = [
                          "${stateDir}/config/any-sync-coordinator:/etc/any-sync-coordinator:Z"
                        ];
                      };
                    };

                anytype-coordinator =
                  lib.recursiveUpdate
                    (daemon images.coordinator [
                      renderService
                      containers.anytype-coordinator-bootstrap.ref
                    ])
                    {
                      containerConfig = {
                        networkAliases = [ "any-sync-coordinator" ];
                        volumes = [
                          "${stateDir}/config/any-sync-coordinator:/etc/any-sync-coordinator:Z"
                          "${stateDir}/storage/networkStore/any-sync-coordinator:/networkStore:Z"
                        ];
                        publishPorts = [
                          "${publishHost}:1004:1004/tcp"
                          "${publishHost}:1014:1014/udp"
                          "127.0.0.1:1004:1004/tcp"
                          "127.0.0.1:1014:1014/udp"
                          "127.0.0.1:8004:8000"
                        ];
                      };
                    };

                anytype-node-1 =
                  lib.recursiveUpdate
                    (daemon images.node [
                      renderService
                      containers.anytype-coordinator.ref
                    ])
                    {
                      containerConfig = {
                        networkAliases = [ "any-sync-node-1" ];
                        volumes = [
                          "${stateDir}/config/any-sync-node-1:/etc/any-sync-node:Z"
                          "${stateDir}/config/.aws:/root/.aws:ro,Z"
                          "${stateDir}/storage/any-sync-node-1:/storage:Z"
                          "${stateDir}/storage/anyStorage/any-sync-node-1:/anyStorage:Z"
                          "${stateDir}/storage/networkStore/any-sync-node-1:/networkStore:Z"
                        ];
                        publishPorts = [
                          "${publishHost}:1001:1001/tcp"
                          "${publishHost}:1011:1011/udp"
                          "127.0.0.1:1001:1001/tcp"
                          "127.0.0.1:1011:1011/udp"
                          "127.0.0.1:8081:8080"
                          "127.0.0.1:8001:8000"
                        ];
                      };
                    };

                anytype-filenode =
                  lib.recursiveUpdate
                    (daemon images.filenode [
                      renderService
                      containers.anytype-coordinator.ref
                    ])
                    {
                      containerConfig = {
                        networkAliases = [ "any-sync-filenode" ];
                        volumes = [
                          "${stateDir}/config/any-sync-filenode:/etc/any-sync-filenode:Z"
                          "${stateDir}/config/.aws:/root/.aws:ro,Z"
                          "${stateDir}/storage/networkStore/any-sync-filenode:/networkStore:Z"
                        ];
                        publishPorts = [
                          "${publishHost}:1005:1005/tcp"
                          "${publishHost}:1015:1015/udp"
                          "127.0.0.1:1005:1005/tcp"
                          "127.0.0.1:1015:1015/udp"
                          "127.0.0.1:8005:8000"
                        ];
                      };
                    };

                anytype-consensusnode =
                  lib.recursiveUpdate
                    (daemon images.consensus [
                      renderService
                      containers.anytype-coordinator.ref
                    ])
                    {
                      containerConfig = {
                        networkAliases = [ "any-sync-consensusnode" ];
                        volumes = [
                          "${stateDir}/config/any-sync-consensusnode:/etc/any-sync-consensusnode:Z"
                          "${stateDir}/storage/networkStore/any-sync-consensusnode:/networkStore:Z"
                        ];
                        publishPorts = [
                          "${publishHost}:1006:1006/tcp"
                          "${publishHost}:1016:1016/udp"
                          "127.0.0.1:1006:1006/tcp"
                          "127.0.0.1:1016:1016/udp"
                          "127.0.0.1:8006:8000"
                        ];
                      };
                    };
              };
            };
          };
      };
  };
}
