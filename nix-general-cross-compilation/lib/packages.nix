# -----------------------------------------------------------------------------
# Every package for every target.
#
# The same four recipes (libadd, libmul, uselib2, sdl3-game) are instantiated
# once per target package set.  Nothing about the recipes changes between
# targets: the target set supplies the compiler, libc and SDL3.
# -----------------------------------------------------------------------------
{ pkgs }:
let
  lib = pkgs.lib;

  # `target` is the matrix row (see lib/targets.nix).  It is a complete nixpkgs
  # package set, so `target.callPackage` resolves dependencies for that
  # platform exactly like nixpkgs does for native packages.
  mkTarget = target:
    { sdl3
    , isEmscripten ? false
    , withCli ? true
    , emscripten ? null
    , cc ? null
    , ar ? null
    }:
    let
      shared = !isEmscripten;

      libadd = target.callPackage ../lib/c-lib.nix {
        pname = "libadd";
        version = "1.0.0";
        src = ../pkgs/libadd;
        sources = [ "add.c" ];
        headers = [ "add.h" ];
        libName = "add";
        inherit shared cc ar;
      };

      libmul = target.callPackage ../lib/c-lib.nix {
        pname = "libmul";
        version = "1.0.0";
        src = ../pkgs/libmul;
        sources = [ "mul.c" ];
        headers = [ "mul.h" ];
        libName = "mul";
        deps = [ libadd ];
        linkLibs = [ "add" ];
        inherit shared cc ar;
      };

      uselib2 = target.callPackage ../pkgs/uselib2 {
        inherit libadd libmul;
      };

      sdl3-game = target.callPackage ../pkgs/sdl3-game {
        src = ../pkgs/sdl3-game;
        inherit libadd libmul sdl3 isEmscripten emscripten;
      };
    in
    {
      inherit libadd libmul sdl3-game;
    } // lib.optionalAttrs withCli { inherit uselib2; };

  androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;

  # The full NDK.  `aarch64-android-prebuilt`'s bionic sysroot is deliberately
  # minimal; SDL3's Android video/audio backends need more (libandroid,
  # libOpenSLES, jni.h, ...), so SDL3 for Android is built with the NDK's own
  # CMake toolchain (see lib/sdl3-android.nix).
  androidNdkBundle = pkgs.buildPackages.buildPackages.androidenv.composeAndroidPackages {
    includeNDK = true;
    ndkVersion = "27.0.12077973";
  };

  androidSdl3 = pkgs.callPackage ./sdl3-android.nix {
    ndkBundle = androidNdkBundle.ndk-bundle;
  };

  linux = mkTarget (import ./targets.nix { inherit pkgs; }).linux {
    sdl3 = pkgs.sdl3;
  };

  windows = mkTarget (import ./targets.nix { inherit pkgs; }).windows {
    sdl3 = pkgs.pkgsCross.mingwW64.sdl3;
  };

  android = mkTarget androidPkgs {
    sdl3 = androidSdl3;
  };

  # SDL3 for WebAssembly is not packaged in nixpkgs; build it from the same
  # upstream source with emscripten.
  sdl3-emscripten = pkgs.callPackage ./sdl3-emscripten.nix { };

  emscripten = mkTarget (import ./targets.nix { inherit pkgs; }).emscripten {
    sdl3 = sdl3-emscripten;
    isEmscripten = true;
    withCli = false;
    emscripten = pkgs.emscripten;
    cc = "${pkgs.emscripten}/bin/emcc";
    ar = "${pkgs.emscripten}/bin/emar";
  };

  # Prefix every attribute with its target so the flake outputs are flat:
  # `linux-libadd`, `windows-sdl3-game`, `android-uselib2`, ...
  prefix = name: lib.mapAttrs' (k: v: lib.nameValuePair "${name}-${k}" v);

  # ---------------------------------------------------------------------------
  # Portable FHS Linux bundles (see lib/sharun.nix).
  # ---------------------------------------------------------------------------
  sharun = import ./sharun.nix { inherit pkgs; };

  portableCli = sharun.mkPortable {
    name = "uselib2";
    app = linux.uselib2;
    # Native-only smoke test: run the bundle through its *bundled* loader with
    # a clean library path, proving it does not need /nix/store.
    checkCommand = ''
      output="$("$out/lib/ld-linux-x86-64.so.2" \
        --library-path "$out/lib" "$out/shared/bin/uselib2")"
      echo "$output"
      echo "$output" | grep -q 'mul(6, 7) = 42'
    '';
  };

  portableGame = sharun.mkPortable {
    name = "sdl3-game";
    app = linux.sdl3-game;
  };

  # ---------------------------------------------------------------------------
  # FHS-usable library bundle: static + shared + headers + pkg-config, with
  # `$ORIGIN` RUNPATHs, ready to drop into a normal distro (see lib/fhs-libs.nix).
  # ---------------------------------------------------------------------------
  fhsLibs = import ./fhs-libs.nix { inherit pkgs; };

  libsBundle = fhsLibs.mkFhsLibs {
    name = "cdemo";
    libs = [ linux.libadd linux.libmul ];
  };

  libsBundleTar = fhsLibs.mkLibsTarball {
    name = "cdemo-libs";
    dir = libsBundle;
  };
in
  prefix "linux" linux
  // prefix "windows" windows
  // prefix "android" android
  // prefix "emscripten" emscripten
  // {
    inherit (sharun) sharun;
    linux-libs = libsBundle;
    linux-libs-tar = libsBundleTar;
    linux-portable-uselib2 = portableCli;
    linux-portable-uselib2-tar = sharun.mkTarball {
      name = "uselib2";
      appdir = portableCli;
    };
    linux-portable-sdl3-game = portableGame;
    linux-portable-sdl3-game-tar = sharun.mkTarball {
      name = "sdl3-game";
      appdir = portableGame;
    };
    linux-portable-uselib2-appimage = sharun.mkAppImage {
      name = "uselib2";
      appdir = portableCli;
    };
    linux-portable-sdl3-game-appimage = sharun.mkAppImage {
      name = "sdl3-game";
      appdir = portableGame;
    };
  }
