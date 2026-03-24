{ inputs, ... }:
{
  meta = {
    name = "max-clan";
    domain = "maxschaefer.me";
  };

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
      deploy.targetHost = "max@max-openclaw-nix.local";
      tags = [ "nixos" "server" "openclaw" ];
    };

    max-g14-nix = {
      deploy.targetHost = "max@max-g14-nix.local";
      tags = [ "nixos" "desktop" "laptop" ];
    };

    max-xps-modal = {
      deploy.targetHost = "max@max-xps-modal.local";
      tags = [ "nixos" "desktop" "laptop" ];
    };
  };

  # Baseline, clan-native services.
  inventory.instances = {
    sshd = {
      roles.server.tags.all = { };
      roles.server.settings.authorizedKeys = {
        # TODO: Replace before first deploy
        "max-admin" = "PASTE_YOUR_SSH_PUBLIC_KEY";
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
        "git" "vim" "wget" "curl" "jq" "htop" "fastfetch" "tree"
      ];
    };

    packages-server = {
      module.name = "packages";
      roles.default.tags.server = { };
      roles.default.settings.packages = [ "tmux" "ripgrep" ];
    };

    packages-desktop = {
      module.name = "packages";
      roles.default.tags.desktop = { };
      roles.default.settings.packages = [
        "vlc" "discord" "keepassxc" "rclone" "libreoffice-qt6-fresh"
        "pulseview" "sigrok-cli" "mangohud" "lutris" "bottles" "heroic"
      ];
    };

    zerotier = {
      roles.controller.machines."max-hetzner-nix" = { };
      roles.peer.tags.all = { };
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
