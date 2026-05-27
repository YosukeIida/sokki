{
  description = "Dev shell (just)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # mkShellNoCC: C コンパイラ不要のシェル（Apple SDK 環境変数を汚染しない）
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.just
            ];
          };
        }
      );
    };
}
