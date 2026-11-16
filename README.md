# wiku

여러 Wine 변형과 여러 prefix를 Nix로 관리하고, prefix마다 정해진 Wine으로 실행하는 도구.

- **변형(wine)**: 패치셋 저장소가 `wiku.lib.mkWine`으로 만든다. 패치가 건드리는 모듈만 빌드하고, DXVK와 prefix에 넣을 레지스트리·폰트를 함께 묶는다.
  예: [winemiku](https://github.com/uskdk1/winemiku).
- **prefix**: 어떤 변형을 쓸지 prefix마다 정한다. home.nix에 선언하거나 `wiku add`로 추가.
- **실행**: `wiku <prefix> app.exe` 하나로. prefix 생성·템플릿·Wine 갱신·앱 메뉴는 알아서.

Nix 전용이다 (x86_64-linux).

## 사용

```bash
wiku app.exe                     # 기본 prefix
wiku kakao app.exe               # kakao prefix
wiku kakao "C:\\...\\앱.lnk"     # 설치한 앱 (바로가기 .lnk 또는 .exe)
wiku kakao --reset [app.exe]     # 초기화 (+ 바로 실행)
wiku kakao --kill                # 이 prefix 의 Wine 프로세스 전부 종료 (트레이에 숨은 앱 포함)
wiku kakao --menus               # 앱 메뉴 다시 만들기 (보통은 실행이 끝날 때 알아서)
wiku --kill-all                  # 설정된 Wine 들로 뜬 모든 prefix 종료
WIKU_LANG=ja_JP.UTF-8 wiku ...   # 이번만 로캘 바꾸기

wiku list                        # prefix 목록 (* 기본, home/user, ! 설정에 없는 데이터)
wiku wines                       # 변형 목록 (버전, 기본값, 쓰는 prefix)
wiku add game staging --wayland on --locale ja_JP.UTF-8 --env FOO=bar
wiku set game --dxvk off         # add 로 만든 prefix 만 (home.nix 것은 home.nix 에서)
wiku rm game [-y]                # prefix 데이터·메뉴 항목 삭제 (add 로 만든 것은 설정도)
```

| 위치 | 내용 |
|---|---|
| `$XDG_DATA_HOME/wiku/<이름>` | prefix (`path`로 바꿀 수 있다) |
| `$XDG_DATA_HOME/applications/wiku/<이름>/` | 이 prefix의 앱 메뉴 (`카카오톡 (kakao)`) |
| `$XDG_CACHE_HOME/wiku/templates/<key>` | 깨끗한 prefix 템플릿. Wine+설정이 같은 prefix끼리 공유, 안 쓰는 것은 자동 삭제 |
| `$XDG_CONFIG_HOME/wiku/prefixes.json` | `wiku add/set`으로 만든 prefix |

(XDG 변수가 없으면 `~/.local/share`, `~/.cache`, `~/.config`)

### prefix 설정

| 설정 | 내용 |
|---|---|
| `wine` | 쓸 변형 |
| `locale` | `LANG`/`LC_ALL` |
| `wayland` | Wayland 전용: `DISPLAY` 제거 + 레지스트리 `Graphics=wayland` |
| `dxvk` | 변형의 DXVK를 prefix에 설치 (system32/syswow64 + DllOverrides) |
| `fileAssoc` | 이 prefix의 앱으로 파일 열기(Wine 파일 연결)도 만들기. 기본은 끔 |
| `env` | 추가 환경 변수 |
| `path` | prefix 경로 |

지정하지 않으면 변형의 기본값(`mkWine`의 `defaults`)이다.

### prefix 생성과 갱신

- prefix가 없으면 템플릿에서 reflink로 복사해서 거의 즉시 만든다. 템플릿이 없으면 한 번 만든다 (약 20초).
- Wine이 바뀌면 `wineboot -u`로 prefix를 갱신한다. Nix store는 mtime이 항상 1이라 Wine이 스스로 못 한다.
- 변형의 레지스트리(`prefix.reg`)를 먼저, wiku 토글(`wiku.reg`)을 그다음에 적용한다. 토글이 이긴다.
- 안전장치: wiku가 만든 prefix(`.wiku-prefix` 표시)만 지운다.

### 앱 메뉴

Wine의 winemenubuilder는 모든 prefix의 바로가기를 같은 경로에 써서 서로 덮어쓰므로 꺼 둔다.
대신 wiku로 띄운 프로그램(설치기 등)이 끝나면 prefix의 시작 메뉴 바로가기(.lnk)로 `applications/wiku/<이름>/`에 메뉴를 만든다.
이름에 `(prefix)`를 붙이고, 실행은 `env WINEPREFIX=… wiku …`.

- 설치기가 먼저 끝나고 자식 프로세스가 나중에 바로가기를 만드는 경우를 위해, 그 뒤에도 5초마다 바로가기 목록을 본다
  (그 prefix의 Wine이 모두 끝나거나 10분이 지나면 멈춤).
- 아이콘을 못 뽑은 항목이 있으면(exe를 바로가기보다 늦게 복사하는 설치기) 3번까지 다시 만든다.
- 지운 앱의 항목은 다음에 만들 때 사라진다. `wiku rm`·`--reset`은 이 디렉터리를 지운다.
- 변형에 따로 패치가 필요 없다.

## home-manager

```nix
# flake inputs: wiku.url = "github:uskdk1/wiku";  winemiku.url = "github:uskdk1/winemiku";
imports = [ inputs.wiku.homeManagerModules.default ];

programs.wiku = {
  enable = true;
  wines.miku = inputs.winemiku.packages.x86_64-linux.default;
  wines.staging = inputs.wiku.packages.x86_64-linux.staging;   # 패치 없는 nixpkgs wine-staging
  prefixes.kakao.wine = "miku";
  prefixes.test = { wine = "staging"; wayland = true; };
  defaultPrefix = "kakao";
};
```

`wiku add`로 고를 수 있는 wine은 여기 `wines`에 등록한 것뿐이다.
home-manager 없이 변형 하나·prefix 하나만 쓰려면 `nix run <변형 flake> -- app.exe` (변형 패키지가 그대로 wiku 실행기다).

## 변형 만들기 (패치셋 저장소)

wiku는 "어떻게"만 안다: 패치된 모듈만 빌드, runtime 오버레이, DXVK 빌드, prefix에 적용.
"무엇을"(패치, 레지스트리, 폰트, env)은 변형이 넘긴다.

```nix
wiku.lib.mkWine {
  inherit pkgs;
  name = "miku";
  base = pkgs.wineWow64Packages.stagingFull;      # 기본값. nixpkgs 캐시에 있는 것이면 패치된 모듈만 빌드
  patches = wiku.lib.patchesIn ./patches;         # *.patch 이름순
  dxvkPatches = wiku.lib.patchesIn ./patches/dxvk;
  dxvk = other.dxvk;                              # 또는 다른 변형의 DXVK 를 그대로 (dxvkPatches 무시)
  prefix.reg = ./prefix.reg;                      # regedit /S 로 적용 (wiku 토글이 그 다음)
  prefix.fonts = [ fontsDir otherFontsDir ];      # drive_c/windows/Fonts 에 링크 (등록은 reg 가)
  runtimeHook = "rm -f $out/share/wine/fonts/tahoma.ttf";   # runtime 을 만든 뒤 ($out = runtime)
  env = { dxvk, runtime }: { MY_VAR = "${dxvk.x64}"; };     # 실행 시 export (attrs 도 됨)
  defaults = { locale = "ko_KR.UTF-8"; wayland = true; dxvk = true; };
}
```

결과는 그대로 실행할 수 있는 wiku 패키지(prefix `<name>` 하나)이고 `passthru`에 다음이 있다.

| `passthru` | 내용 |
|---|---|
| `wiku` | 변형 정보 (HM 모듈이 읽는다) |
| `wine-full` | 패치된 Wine 전체 (약 1시간, 확인용) |
| `modules` | 패치가 건드리는 모듈만 빌드한 결과. `diff --git a/` 경로에서 `dlls/<이름>`, `programs/<이름>`, `server`를 뽑는다 |
| `runtime` | 실행용 Wine: base의 심볼릭 링크 복제본 + `modules` 덮어쓰기 (컴파일 없음) |
| `dxvk` | (패치된) DXVK. `x64/`, `x32/` |
| `config`, `path` | 실행기가 쓰는 설정 JSON과 PATH (패치셋 개발 셸용) |

runtime을 이렇게 만드는 이유: Wine은 `ntdll.so`의 실제 위치 기준으로 내장 DLL을 찾고 `WINEDLLPATH`로는 덮어쓸 수 없다.
그래서 실행파일과 `ntdll.so`만 복사하고, store 경로를 박은 `bin/wine` 래퍼는 `scripts/rewrap.py`로 다시 만든다.

### 패치셋 개발 셸

패치셋 저장소의 개발 셸은 prefix 준비를 wiku에 맡기고 wine은 직접 띄울 수 있다 (winemiku의 `scripts/dev.sh` 참고).

```bash
eval "$(wiku miku --env)" && "$WIKU_WINE" app.exe
```

`--env`는 prefix를 만들거나 갱신하고, `override`를 반영한 뒤, 실행 환경(`WIKU_WINE`, `WINEPREFIX`, 로캘, `DISPLAY` 제거, 변형 env)을 셸 코드로 출력한다.
앱 메뉴 갱신 같은 부가 동작은 하지 않는다.

개발 셸이 바꿔 쓰는 것:

| 환경 변수 / 설정 | 내용 |
|---|---|
| `WIKU_CONFIG` | 설정 JSON (`passthru.config`를 jq로 고쳐서 넘긴다) |
| `.wines.<이름>.runtime` | 쓰기 가능한 runtime 복제본 경로 |
| `.prefixes.<이름>.path`, `.override` | 개발 prefix 경로, `override/<경로>`를 runtime에 덮어쓸 디렉터리 |
| `WIKU_USER_CONFIG`, `WIKU_TEMPLATES` | 사용자 설정과 템플릿 위치 (개발용 것만 쓰게) |
| `WIKU_SELF` | 앱 메뉴 `Exec=`에 넣을 실행기 (기본 `wiku`) |

## CI

`.github/workflows/build.yml`은 패치셋 저장소가 부르는 재사용 워크플로다. flake 패키지를 빌드해서 cachix에 올린다.
cache.nixos.org에 이미 있는 경로(vanilla wine 등)는 올리지 않는다. PR(포크)에는 시크릿이 없으므로 빌드만 한다.

```yaml
jobs:
  build:
    uses: uskdk1/wiku/.github/workflows/build.yml@master
    with:
      cachix: winemiku
      packages: winemiku winemiku-unpatched wine-miku-modules
    secrets:
      CACHIX_AUTH_TOKEN: ${{ secrets.CACHIX_AUTH_TOKEN }}
```
