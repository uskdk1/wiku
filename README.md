# Wiku

여러가지 Wine 변형들을 Nix로 관리하는 도구.

- **변형(wine)**: 패치셋 저장소가 `wiku.lib.mkWine`으로 만든다 (패치된 모듈만 빌드, DXVK, prefix에 넣을 레지스트리·폰트).
- **prefix**: 어떤 변형을 쓸지 prefix마다 정한다. home.nix에 선언하거나 `wiku add`로 추가.
- **실행**: `wiku <prefix> app.exe` 하나로. prefix 생성·템플릿·Wine 갱신은 알아서.

## 사용

```bash
wiku app.exe                     # 기본 prefix
wiku kakao app.exe               # kakao prefix
wiku kakao --reset [app.exe]     # 초기화
wiku kakao --kill                # 이 prefix의 Wine 종료
wiku kakao --menus               # 앱 메뉴 다시 만들기 (보통은 실행이 끝날 때 알아서)
wiku --kill-all                  # 설정된 Wine들로 뜬 모든 prefix 종료

wiku list                        # prefix 목록 (* 기본, home/user, ! 설정에 없는 데이터)
wiku wines                       # 변형 목록 (버전, 기본값, 쓰는 prefix)
wiku add game staging --wayland on --locale ja_JP.UTF-8 --env FOO=bar
wiku set game --dxvk off         # add로 만든 prefix만 (home.nix 것은 home.nix에서)
wiku rm game [-y]                # prefix 데이터·메뉴 항목 삭제 (add로 만든 것은 설정도)
```

| 위치 | 내용 |
|---|---|
| `$XDG_DATA_HOME/wiku/<이름>` | prefix (`path`로 바꿀 수 있음) |
| `$XDG_DATA_HOME/applications/wiku/<이름>/` | 이 prefix의 앱 메뉴 (`카카오톡 (kakao)`) |
| `$XDG_CACHE_HOME/wiku/templates/<key>` | 깨끗한 prefix 템플릿. Wine+설정이 같은 prefix끼리 공유, 안 쓰는 것은 자동 삭제 |
| `$XDG_CONFIG_HOME/wiku/prefixes.json` | `wiku add/set`으로 만든 prefix |

(XDG 변수가 없으면 `~/.local/share`, `~/.cache`, `~/.config`)

prefix 설정: `locale`, `wayland`(DISPLAY 제거 + Graphics=wayland), `dxvk`(변형의 DXVK 설치),
`fileAssoc`(이 prefix의 앱으로 파일 열기도 만들기, 기본은 끔), `env`, `path`.
지정하지 않으면 변형의 기본값.

### 앱 메뉴

Wine의 winemenubuilder는 모든 prefix의 바로가기를 같은 경로에 써서 서로 덮어쓰므로 꺼 둔다.
대신 wiku로 띄운 프로그램(설치기 등)이 끝나면 wiku가 prefix의 시작 메뉴 바로가기(.lnk)로
`applications/wiku/<이름>/`에 메뉴를 만든다: 이름에 `(prefix)`, 실행은 `env WINEPREFIX=… wiku …`.
지운 앱의 항목은 다음에 만들 때 사라지고, `wiku rm`·`--reset`은 이 디렉터리를 지운다.
변형에 따로 패치가 필요 없다.

## home-manager

```nix
# flake inputs: wiku.url = "github:uskdk1/wiku";  winemiku.url = "github:uskdk1/winemiku";
imports = [ inputs.wiku.homeManagerModules.default ];

programs.wiku = {
  enable = true;
  wines.miku = inputs.winemiku.packages.x86_64-linux.default;
  wines.staging = inputs.wiku.packages.x86_64-linux.staging;
  prefixes.kakao.wine = "miku";
  prefixes.test = { wine = "staging"; wayland = true; };
  defaultPrefix = "kakao";
};
```

`wiku add`로 고를 수 있는 wine은 여기 `wines`에 등록한 것뿐이다.

HM 없이: `nix run .#staging -- app.exe` (변형 하나, prefix 하나).

## 변형 만들기 (패치셋 저장소)

```nix
wiku.lib.mkWine {
  inherit pkgs;
  name = "miku";
  base = pkgs.wineWow64Packages.stagingFull;      # 기본값
  patches = wiku.lib.patchesIn ./patches;         # *.patch 이름순
  dxvkPatches = wiku.lib.patchesIn ./patches/dxvk;
  prefix.reg = ./prefix.reg;                      # regedit /S 로 적용 (wiku 토글이 그 다음)
  prefix.fonts = [ fontsDir otherFontsDir ];      # drive_c/windows/Fonts 에 링크 (이름 겹치면 빌드 오류)
  runtimeHook = "rm -f $out/share/wine/fonts/tahoma.ttf";   # runtime 을 만든 뒤
  env = { dxvk, ... }: { MY_VAR = "${dxvk}/x64"; };          # 실행 시 export
  defaults = { locale = "ko_KR.UTF-8"; wayland = true; dxvk = true; };
}
```

결과는 그대로 실행할 수 있는 wiku 패키지(prefix `<name>` 하나)이고, `passthru`에
`wiku`(변형 정보), `wine-full`, `modules`, `dxvk`, `runtime`이 있다.
