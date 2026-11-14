{
  description = "wiku - 여러 Wine 변형과 prefix 를 Nix 로 관리";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      wikuLib = import ./lib { inherit (nixpkgs) lib; };
    in
    {
      # mkWine, mkWiku, patchesIn (패치셋 저장소가 쓴다)
      lib = wikuLib;

      packages.${system} = rec {
        # 패치 없는 nixpkgs wine-staging (빌드 없이 캐시에서). 시험용·기본 변형
        staging = wikuLib.mkWine { inherit pkgs; name = "staging"; };
        default = staging;
      };

      # programs.wiku (여러 wine + 여러 prefix)
      homeManagerModules.default = import ./hm/module.nix wikuLib;
    };
}
