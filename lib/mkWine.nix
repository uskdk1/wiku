# Wine 변형 하나를 만든다.
#
# wiku 는 "어떻게" 만 안다: 패치된 모듈만 빌드, runtime 오버레이, DXVK 빌드, prefix 에 적용.
# "무엇을" (패치, 레지스트리 내용, 폰트, env) 은 변형이 넘긴다.
#
# 결과: 이 변형 하나(prefix 이름 = name)만 쓰는 wiku 패키지. nix run 으로 바로 쓸 수 있다.
#   passthru.wiku       변형 정보 (HM 모듈 / mkWiku 가 읽는다)
#   passthru.wine-full  패치된 Wine 전체 (약 1시간, 확인용)
#   passthru.modules    패치가 건드리는 모듈만 빌드한 결과 (patches 가 없으면 null)
#   passthru.dxvk       (패치된) DXVK, x64/ x32/ 에 DLL (passthru x64, x32 = 실제 경로)
{ lib, mkWiku }:
{ pkgs
, name
  # 바탕 Wine. nixpkgs 캐시에 있는 것이면 패치된 모듈만 빌드한다
, base ? pkgs.wineWow64Packages.stagingFull
, patches ? [ ]
, dxvkPatches ? [ ]
  # 이미 만든 DXVK 를 그대로 쓰기 (다른 변형의 passthru.dxvk 등. 주면 dxvkPatches 는 무시)
, dxvk ? null
  # prefix 에 넣을 것 (선택)
  #   reg   : regedit /S 로 적용할 .reg 파일 경로
  #   fonts : 디렉터리 (하나 또는 목록). 안의 파일을 drive_c/windows/Fonts 에 링크.
  #           등록(HKLM\...\Fonts)은 reg 가 한다 (Wine DirectWrite 는 등록된 폰트만 본다)
, prefix ? { }
  # runtime 을 만든 뒤 실행할 셸 코드 ($out = runtime). 예: 내장 폰트 빼기
, runtimeHook ? ""
  # 실행 시 export 할 환경 변수. attrs 또는 { dxvk, runtime }: attrs
  # (dxvk.x64 / dxvk.x32 = DXVK DLL 의 실제 디렉터리)
, env ? { }
  # prefix 설정 기본값 (prefix 마다 덮어쓸 수 있다)
, defaults ? { }
}@args:
let
  dxvkPkg = args.dxvk or null;
  wine-full =
    if patches == [ ] then base
    else base.overrideAttrs (o: {
      pname = "wine-${name}";
      patches = (o.patches or [ ]) ++ patches;
    });

  # 패치가 건드리는 모듈: "diff --git a/<경로>" 에서 dlls/<이름>, programs/<이름>, server
  patchedModules = lib.unique (lib.concatMap
    (p: lib.concatMap
      (l:
        let m = builtins.match "diff --git a/((dlls|programs)/[^/]+|server)/.*" l;
        in lib.optional (m != null) (builtins.head m))
      (lib.splitString "\n" (builtins.readFile p)))
    patches);

  # 패치된 모듈만 빌드 (같은 소스·패치·configure 에서 make <모듈>/all 만. 몇 분)
  # 결과: lib/wine/{x86_64,i386}-windows/*.dll|exe|drv, lib/wine/x86_64-unix/*.so, bin/wineserver
  modules =
    if patches == [ ] then null
    else wine-full.overrideAttrs (o: {
      pname = "wine-${name}-modules";
      buildPhase = ''
        runHook preBuild
        make -j$NIX_BUILD_CORES ${lib.concatMapStringsSep " " (m: "${m}/all") patchedModules}
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        for d in ${toString patchedModules}; do
          if [ "$d" = server ]; then
            install -Dm755 server/wineserver $out/bin/wineserver; continue
          fi
          top=''${d%%/*} name=''${d#*/}
          case "$name" in
            *.*) mod=$name ;;
            *) if [ "$top" = programs ]; then mod=$name.exe; else mod=$name.dll; fi ;;
          esac
          so=''${mod%.*}.so n=0
          for arch in x86_64-windows i386-windows; do
            if [ -f "$d/$arch/$mod" ]; then
              install -Dm644 "$d/$arch/$mod" "$out/lib/wine/$arch/$mod"; n=$((n + 1))
            fi
          done
          if [ -f "$d/$so" ]; then
            install -Dm755 "$d/$so" "$out/lib/wine/x86_64-unix/$so"; n=$((n + 1))
          fi
          [ $n -gt 0 ] || { echo "$d: 빌드 결과물이 없음" >&2; exit 1; }
        done
        runHook postInstall
      '';
      postInstall = "";
      doCheck = false;
      doInstallCheck = false;
    });

  # D3D8/9/10/11 -> Vulkan. x64/ x32/ 에 DLL
  patchDxvk = d:
    if dxvkPatches == [ ] then d
    else d.overrideAttrs (o: {
      pname = "dxvk-${name}";
      patches = (o.patches or [ ]) ++ dxvkPatches;
    });
  # passthru x64 / x32 = 링크가 아닌 실제 DLL 디렉터리 (env 에서 쓸 수 있게)
  dxvk =
    if dxvkPkg != null then dxvkPkg
    else
      let
        x64 = "${patchDxvk pkgs.dxvk.dxvk64}/bin";
        x32 = "${patchDxvk pkgs.dxvk.dxvk32}/bin";
      in
      pkgs.runCommand "dxvk-${name}-${pkgs.dxvk.version}" { passthru = { inherit x64 x32; }; } ''
        mkdir -p $out
        ln -s ${x64} $out/x64
        ln -s ${x32} $out/x32
      '';

  # 실행용 wine: 바탕 wine 의 심볼릭 링크 복제본 + 패치된 모듈 (컴파일 없음).
  # Wine 은 ntdll.so 의 실제 위치 기준으로 내장 DLL 을 찾고 WINEDLLPATH 로는 덮어쓸 수 없어서
  # 실행파일과 ntdll.so 는 복사하고, store 경로를 박은 bin/wine 래퍼는 rewrap.py 로 다시 만든다.
  # .wiku-wine: 이 runtime 의 Wine 빌드 (바뀌면 wiku 가 prefix 를 wineboot -u 로 갱신)
  runtime = pkgs.runCommand "wine-${name}-runtime"
    { nativeBuildInputs = [ pkgs.python3 ]; passthru = { inherit (base) version; }; } ''
    cp -rs ${base}/. $out && chmod -R u+w $out
    for f in bin/wine bin/.wine lib/wine/x86_64-unix/{wine,wine-preloader,ntdll.so}; do
      [ -e ${base}/$f ] || continue
      rm -f $out/$f; cp -L ${base}/$f $out/$f
    done
    python3 -I ${../scripts/rewrap.py} ${base} $out
    ${lib.optionalString (modules != null) ''
      (cd ${modules} && find . -type f) | while read -r f; do
        rm -f $out/$f; install -Dm755 ${modules}/$f $out/$f
      done
    ''}
    ${runtimeHook}
    echo ${base}${lib.optionalString (modules != null) " ${modules}"} > $out/.wiku-wine
  '';

  dxvkDlls = [ "d3d8" "d3d9" "d3d10core" "d3d11" "dxgi" ];
  fontDirs = lib.toList (prefix.fonts or [ ]);

  # prefix 설정(토글)에 따른 데이터 디렉터리
  #   wiku.reg    wiku 토글 (Graphics=wayland, DXVK override, winemenubuilder 옵션).
  #               변형의 prefix.reg 다음에 적용
  #   prefix.reg  변형이 준 레지스트리 (있으면)
  #   fonts/      변형이 준 폰트 디렉터리들의 파일 링크 (있으면. 이름이 겹치면 빌드 오류)
  #   dxvk/       DXVK DLL (dxvk 를 켰을 때만)
  share = s:
    let
      line = k: v: ''"${k}"=${v}'';
      wikuReg = pkgs.writeText "wiku.reg" (lib.concatStringsSep "\r\n" ([
        "REGEDIT4"
        ""
        ''[HKEY_CURRENT_USER\Software\Wine\Drivers]''
        (line "Graphics" (if s.wayland then ''"wayland"'' else "-"))
        ""
        ''[HKEY_CURRENT_USER\Software\Wine\DllOverrides]''
      ] ++ map (d: line d (if s.dxvk then ''"native,builtin"'' else "-")) dxvkDlls ++ [
        ""
        # 세션 시작마다 도는 winemenubuilder. 기본값 "-a -r" 의 -a 는 Wine 파일 연결
        # (~/.local/share/applications/wine-extension-*.desktop)을 만드는데, 파일 이름이 모든 prefix
        # 공통이라 마지막에 실행한 prefix 가 덮어쓴다 -> fileAssoc 를 켠 prefix 만 -a
        ''[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\RunServices]''
        (line "winemenubuilder"
          ''"C:\\windows\\system32\\winemenubuilder.exe ${if s.fileAssoc then "-a -r" else "-r"}"'')
        ""
      ]));
    in
    pkgs.runCommand "wiku-${name}-share${lib.optionalString s.wayland "-wayland"}${lib.optionalString s.dxvk "-dxvk"}${lib.optionalString s.fileAssoc "-assoc"}" { } ''
      mkdir -p $out
      cp ${wikuReg} $out/wiku.reg
      ${lib.optionalString (prefix ? reg) "ln -s ${prefix.reg} $out/prefix.reg"}
      ${lib.optionalString (fontDirs != [ ]) ''
        mkdir $out/fonts
        for d in ${lib.escapeShellArgs (map toString fontDirs)}; do
          for f in "$d"/*; do
            [ -f "$f" ] || continue
            [ ! -e "$out/fonts/''${f##*/}" ] || { echo "폰트 이름이 겹침: ''${f##*/} ($d)" >&2; exit 1; }
            ln -s "$f" "$out/fonts/''${f##*/}"
          done
        done
      ''}
      ${lib.optionalString s.dxvk "ln -s ${dxvk} $out/dxvk"}
    '';

  variant = {
    inherit name base wine-full modules dxvk runtime;
    # 설정 기본값: wiku 기본 <- 변형 defaults
    defaults = {
      locale = null; # null 이면 실행 환경의 LANG 그대로
      wayland = false;
      dxvk = true;
      fileAssoc = false; # Wine 파일 연결(.desktop) 만들기. prefix 끼리 덮어써서 기본은 끔
    } // defaults;
    env = if lib.isFunction env then env { inherit dxvk runtime; } else env;
    version = base.version;
    # { wayland, dxvk, fileAssoc } -> prefix 데이터. 이 변형의 pkgs 로 만든다 (CI 캐시와 같은 경로)
    inherit share;
  };
in
mkWiku {
  inherit pkgs;
  name = "wiku-${name}";
  wines.${name} = variant;
  prefixes.${name}.wine = name;
  default = name;
  passthru = { wiku = variant; inherit wine-full modules dxvk runtime; };
}
