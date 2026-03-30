{
  description = "Max Clan config (clean repo, Clan-native structure)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs@{ self, nixpkgs, clan-core, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      clanConfig = import ./clan.nix { inherit inputs self; };
      clan = clan-core.lib.clan ({
        inherit self;
        specialArgs = { inherit inputs self; };
      } // clanConfig);
    in {
      nixosConfigurations = clan.config.nixosConfigurations // {
        bootstrap-installer = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = [ ./installers/bootstrap-installer.nix ];
        };
      };
      inherit (clan.config) nixosModules clanInternals;
      clan = clan.config;

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
          if system == "x86_64-linux" then {
            bootstrap-installer-iso = self.nixosConfigurations.bootstrap-installer.config.system.build.isoImage;
          } else {
            default = pkgs.emptyFile;
          });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          bootstrap = pkgs.mkShell {
            packages = with pkgs; [
              clan-core.packages.${system}.clan-cli
              git
              age
              sops
              just
              age-plugin-fido2-hmac
              fido2-manage
            ];
          };
          default = self.devShells.${system}.bootstrap;
        });
    };
}
