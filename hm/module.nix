# home-manager 모듈: programs.wiku
#
#   programs.wiku = {
#     enable = true;
#     wines.miku = inputs.winemiku.packages.x86_64-linux.default;
#     prefixes.kakao.wine = "miku";
#     prefixes.line = { wine = "miku"; locale = "ja_JP.UTF-8"; };
#     defaultPrefix = "kakao";
#   };
#
# 여기서 선언한 prefix 외에 `wiku add` 로 만든 prefix 는 ~/.config/wiku/prefixes.json 에 저장된다
# (wine 은 여기 wines 에 등록한 것만 고를 수 있다).
wikuLib:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.wiku;
  inherit (lib) mkOption mkEnableOption mkIf types;
  reserved = [ "list" "wines" "add" "set" "rm" "help" ];

  prefixModule = { name, ... }: {
    options = {
      wine = mkOption {
        type = types.str;
        description = "쓸 Wine 변형 (programs.wiku.wines 의 이름)";
      };
      locale = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "ko_KR.UTF-8";
        description = "LANG/LC_ALL. null 이면 변형의 기본값";
      };
      wayland = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Wayland 전용 (DISPLAY 제거 + Graphics=wayland). null 이면 변형의 기본값";
      };
      dxvk = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "변형의 DXVK 를 prefix 에 설치. null 이면 변형의 기본값";
      };
      fileAssoc = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Wine 파일 연결(이 prefix 에 설치한 앱으로 파일 열기) 도 앱 메뉴와 함께 만들기
          (~/.local/share/applications/wiku/<이름>/). null 이면 변형의 기본값 (wiku 기본: 끔)
        '';
      };
      env = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "추가 환경 변수";
      };
      path = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "prefix 경로 (절대 경로). null 이면 ~/.local/share/wiku/<이름>";
      };
    };
  };
in
{
  options.programs.wiku = {
    enable = mkEnableOption "wiku (여러 Wine 변형과 prefix 관리)";

    wines = mkOption {
      type = types.attrsOf types.package;
      default = { };
      description = "쓸 수 있는 Wine 변형 (wiku.lib.mkWine 으로 만든 패키지)";
    };

    prefixes = mkOption {
      type = types.attrsOf (types.submodule prefixModule);
      default = { };
      description = "선언한 prefix";
    };

    defaultPrefix = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "이름 없이 `wiku app.exe` 할 때의 prefix. null 이면 prefix 가 하나일 때 그것";
    };

    package = mkOption {
      type = types.package;
      readOnly = true;
      description = "설정이 들어간 wiku 패키지";
    };
  };

  config = mkIf cfg.enable {
    assertions =
      lib.mapAttrsToList
        (n: p: {
          assertion = cfg.wines ? ${p.wine};
          message = "programs.wiku.prefixes.${n}.wine = \"${p.wine}\" 가 programs.wiku.wines 에 없음";
        })
        cfg.prefixes
      ++ lib.mapAttrsToList
        (n: _: {
          assertion = builtins.match "[A-Za-z0-9._][A-Za-z0-9._-]*" n != null && !(lib.elem n reserved);
          message = "programs.wiku.prefixes.${n}: 이름은 영문·숫자·._- 만, ${toString reserved} 는 안 됨";
        })
        cfg.prefixes
      ++ lib.mapAttrsToList
        (n: w: {
          assertion = w ? wiku;
          message = "programs.wiku.wines.${n} 는 wiku.lib.mkWine 으로 만든 패키지가 아님";
        })
        cfg.wines
      ++ [{
        assertion = cfg.defaultPrefix == null || cfg.prefixes ? ${cfg.defaultPrefix};
        message = "programs.wiku.defaultPrefix = \"${toString cfg.defaultPrefix}\" 가 prefixes 에 없음";
      }];

    programs.wiku.package = wikuLib.mkWiku {
      inherit pkgs;
      inherit (cfg) wines;
      prefixes = lib.mapAttrs (_: p: p) cfg.prefixes;
      default =
        if cfg.defaultPrefix != null then cfg.defaultPrefix
        else if lib.length (lib.attrNames cfg.prefixes) == 1 then lib.head (lib.attrNames cfg.prefixes)
        else null;
      # 바로가기(.desktop)는 PATH 의 wiku 를 부른다 (store 경로를 박으면 rebuild 후 낡은 경로가 남는다)
      launcher = "wiku";
    };

    home.packages = [ cfg.package ];
  };
}
