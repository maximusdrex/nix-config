{
  description = "NixOS configuration flake for max's devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: {
    nixosConfigurations = {
      # Each system needs a configuration here

      max-xps-modal = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Import the host module
          ./hosts/xps

          # Import the home-manager module
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.max = import ./common/desktop/home.nix;
          }
        ];
      };

      max-hetzner-nix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Import the host module
          ./hosts/hetzner

          # Import the home-manager module
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.max = import ./common/server/home.nix;
          }
        ];
      };

      max-richard-nix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Import the host module
          ./hosts/richard

          # Import the home-manager module
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.max = import ./common/server/home.nix;
          }
        ];
      };

    };
  };
}
