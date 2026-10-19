{
  description = "Chapter 09 — replacing libc: hosted (glibc) vs freestanding, and the embedded libc family";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # =======================================================================
      # What libc is
      # =======================================================================
      # `libc` is just a package that must provide:
      #
      #   $out/include/   the headers
      #   $out/lib/       crt1.o, libc.a (and/or libc.so)
      #
      # The compiler wrapper turns it into its flag files:
      #
      #   libc-cflags       -> -idirafter <libc>/<target>/include
      #   libc-crt1-cflags  -> -B <libc>/<target>/lib
      #   libc-ldflags      -> linker flags for the C library
      #
      # `libc = null` means "freestanding": none of those flags are added.
      #
      # NOTE ON COST.  On a CROSS target, `crossSystem.libc` selects which libc
      # the gcc cross compiler is built against.  Changing it therefore makes
      # Nix build a *matching gcc* (and the libc) from source the first time,
      # which is slow.  That is why this chapter demonstrates the substitution
      # on the NATIVE toolchain, where it is cheap, and only tabulates the
      # embedded options.  (See chapter 21 for picking targets that have cached
      # toolchains.)

      # =======================================================================
      # 1. Two native toolchains that differ only in libc.
      # =======================================================================
      mkToolchain = libc:
        let
          # binutils and cc MUST agree on libc (cc-wrapper asserts it).
          bintools = pkgs.wrapBintoolsWith {
            bintools = pkgs.binutils-unwrapped;
            inherit libc;
          };
          cc = pkgs.wrapCCWith {
            cc = pkgs.gcc-unwrapped;
            bintools = bintools;
            inherit libc;
          };
          stdenv = pkgs.stdenv.override {
            buildPlatform  = pkgs.stdenv.buildPlatform;
            hostPlatform   = pkgs.stdenv.hostPlatform;
            targetPlatform = pkgs.stdenv.targetPlatform;
            inherit cc;
            hasCC = true;
            extraBuildInputs = [ ];
            overrides = _: _: { };
            allowedRequisites = null;
          };
        in
        { inherit stdenv cc bintools libc; };

      # glibc: a normal hosted Linux target (printf, files, sockets, ...).
      hosted = mkToolchain pkgs.glibc;

      # null: freestanding -- no C library at all.  Only pure computation works.
      freestanding = mkToolchain null;

      # =======================================================================
      # 2. A hosted program (needs libc: it calls printf).
      # =======================================================================
      hello = hosted.stdenv.mkDerivation {
        pname = "hello-hosted";
        version = "1.0.0";
        src = ./src;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC add.c main.c -o hello
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp hello $out/bin/
          runHook postInstall
        '';
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          output="$(./hello)"; echo "$output"
          echo "$output" | grep -q 'add(6, 7) = 13'
          runHook postCheck
        '';
      };

      # =======================================================================
      # 3. A freestanding object (cannot call libc at all).
      # =======================================================================
      libadd = freestanding.stdenv.mkDerivation {
        pname = "libadd-freestanding";
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
      };
    in
    {
      packages.${system} = {
        inherit hello libadd;
        default = hello;
      };

      # Compare the two wrappers' flag files:
      #   cat "$(nix eval --raw .#toolchains.hosted.cc)/nix-support/libc-cflags"
      #   cat "$(nix eval --raw .#toolchains.freestanding.cc)/nix-support/libc-cflags"
      toolchains = { inherit hosted freestanding; };
    };
}
