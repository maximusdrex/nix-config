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

    home-site = {
      url = "git+ssh://git@github.com/maximusdrex/home-site.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs@{ self, clan-core, ... }:
    let
      clanConfig = import ./clan.nix { inherit inputs self; };
      clan = clan-core.lib.clan ({
        inherit self;
        specialArgs = { inherit inputs self; };
      } // clanConfig);
    in {
      inherit (clan.config) nixosConfigurations nixosModules clanInternals;
      clan = clan.config;
    };
}
