{
  description = "Chapter 01 — what cross-compilation is: build/host/target and the four toolchain parts";

  # Pin nixpkgs so the guide is reproducible.  Every chapter pins the same
  # revision, so the toolchains are shared and only downloaded once.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      # =======================================================================
      # 1. The machine the build runs on.
      # =======================================================================
      # A plain nixpkgs system string.  Everything below is evaluated from a
      # shell running on this machine.
      localSystem = "x86_64-linux";

      # =======================================================================
      # 2. The machine the result runs on: the "cross system".
      # =======================================================================
      # This is the ONLY place the target is named.  Change `config` and the
      # whole chapter builds for a different CPU/OS.
      #
      # A `crossSystem` set is a GNU target triple split into fields:
      #   <cpu>-<vendor>-<os><abi>
      #     cpu    = arm        -> the processor family
      #     vendor = none       -> "no vendor"; also used for "bare metal"
      #     os     = (empty)    -> no operating system at all
      #     abi    = eabi       -> the Embeded Application Binary Interface
      # So "arm-none-eabi" means: ARM CPU, no OS, EABI.  Code for it runs on
      # microcontrollers, not on an operating system.
      crossSystem = {
        config = "arm-none-eabi";

        # The C library linked on the target.  Bare metal cannot use glibc
        # (which needs a kernel and the dynamic loader), so this is newlib.
        libc = "newlib";

        # Other fields exist (`gcc.arch`, `useLLVM`, ...).  Chapter 02 shows
        # how to use them; here the defaults are exactly what the prebuilt
        # toolchain in the binary cache was compiled with, so nothing is built
        # from source.
      };

      # =======================================================================
      # 3. The three platform descriptions nixpkgs reasons with.
      # =======================================================================
      # From GNU autotools:
      #   buildPlatform  - where the build executes
      #   hostPlatform   - where the produced packages run
      #   targetPlatform - what a produced *compiler* emits code for
      #
      # For an ordinary cross build, host == target: we run a compiler on
      # x86_64-linux that produces arm-none-eabi objects, and those objects
      # are "hosted" on arm-none-eabi.  The two only differ for a "Canadian
      # cross" (a compiler that runs on one machine and generates code for
      # another), which the guide does not need.
      #
      # `elaborate` expands a name (or the crossSystem set) into the full
      # machine record: parsed CPU, kernel, ABI, endianness, libc, and so on.
      buildPlatform  = nixpkgs.lib.systems.elaborate localSystem;
      targetPlatform = nixpkgs.lib.systems.elaborate crossSystem;

      # =======================================================================
      # 4. The two package sets.
      # =======================================================================
      # `nativePkgs` is x86_64-linux: it provides the *build* tools (bash,
      # make, the native stdenv we re-target below).
      nativePkgs = import nixpkgs { inherit localSystem; };

      # `targetPkgs` is nixpkgs built *for the target*.  Its
      # `buildPackages.<pkg>` attributes are the tools that run on the build
      # machine to produce target code -- exactly what a cross compiler and
      # cross binutils are.
      targetPkgs = import nixpkgs { inherit localSystem crossSystem; };

      # =======================================================================
      # 5. The four parts of a toolchain.
      # =======================================================================
      # A cross toolchain is just these four things.  Each is a package with a
      # small, documented interface; you can replace any one of them.

      # -- cc: the compiler driver --------------------------------------------
      # Interface: a package with an executable in $out/bin.  nixpkgs wraps it
      # so builds see `$CC`/`$CXX`; see chapter 03 for the exact mechanism.
      cc = targetPkgs.buildPackages.gcc;

      # -- binutils: assembler, linker, archiver, object tools ----------------
      # Interface: $out/bin/<targetPrefix>{ar,as,ld,nm,objcopy,ranlib,strip,...}
      # and a `targetPrefix` attribute ("arm-none-eabi-" here).
      binutils = targetPkgs.buildPackages.binutils;

      # -- libc: headers, start files, and the C library ----------------------
      # Interface: $out/include (headers) and $out/lib (crt1.o, libc.a, ...).
      # `null` would mean "freestanding" (no C library at all).
      libc = targetPkgs.newlib;

      # -- ... and the fourth part is not a package at all: the *platform
      #    descriptions* from section 3.  A toolchain is (cc, binutils, libc)
      #    plus "for which machine", which the stdenv carries.

      # =======================================================================
      # 6. The stdenv, built from those parts.
      # =======================================================================
      # We take the build machine's stdenv and replace exactly the parts that
      # decide "which toolchain, for which machine".  nixpkgs defines its own
      # cross stdenv the same way (pkgs/stdenv/cross/default.nix).
      stdenv = nativePkgs.stdenv.override {
        inherit buildPlatform;
        hostPlatform = targetPlatform;
        targetPlatform = targetPlatform;

        inherit cc;
        hasCC = true;

        # The native stdenv's build inputs and package overrides belong to the
        # build machine and must not leak into target packages.
        extraBuildInputs = [ ];
        overrides = _: _: { };

        # Inputs of this stdenv are target packages, so do not compare its
        # closure against the native one.
        allowedRequisites = null;
      };

      # =======================================================================
      # 7. A package built with that stdenv.
      # =======================================================================
      # Nothing below mentions "arm" or "newlib" again: the build script just
      # uses $CC and $AR.  Swapping the toolchain in section 5 is all it takes
      # to retarget it.
      libadd = stdenv.mkDerivation {
        pname = "libadd";
        version = "1.0.0";
        src = ./src;

        # We drive the compiler directly, so there is no configure step.
        dontConfigure = true;

        # The single-core rule: never fork multiple compiler jobs.
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild

          # $CC and $AR are provided by the stdenv's setup hooks.  They already
          # point at the arm-none-eabi tools; the flags (e.g. where newlib's
          # headers are) are injected by the cc-wrapper.  See chapter 03.
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

        meta = {
          description = "add(a, b) for arm-none-eabi, cross-compiled with Nix";
          platforms = nixpkgs.lib.platforms.all;
        };
      };
    in
    {
      # `nix build .#libadd` or `nix build` (the default).
      packages.${localSystem} = {
        inherit libadd;
        default = libadd;
      };

      # Plain strings so you can inspect the chapter's decisions, e.g.
      #   nix eval --raw .#platforms.target
      platforms = {
        build  = buildPlatform.system;            # x86_64-linux
        host   = targetPlatform.system;           # arm-none-eabi
        target = targetPlatform.config;           # arm-none-eabi
      };

      # The declaration itself, for `nix eval .#crossSystem.libc`.
      inherit crossSystem;

      # Reusable pieces (also handy for `nix repl`).
      inherit stdenv cc binutils libc;
    };
}
