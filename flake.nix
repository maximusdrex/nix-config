{
  description = "NixOS configuration flake for max's devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, home-manager, nixos-hardware, ... }@inputs: {
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

            home-manager.users.max = import ./hosts/xps/home.nix;
          }
        ];
      };

      max-g14-nix = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Import the host module
          ./hosts/g14

          # Import the home-manager module
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.max = import ./hosts/g14/home.nix;
          }
	  nixos-hardware.nixosModules.asus-zephyrus-ga402x-nvidia
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

            home-manager.users.max = import ./hosts/hetzner/home.nix;
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

            home-manager.users.max = import ./hosts/richard/home.nix;
          }
        ];
      };

    };
  };
}
