# wine 목록 + prefix 목록 -> wiku 명령.
#
#   wines.<이름>    = 변형 (mkWine 결과 패키지 또는 그 passthru.wiku)
#   prefixes.<이름> = {           # 선언한 prefix (home.nix). wiku add 로 만든 것은 ~/.config/wiku 에
#     wine     = "<wines 의 이름>";
#     locale / wayland / dxvk / fileAssoc = 변형 defaults 덮어쓰기 (null 이면 기본값);
#     env      = 추가 환경 변수;
#     path     = prefix 경로 (기본: ~/.local/share/wiku/<이름>);
#     override = (개발용) 쓰기 가능한 runtime 에 반영할 빌드 결과 디렉터리;
#   };
#   default  = 기본 prefix 이름 (null 이면 ~/.config/wiku 의 기본값, 그것도 없으면 prefix 이름 필수)
#   launcher = 앱 바로가기(.desktop)가 부를 명령 (null 이면 이 패키지의 store 경로)
#
# 설정 JSON 은 store 에 박는다. prefix 의 토글(wayland, dxvk)을 명령으로 바꿔도 빌드가
# 필요 없게 wine 마다 토글 조합 4가지의 share 를 미리 만들어 둔다 (작은 링크 디렉터리).
# (fileAssoc 는 실행기가 앱 메뉴를 만들 때만 보므로 share 와 무관)
{ lib }:
{ pkgs
, wines
, prefixes ? { }
, default ? null
, launcher ? null
, name ? "wiku"
, passthru ? { }
}:
let
  bools = [ true false ];
  key = w: d: "${lib.boolToString w}-${lib.boolToString d}";

  wineEntry = n: pkg:
    let v = pkg.wiku or pkg;
    in {
      version = v.version;
      runtime = "${v.runtime}";
      defaults = v.defaults;
      env = v.env;
      # "<wayland>-<dxvk>" -> share
      shares = lib.listToAttrs (lib.concatMap
        (w: map (d: lib.nameValuePair (key w d) "${v.share { wayland = w; dxvk = d; }}") bools)
        bools);
    };

  prefixEntry = n: p:
    assert lib.assertMsg (wines ? ${p.wine}) "wiku: prefix '${n}' 의 wine '${p.wine}' 가 wines 에 없음";
    {
      inherit (p) wine;
      locale = p.locale or null;
      wayland = p.wayland or null;
      dxvk = p.dxvk or null;
      fileAssoc = p.fileAssoc or null;
      env = p.env or { };
      path = p.path or null;
      override = p.override or null;
    };

  # 실행기가 쓰는 명령들
  # (desktop-file-utils, shared-mime-info: 파일 연결을 만들 때 데이터베이스 갱신)
  path = lib.makeBinPath (with pkgs; [
    coreutils findutils gnugrep gnused gawk procps util-linux diffutils jq
    desktop-file-utils shared-mime-info
  ]);

  config = pkgs.writeText "wiku-config.json" (builtins.toJSON {
    inherit default;
    wines = lib.mapAttrs wineEntry wines;
    prefixes = lib.mapAttrs prefixEntry prefixes;
  });
in
assert lib.assertMsg (default == null || prefixes ? ${default})
  "wiku: 기본 prefix '${toString default}' 가 prefixes 에 없음";
pkgs.runCommand name
{
  nativeBuildInputs = [ pkgs.makeWrapper ];
  meta.mainProgram = "wiku";
  # config: 설정 JSON, path: 실행기용 PATH (libexec/wiku 를 다른 설정으로 직접 부를 때)
  passthru = passthru // { inherit config path; };
} ''
  install -Dm755 ${../bin/wiku} $out/libexec/wiku
  patchShebangs $out/libexec/wiku
  makeWrapper $out/libexec/wiku $out/bin/wiku \
    --prefix PATH : ${path} \
    --set WIKU_CONFIG ${config} \
    --set WIKU_SELF ${if launcher == null then "$out/bin/wiku" else lib.escapeShellArg launcher}
''
