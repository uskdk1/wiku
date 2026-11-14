{ lib }:
rec {
  # dir 안의 *.patch 파일을 이름순으로 (dir 이 없으면 빈 목록)
  patchesIn = dir:
    if !builtins.pathExists dir then [ ]
    else
      let entries = builtins.readDir dir;
      in map (f: dir + "/${f}") (lib.sort lib.lessThan
        (lib.filter (f: entries.${f} == "regular" && lib.hasSuffix ".patch" f)
          (builtins.attrNames entries)));

  # prefix 목록 -> wiku 명령 패키지 (설정 JSON 을 store 에 박는다)
  mkWiku = import ./mkWiku.nix { inherit lib; };

  # Wine 변형 하나 -> 그 변형만 쓰는 wiku 패키지 (passthru.wiku = 변형 정보)
  mkWine = import ./mkWine.nix { inherit lib mkWiku; };
}
