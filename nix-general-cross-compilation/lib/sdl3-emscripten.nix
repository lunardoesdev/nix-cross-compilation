# -----------------------------------------------------------------------------
# SDL3 built for Emscripten / WebAssembly.
#
# nixpkgs' `sdl3` package is only wired up for native Unix/Windows, so this is
# a small local derivation around the very same upstream source.  It uses
# emscripten's CMake toolchain (`emcmake`) and installs a static `libSDL3.a`
# plus the headers; `pkgs/sdl3-game` links that archive with `emcc`.
# -----------------------------------------------------------------------------
{ lib
, stdenv
, fetchFromGitHub
, emscripten
, cmake
, ninja
, python3
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "sdl3-emscripten";
  version = "3.4.16";

  src = fetchFromGitHub {
    owner = "libsdl-org";
    repo = "SDL";
    tag = "release-${finalAttrs.version}";
    hash = "sha256-zSwjDbPkYYjm0yA05bq/0Dq+RU154J/gYOw8a2YmerA=";
  };

  nativeBuildInputs = [ emscripten cmake ninja python3 ];

  dontConfigure = true;
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR"
    export EM_CACHE="$TMPDIR/emscripten-cache"

    ${emscripten}/bin/emcmake cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DSDL_SHARED=OFF \
      -DSDL_STATIC=ON \
      -DSDL_TESTS=OFF \
      -DSDL_INSTALL_TESTS=OFF \
      -DSDL_ALSA=OFF \
      -DSDL_DBUS=OFF \
      -DSDL_IBUS=OFF \
      -DSDL_JACK=OFF \
      -DSDL_KMSDRM=OFF \
      -DSDL_LIBUDEV=OFF \
      -DSDL_PIPEWIRE=OFF \
      -DSDL_PULSEAUDIO=OFF \
      -DSDL_SNDIO=OFF \
      -DSDL_WAYLAND=OFF \
      -DSDL_X11=OFF

    ninja -C build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/include"
    cp build/libSDL3.a "$out/lib/"
    cp -r include/SDL3 "$out/include/"
    runHook postInstall
  '';

  meta = {
    description = "SDL3 built for Emscripten (static)";
    platforms = [ "x86_64-linux" ];
  };
})
