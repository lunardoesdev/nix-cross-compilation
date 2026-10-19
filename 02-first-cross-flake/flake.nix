{
  description = "Chapter 02 — your first cross flake: two C libraries for bare-metal ARM";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      # =======================================================================
      # 1. Which machines.
      # =======================================================================
      # Same two declarations as chapter 01; see that chapter for what every
      # field means.
      localSystem = "x86_64-linux";
      crossSystem = {
        config = "arm-none-eabi";  # ARM CPU, no OS, EABI ABI
        libc = "newlib";           # the C library a bare-metal target links
      };

      buildPlatform  = nixpkgs.lib.systems.elaborate localSystem;
      targetPlatform = nixpkgs.lib.systems.elaborate crossSystem;

      # The build machine's package set ...
      nativePkgs = import nixpkgs { inherit localSystem; };
      # ... and the target's.  `buildPackages.*` are the cross tools.
      targetPkgs = import nixpkgs { inherit localSystem crossSystem; };

      # =======================================================================
      # 2. The cross toolchain, assembled as a stdenv.
      # =======================================================================
      stdenv = nativePkgs.stdenv.override {
        inherit buildPlatform;
        hostPlatform = targetPlatform;
        targetPlatform = targetPlatform;
        cc = targetPkgs.buildPackages.gcc;
        hasCC = true;
        extraBuildInputs = [ ];
        overrides = _: _: { };
        allowedRequisites = null;
      };

      # =======================================================================
      # 3. libadd — the library everything else depends on.
      # =======================================================================
      libadd = stdenv.mkDerivation {
        pname = "libadd";
        version = "1.0.0";
        src = ./src;

        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild
          $CC -Os -c add.c -o add.o
          $AR rcs libadd.a add.o
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/include
          cp libadd.a $out/lib/
          cp add.h    $out/include/
          runHook postInstall
        '';

        meta.description = "add(a, b) for arm-none-eabi";
      };

      # =======================================================================
      # 4. libmul — a library that USES libadd.
      # =======================================================================
      # This is the important part of the chapter.  `mul.c` does
      # `#include "add.h"`, but the build script below contains no `-I`
      # pointing at libadd.  It does not need one:
      #
      #   buildInputs = [ libadd ];
      #
      # Nix puts libadd's store path into the build environment, and the
      # cc-wrapper's setup hook turns every dependency that has an `include/`
      # directory into `-isystem <dep>/include`.  Dependencies are passed the
      # exact same way here as in any ordinary nixpkgs package.
      #
      # `propagatedBuildInputs` additionally forwards libadd to anything that
      # consumes libmul: a package that links libmul usually needs libadd's
      # headers and archive too.  (libmul.a contains an *undefined reference*
      # to add(), so the final link needs both archives.)
      libmul = stdenv.mkDerivation {
        pname = "libmul";
        version = "1.0.0";
        src = ./src;

        buildInputs = [ libadd ];
        propagatedBuildInputs = [ libadd ];

        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild
          $CC -Os -c mul.c -o mul.o
          $AR rcs libmul.a mul.o
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/include
          cp libmul.a $out/lib/
          cp mul.h    $out/include/
          runHook postInstall
        '';

        meta.description = "mul(a, b) for arm-none-eabi, built on top of libadd";
      };
    in
    {
      packages.${localSystem} = {
        inherit libadd libmul;
        default = libmul;
      };

      platforms = {
        build = buildPlatform.system;
        target = targetPlatform.config;
      };

      # Everything the chapter used, handy for `nix repl` or `nix eval`:
      #   nix eval --raw .#env.stdenv.cc.name
      #   nix eval --raw .#env.binutils.name
      #   nix eval --raw .#env.libc.name
      #   nix eval --raw .#env.targetPlatform.config
      env = {
        inherit buildPlatform targetPlatform nativePkgs targetPkgs stdenv;
        cc = targetPkgs.buildPackages.gcc;
        binutils = targetPkgs.buildPackages.binutils;
        libc = targetPkgs.newlib;
      };
    };
}
