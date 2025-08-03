{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default = 
      let
        pkgs = import nixpkgs { system = "x86_64-linux"; };
      in
        pkgs.callPackage ./default.nix { };
  };
}
