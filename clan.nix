{ inputs, ... }:
let
  stripTrailingNewline = value: builtins.replaceStrings [ "\n" ] [ "" ] value;
  zerotierIP = machine:
    stripTrailingNewline (
      builtins.readFile (./vars/per-machine + "/${machine}/zerotier/zerotier-ip/value")
    );
  internalZTDomain = "zt.maxschaefer.me";

  # The official CoreDNS service currently expects an IPv4 endpoint for the
  # DNS server itself, even if the records it serves are AAAA records.
  hetznerPublicIPv4 = "5.78.135.36";
in
{
  meta = {
    name = "max-clan";
    domain = "maxschaefer.me";
  };

  exportInterfaces.publicProxy = ./clanServices/edge-proxy/export-interface.nix;
  modules.edge-proxy = ./clanServices/edge-proxy;

  inventory.machines = {
    max-hetzner-nix = {
      deploy.targetHost = "max@maxschaefer.me";
      tags = [ "nixos" "server" "edge" "public" ];
    };

    max-richard-nix = {
      deploy.targetHost = "max@max-richard-nix.local";
      tags = [ "nixos" "server" "home-services" ];
    };

    max-openclaw-nix = {
      deploy.targetHost = "max@5.78.177.67";
      tags = [ "nixos" "server" "openclaw" ];
    };

    max-g14-nix = {
      tags = [ "nixos" "desktop" "laptop" ];
    };

    max-xps-modal = {
      tags = [ "nixos" "desktop" "laptop" ];
    };
  };

  # Baseline, clan-native services.
  inventory.instances = {
    sshd = {
      roles.server.tags.all = { };
      roles.server.settings.authorizedKeys = {
        "max-admin" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC/qDFl92Ao8C4LVIbBsZQmlTzXa8+/lglFfIpD7VKp7 max@max-g14-nix";
      };
    };

    user-root = {
      module.name = "users";
      roles.default.tags.all = { };
      roles.default.settings = {
        user = "root";
        prompt = true;
      };
    };

    user-max = {
      module.name = "users";
      roles.default.tags.all = { };
      roles.default.settings = {
        user = "max";
        prompt = true;
      };
    };

    packages-all = {
      module.name = "packages";
      roles.default.tags.all = { };
      roles.default.settings.packages = [
        "git" "vim" "wget" "curl" "jq" "htop" "fastfetch" "tree" "ripgrep"

        # Container Tools
        "dive" "podman-tui" "podman-compose" "runc" "conmon" "skopeo"

        # Dev
        "mtr" "iperf3" "dnsutils" "ldns" "aria2" "socat" "nmap" "ipcalc" "fd"
        "hugo" "glow" "wishlist" "go" "pkg-config" "pcsclite" "devcontainer" "wl-clipboard-rs"
        "btop" "iotop" "iftop" "strace" "ltrace" "lsof"
        "sysstat" "lm_sensors" "ethtool" "pciutils" "usbutils" "inetutils" "linuxConsoleTools"
        "gcc_multi" "cmake" "gnumake" "ninja" "just"
        "android-tools" 

        # Python
        "python3" "uv"

      ];
    };

    packages-server = {
      module.name = "packages";
      roles.default.tags.server = { };
      roles.default.settings.packages = [ "tmux" ];
    };

    packages-desktop = {
      module.name = "packages";
      roles.default.tags.desktop = { };
      roles.default.settings.packages = [
        "google-chrome" "vlc" "discord" "keepassxc" "rclone" "libreoffice-qt6-fresh"
        
        # Gaming
        "mangohud" "lutris" "bottles" "heroic"

        # Dev
        "jetbrains-toolbox" "jetbrains.clion" "jetbrains.pycharm"
        "distrobox" "distrobox-tui"
        "pulseview" "sigrok-cli"

        # Work
        "slack" "thunderbird" "gpu-screen-recorder-gtk"
        "qgroundcontrol" "stm32cubemx" "segger-jlink" "betaflight-configurator"

        # Customization
        "spicetify-cli"

        # Personal
        "spotify" "solaar" "gdrive" "cbonsai" "qalculate-qt" "nom" "codex" "claude-code"
      ];
    };

    zerotier = {
      roles.controller.machines."max-hetzner-nix" = { };
      roles.peer.tags.all = { };
    };

    coredns = {
      roles.server.machines."max-hetzner-nix".settings = {
        ip = hetznerPublicIPv4;
        tld = internalZTDomain;
      };

      roles.default.tags.all = { };

      roles.default.machines."max-hetzner-nix".settings = {
        ip = zerotierIP "max-hetzner-nix";
        services = [ "max-hetzner-nix" "monitoring" ];
      };

      roles.default.machines."max-richard-nix".settings = {
        ip = zerotierIP "max-richard-nix";
        services = [ "max-richard-nix" ];
      };

      roles.default.machines."max-openclaw-nix".settings = {
        ip = zerotierIP "max-openclaw-nix";
        services = [ "max-openclaw-nix" ];
      };

      roles.default.machines."max-g14-nix".settings = {
        ip = zerotierIP "max-g14-nix";
        services = [ "max-g14-nix" ];
      };

      roles.default.machines."max-xps-modal".settings = {
        ip = zerotierIP "max-xps-modal";
        services = [ "max-xps-modal" ];
      };
    };

    monitoring = {
      roles.client.tags.all = { };
      roles.client.settings = {
        useSSL = false;
      };

      roles.server.machines."max-hetzner-nix".settings = {
        host = "monitoring.${internalZTDomain}";
        grafana.enable = true;
      };
    };

    edge-proxy = {
      module = {
        input = "self";
        name = "edge-proxy";
      };

      roles.edge.machines."max-hetzner-nix".settings = {
        acmeEmail = "max@theschaefers.com";
      };

      roles.server.tags.server = { };

      roles.server.machines."max-richard-nix".settings.routes.home = {
        host = "home";
        port = 8123;
      };

      roles.server.machines."max-hetzner-nix".settings.routes.budget = {
        host = "budget";
        port = 5006;
      };

      roles.server.machines."max-hetzner-nix".settings.routes.monitoring-root = {
        host = "monitoring";
        path = "/";
        port = 80;
        proxyWebsockets = false;
        locationExtraConfig = ''
          return 302 /grafana/;
        '';
      };

      roles.server.machines."max-hetzner-nix".settings.routes.monitoring-grafana = {
        host = "monitoring";
        path = "/grafana/";
        port = 3000;
        proxyWebsockets = true;
      };

      roles.server.machines."max-openclaw-nix".settings.routes.openclaw = {
        host = "openclaw";
        port = 18789;
      };
    };
  };

  machines = {
    max-hetzner-nix = {
      nixpkgs.hostPlatform = "x86_64-linux";
      imports = [
        ./machines/max-hetzner-nix
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.max = import ./homes/max-hetzner-nix.nix;
        }
      ];
    };

    max-richard-nix = {
      nixpkgs.hostPlatform = "x86_64-linux";
      clan.core.deployment.requireExplicitUpdate = true;
      imports = [
        ./machines/max-richard-nix
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.max = import ./homes/max-richard-nix.nix;
        }
      ];
    };

    max-openclaw-nix = {
      nixpkgs.hostPlatform = "x86_64-linux";
      imports = [
        ./machines/max-openclaw-nix
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.sharedModules = [
            inputs.nix-openclaw.homeManagerModules.openclaw
          ];
          home-manager.users.max = import ./homes/max-openclaw-nix.nix;
        }
      ];
    };

    max-g14-nix = {
      nixpkgs.hostPlatform = "x86_64-linux";
      clan.core.deployment.requireExplicitUpdate = true;
      imports = [
        ./machines/max-g14-nix
        inputs.home-manager.nixosModules.home-manager
        inputs.nixos-hardware.nixosModules.asus-zephyrus-ga402x-nvidia
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.max = import ./homes/max-g14-nix.nix;
        }
      ];
    };

    max-xps-modal = {
      nixpkgs.hostPlatform = "x86_64-linux";
      clan.core.deployment.requireExplicitUpdate = true;
      imports = [
        ./machines/max-xps-modal
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.max = import ./homes/max-xps-modal.nix;
        }
      ];
    };
  };
}
