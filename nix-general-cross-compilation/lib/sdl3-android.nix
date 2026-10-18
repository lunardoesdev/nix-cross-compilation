# -----------------------------------------------------------------------------
# SDL3 built for Android (arm64-v8a) with the NDK's own CMake toolchain.
#
# nixpkgs' `aarch64-android-prebuilt` stdenv only ships a reduced bionic sysroot
# (no libandroid/libOpenSLES/jni.h), which is not enough for SDL3's Android
# video/audio backends.  The full NDK *is* available through Nix, so we build
# SDL3 with it directly: same upstream source, `ANDROID` properly detected, and
# a real `libSDL3.so` for `jniLibs/arm64-v8a`.
# -----------------------------------------------------------------------------
{ lib
, stdenvNoCC
, fetchFromGitHub
, cmake
, ninja
, python3
, ndkBundle
}:
let
  # ndkBundle points at the androidenv "ndk-bundle" root; the toolchain lives
  # one directory deeper.
  ndk = "${ndkBundle}/libexec/android-sdk/ndk-bundle";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "sdl3-android";
  version = "3.4.16";

  src = fetchFromGitHub {
    owner = "libsdl-org";
    repo = "SDL";
    tag = "release-${finalAttrs.version}";
    hash = "sha256-zSwjDbPkYYjm0yA05bq/0Dq+RU154J/gYOw8a2YmerA=";
  };

  nativeBuildInputs = [ cmake ninja python3 ];

  dontConfigure = true;
  # Keep the NDK-produced ELF untouched (no nixos RPath patching).
  dontFixup = true;
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR"

    cmake -S . -B build -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=${ndk}/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=arm64-v8a \
      -DANDROID_PLATFORM=android-35 \
      -DCMAKE_BUILD_TYPE=Release \
      -DSDL_SHARED=ON \
      -DSDL_STATIC=OFF \
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
    cp -a build/libSDL3.so* "$out/lib/"
    cp -r include/SDL3 "$out/include/"
    runHook postInstall
  '';

  meta = {
    description = "SDL3 built for Android arm64-v8a with the NDK toolchain";
    platforms = [ "x86_64-linux" ];
  };
})
