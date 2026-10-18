# sdl3-game - SDL3 game built for native Linux, Windows, Android and Emscripten.
#
# SDL3 comes from the target package set for Linux/Windows/Android.  For
# Emscripten nixpkgs has no SDL3 package, so `sdl3` is our local
# `pkgs/sdl3-emscripten.nix` and we link it statically with emcc.
{ lib
, stdenv
, pname ? "sdl3-game"
, version ? "1.0.0"
, src
, libadd
, libmul
, sdl3
, emscripten ? null
, isEmscripten ? false
}:
let
  isWindows = stdenv.hostPlatform.isWindows;
  exeExt = if isWindows then ".exe" else "";
  canRun = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  includeFlags = "-I${libmul}/include -I${libadd}/include"
    + (if isEmscripten then " -I${sdl3}/include" else " -I${lib.getDev sdl3}/include");

  commonFlags = "-O2 -Wall -Wextra ${includeFlags} main.c";

  # Link SDL3 straight from its Nix outputs instead of pkg-config: that works
  # identically for native, mingw and Android cross builds.
  nativeBuildCommand = ''
    $CC ${commonFlags} \
      -L${libmul}/lib -lmul -L${libadd}/lib -ladd \
      -L${lib.getLib sdl3}/lib -lSDL3 \
      -o "sdl3-game${exeExt}"
  '';

  emscriptenCommand = ''
    ${emscripten}/bin/emcc ${commonFlags} \
      ${libmul}/lib/libmul.a ${libadd}/lib/libadd.a \
      ${sdl3}/lib/libSDL3.a \
      -o sdl3-game.html \
      -sALLOW_MEMORY_GROWTH=1 \
      -sEXIT_RUNTIME=1 \
      -sMIN_WEBGL_VERSION=2 \
      -sMAX_WEBGL_VERSION=2
  '';
in
stdenv.mkDerivation {
  inherit pname version src;

  # For the native targets the SDL3 dependency comes from the package set;
  # pkg-config is a build-time tool only.
  buildInputs = lib.optionals (!isEmscripten) [ sdl3 libmul libadd ];
  nativeBuildInputs = lib.optionals isEmscripten [ emscripten ];

  strictDeps = true;
  dontConfigure = true;
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild
    ${if isEmscripten then emscriptenCommand else nativeBuildCommand}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    ${if isEmscripten then ''
      cp sdl3-game.html sdl3-game.js sdl3-game.wasm "$out/bin/"
    '' else ''
      cp "sdl3-game${exeExt}" "$out/bin/"
    ''}
    runHook postInstall
  '';

  doCheck = canRun && !isEmscripten;
  checkPhase = ''
    runHook preCheck
    output="$(SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy \
      ./sdl3-game${exeExt} --frames 5)"
    echo "$output"
    echo "$output" | grep -q 'score = mul(3, 14) = 42'
    runHook postCheck
  '';

  meta = {
    description = "Tiny SDL3 game used to demonstrate cross-compilation";
    mainProgram = if isWindows then "sdl3-game.exe" else "sdl3-game";
    platforms = lib.platforms.all;
  };
}
