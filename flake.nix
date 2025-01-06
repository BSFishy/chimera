{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages = {
          default = pkgs.stdenv.mkDerivation {
            pname = "chimera";
            version = "0.1.0";
            src = ./.;

            nativeBuildInputs = [
              pkgs.zig.hook
            ];

            buildInputs = [
              (pkgs.callPackage ./pkgs/lxc/lxc.nix { })
            ];
          };
        };

        devShells = {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.just
              pkgs.zig
              pkgs.zls
              (pkgs.callPackage ./pkgs/lxc/lxc.nix { })
            ];
          };
        };
      }
    );
}
