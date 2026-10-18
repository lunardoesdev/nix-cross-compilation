{
  description = "Cross-compile two tiny C libraries for embedded ARM (bare metal) with Nix";

  inputs.nixpkgs.url = "nixpkgs";

  /*
    ============================================================================
    0. From the attributes below to $CC, $CXX and real compiler flags
    ============================================================================

    The attributes in this file look abstract; here is the concrete chain that
    turns them into the commands a build actually runs.

    1. `stdenv.mkDerivation` is a bash script.  Its environment is the stdenv
       derivation plus the setup hooks of all dependencies.  The stdenv itself
       puts the `cc` wrapper into every build's nativeBuildInputs
       (pkgs/stdenv/generic/default.nix: defaultNativeBuildInputs = ... ++
       optional hasCC cc), which is what makes $CC exist at all.

    2. `setup.sh` sources `nix-support/setup-hook` of every dependency.  The
       cc-wrapper's hook ends with:

           export NIX_CC=...-arm-none-eabi-gcc-wrapper-16.2.0
           export CC=arm-none-eabi-gcc
           export CXX=arm-none-eabi-g++

       The bintools wrapper's hook loops over ar/as/ld/nm/objcopy/objdump/
       readelf/ranlib/strip/strings/size/windres/rc and exports e.g.

           export AR=arm-none-eabi-ar
           export AS=arm-none-eabi-as
           export LD=arm-none-eabi-ld
           ...

       `CC` does NOT always mean GNU gcc -- it is just the conventional name
       of the "C compiler" variable, and its value is the driver family that
       was found in the `cc` package:

           gcc    -> CC=<prefix>gcc     CXX=<prefix>g++
           clang  -> CC=<prefix>clang   CXX=<prefix>clang++
           arocc  -> CC=<prefix>arocc
           other  -> default <prefix>cc, but no such binary is installed;
                     expose your driver as gcc/clang/arocc (see section 7)

       In this file: the ARM target yields CC=arm-none-eabi-gcc; the TCC
       example yields CC=gcc (we named the driver gcc).

       That is the whole magic: `cc` and `binutils` are just packages whose
       setup hooks export the variable names build systems already use.

       Two details are easy to miss:

       * `cc` is the WRAPPER package (`...-gcc-wrapper-16.2.0`), not the raw
         compiler (`...-arm-none-eabi-gcc-16.2.0`, recorded in the wrapper's
         nix-support/orig-cc).  The raw gcc package exports no CC at all --
         it only has bin/arm-none-eabi-gcc and passthru.isGNU = true.

       * `isGNU` / `isClang` do NOT choose the value of CC.  wrapCCWith
         (pkgs/top-level/all-packages.nix) reads them at *evaluation* time
         and passes them into the wrapper to select FLAGS (gcc-for-libs,
         response files, C++ stdlib, hardening), not the value of CC.  The
         value comes from the driver *filename* found in $ccPath
         (gcc/clang/arocc) -> named_cc -> setup-hook, as described above.

       Nix itself (the package manager) never reads isGNU/isClang and never
       sets CC: it evaluates nixpkgs and builds the wrapper.  The variable is
       exported at build time by bash, when setup.sh sources the hook
       (pkgs/stdenv/generic/setup.sh, _addToEnv):

           if [[ -f "$pkg/nix-support/setup-hook" ]]; then
               source "$pkg/nix-support/setup-hook"
           fi

       Literal source locations (pinned nixpkgs):

         pkgs/development/compilers/gcc/ng/common/default.nix
             :218  gcc = wrapCCWith { cc = gccPackages.gcc-unwrapped; ... }
                   (this is why `buildPackages.gcc` is the wrapper)
         pkgs/top-level/all-packages.nix
             wrapCCWith = ... callPackage ../build-support/cc-wrapper ...
         pkgs/build-support/cc-wrapper/default.nix
             :424  stdenvNoCC.mkDerivation { pname = "...-wrapper"; ... }
             :559  export named_cc=...            (installPhase)
             :564  ln -s ...gcc $out/bin/...cc
             :565  export named_cc=...gcc
             :636  setupHooks = [ ../setup-hooks/role.bash ]
                   ++ optional (cc.langC or true) ./setup-hook.sh
         pkgs/build-support/cc-wrapper/setup-hook.sh
             :119  export CC${role_post}=@named_cc@
         pkgs/stdenv/generic/setup.sh
             fixupPhase: substituteAllStream ... >> $out/nix-support/setup-hook
                         (replaces @named_cc@ with the exported named_cc)
             _addToEnv:  source "$pkg/nix-support/setup-hook"

    3. `$CC` is not the raw compiler.  It is
       `$ccWrapper/bin/arm-none-eabi-gcc`, a generated bash script.  The
       script sources `nix-support/add-flags.sh`, which prepends flags from
       files in `$ccWrapper/nix-support/`:

           cc-cflags          -> -B <gcc-lib>/arm-none-eabi/lib
           cc-cflags-before   -> -fno-omit-frame-pointer
           cc-ldflags         -> -L <gcc-lib>/arm-none-eabi/lib
           libc-cflags        -> -idirafter <newlib>/arm-none-eabi/include
                                 -idirafter <gcc>/.../include-fixed
           libc-crt1-cflags   -> -B <newlib>/arm-none-eabi/lib
           libc-ldflags       -> (linker flags for the C library)
           libcxx-cxxflags    -> (C++ standard library flags, if any)

       `add-hardening.sh` adds the flags selected by NIX_HARDENING_ENABLE
       (-fstack-clash-protection, -fzero-call-used-regs, -Wformat, ...), and
       `$NIX_CFLAGS_COMPILE`/`$NIX_LDFLAGS` add user and dependency flags.
       The script finally `exec`s the real compiler binary with all of them.

       Which files exist/filled depends on WHICH parts you chose:
         * the `libc` attribute  -> libc-cflags / libc-crt1-cflags /
                                    libc-ldflags (empty when libc = null)
         * the `binutils` attr   -> what $AR/$AS/$LD execute (the cc wrapper
                                    prepends the bintools wrapper to $PATH)
         * the `cc` attribute    -> what $CC/$CXX execute

    4. `targetPlatform.config` decides the `targetPrefix`: when
       targetPlatform != hostPlatform every tool and variable is named
       "arm-none-eabi-<tool>" and the wrapper adds the matching -B/-idirafter
       paths.  For a native build the prefix is empty (CC=gcc, AR=ar, ...).

    5. Every dependency in `buildInputs` that has an `include/` directory is
       turned into `-isystem <dep>/include` by the cc-wrapper's env hook, and
       one with a `lib/` directory into `-L <dep>/lib` by the bintools hook.
       That is why libmul needs no `-I` for libadd below.

    You can see all of it without trusting this comment:

        cc=$(nix eval --raw .#env.cc)
        ls "$cc/bin" "$cc/nix-support"
        cat "$cc/nix-support/libc-cflags" "$cc/nix-support/cc-cflags"
        cat "$cc/nix-support/setup-hook" | tail -30

    and the fully expanded command line, by building with NIX_DEBUG=1:

        nix build .#libmul --cores 1 --max-jobs 1 \
          --impure --expr '(builtins.getFlake (toString ./.)).packages.x86_64-linux.libmul.overrideAttrs { NIX_DEBUG = 1; }'
        nix log <the .drv printed above>
  */

  outputs = { self, nixpkgs }:
    let
      # =================================================================
      # 1. The two machines
      # =================================================================

      # The machine the build runs on.
      localSystem = "x86_64-linux";

      # The machine the result runs on.  This declaration is the whole
      # "cross system": everything below is derived from it.
      crossSystem = {
        # GNU target triple <cpu>-<vendor>-<os><abi>:
        #   arm   -> the CPU family
        #   none  -> no operating system at all, i.e. bare metal
        #   eabi  -> the (Embedded) application binary interface
        config = "arm-none-eabi";

        # The C library the target is linked against.  Bare-metal ARM uses
        # newlib; "newlib-nano" is the size-optimised variant, "picolibc"
        # is another.  To use your OWN libc package, see section 4.
        libc = "newlib";

        # Optional: pin code generation.  Left commented out on purpose,
        # because the default (no options) is exactly what the prebuilt
        # toolchain in the binary cache was compiled with, so builds start
        # immediately.  Uncommenting any of these forces Nix to build a
        # matching gcc/binutils from source the first time.
        #
        # gcc = {
        #   arch = "armv7m";       # instruction set: ARMv7-M (Cortex-M3/4/7)
        #   cpu  = "cortex-m4";    # exact core
        #   fpu  = "fpv4-sp-d16";  # single-precision FPU (Cortex-M4F)
        #   abi  = "eabi";         # soft-float ABI ("eabihf" = hard float)
        # };
        #
        # The same declaration also selects a different compiler if wanted:
        #   useLLVM  = true;   # use clang instead of gcc
        #   useZig   = true;   # use `zig cc`
        #   useArocc = true;   # use `arocc`
      };

      # =================================================================
      # 2. The two machines, parsed
      # =================================================================
      # `elaborate` expands a system string (or the `crossSystem` set above)
      # into the full machine description nixpkgs works with: parsed CPU,
      # kernel, ABI, endianness, libc, object-file extensions, and so on.
      # These are the `buildPlatform` / `hostPlatform` / `targetPlatform`
      # values (GNU autotools terminology):
      #
      #   buildPlatform  -- where the build executes
      #   hostPlatform   -- where the produced packages run
      #   targetPlatform -- what the produced compiler emits code for
      #
      # For an ordinary cross build host and target are the target machine.
      # (They only differ for a "Canadian cross": a compiler that runs on
      # one machine and generates code for another.)
      #
      # Anything nixpkgs knows can be written here directly.  For a machine
      # nixpkgs has no name for, elaborate a set with an explicit `parsed`
      # field (see lib/systems/parse.nix), e.g.
      #   targetPlatform = nixpkgs.lib.systems.elaborate {
      #     config = "mycpu-unknown-myos";
      #     parsed = { cpu = { name = "mycpu"; bits = 32; }; ... };
      #   };
      buildPlatform  = nixpkgs.lib.systems.elaborate localSystem;
      targetPlatform = nixpkgs.lib.systems.elaborate crossSystem;

      # =================================================================
      # 3. The two package sets
      # =================================================================
      # The build machine's packages: native tools, and the native stdenv
      # that we re-target below.
      nativePkgs = import nixpkgs { inherit localSystem; };

      # The target's packages: nixpkgs built for `targetPlatform`.
      # `buildPackages.<pkg>` is the package built to *run on the build
      # machine while producing target code* -- exactly what a cross
      # compiler and cross binutils are.
      targetPkgs = import nixpkgs { inherit localSystem crossSystem; };

      # =================================================================
      # 4. The toolchain: the four replaceable pieces
      # =================================================================
      # A cross toolchain is just four independent things.  Each one is
      # named here so you can substitute your own; the comments give the
      # interface nixpkgs expects from each.

      # -- cc: the compiler driver ------------------------------------
      # Expected: a package whose executable is in $out/bin.
      # nixpkgs' cc-wrapper recognises a driver named `gcc`, `clang` or
      # `arocc`; it renames/wraps it so the build sees it as $CC (and
      # exports $CXX, $CPP, ... appropriately).
      # Concretely, choosing this attribute decides what `$CC` executes and
      # what the wrapper's setup hook exports:
      #     CC=arm-none-eabi-gcc   CXX=arm-none-eabi-g++
      # To plug in your own: see section 7 (TCC).
      cc = targetPkgs.buildPackages.gcc;

      # -- binutils: assembler / linker / archiver / object tools ------
      # Expected: a package with
      #     $out/bin/<targetPrefix>{ar,as,ld,nm,objcopy,ranlib,strip,...}
      # and a `targetPrefix` attribute ("" for native, e.g.
      # "arm-none-eabi-" for a cross build).
      # Concretely, this attribute decides what these variables execute:
      #     AR=arm-none-eabi-ar   AS=arm-none-eabi-as   LD=arm-none-eabi-ld
      #     NM/RANLIB/OBJCOPY/OBJDUMP/READELF/STRIP=arm-none-eabi-...
      # (exported by the bintools wrapper's setup hook).
      # It MUST target the same architecture/object format as the code
      # your compiler emits.  Suitable choices:
      #   * GNU binutils for that triple   (gcc, tcc: as/ld/ar)
      #   * your own build of binutils, wrapped with `wrapBintoolsWith`
      # A compiler with an integrated assembler (tcc) never calls `as`;
      # it only needs `ld` (if it links itself) and `ar` (to archive).
      binutils = targetPkgs.buildPackages.binutils;

      # -- libc: headers, start files, C library ----------------------
      # Expected: a package with
      #     $out/include/   the headers
      #     $out/lib/       crt1.o, libc.a (and/or libc.so)
      # (optionally `incdir` / `libdir` if the layout differs).
      # Concretely, this attribute fills the wrapper's flag files:
      #     libc-cflags       -> -idirafter <libc>/<target>/include
      #     libc-crt1-cflags  -> -B <libc>/<target>/lib
      #     libc-ldflags      -> linker flags for the C library
      # `null` means "freestanding": no libc flags are added at all and
      # nothing is linked in.  For bare metal this is newlib, newlib-nano,
      # picolibc or your own libc package.
      libc = targetPkgs.newlib;

      # =================================================================
      # 5. The stdenv, defined from those parts
      # =================================================================
      # A stdenv is a set of build phases plus "which toolchain, for which
      # machine".  We take the build machine's stdenv and replace exactly
      # those parts.  nixpkgs defines its own cross stdenv the same way
      # (pkgs/stdenv/cross/default.nix).
      stdenv = nativePkgs.stdenv.override {
        inherit buildPlatform;
        hostPlatform = targetPlatform;
        targetPlatform = targetPlatform;

        cc = cc;
        hasCC = true;

        # The native stdenv's build inputs and package overrides belong to
        # the build machine and must not leak into target packages.
        extraBuildInputs = [ ];
        overrides = _: _: { };

        # Inputs of this stdenv are target packages, so do not check its
        # closure against the native one.
        allowedRequisites = null;
      };

      # What this buys you, concretely: every derivation made with this
      # stdenv gets `cc` in its nativeBuildInputs, whose setup hook exports
      # CC/CXX; the bintools hook (pulled in by cc) exports AR/AS/LD/...;
      # and the wrapper scripts prepend the libc and hardening flags
      # described in section 0.  Nothing else needs to know about ARM.

      # =================================================================
      # 6. libadd / libmul
      # =================================================================
      # Nothing below mentions the compiler, binutils or libc again: the
      # build scripts just use the environment they are given.
      libadd = stdenv.mkDerivation {
        pname = "libadd";
        version = "0.1.0";
        src = ./lib/add;

        buildPhase = ''
          $CC -Os -c add.c -o add.o
          $AR rcs libadd.a add.o
        '';

        installPhase = ''
          mkdir -p $out/lib $out/include
          cp libadd.a $out/lib/
          cp add.h   $out/include/
        '';
      };

      # libadd is consumed exactly like any other Nix dependency: it is a
      # build input, so its store path is available during the build, and
      # `propagatedBuildInputs` forwards it to whatever links libmul.
      # Note there is no `-I` below: nixpkgs' cc-wrapper adds
      # `-isystem <libadd>/include` by itself for every dependency with an
      # `include/` directory (see section 0, point 5).
      libmul = stdenv.mkDerivation {
        pname = "libmul";
        version = "0.1.0";
        src = ./lib/mul;

        buildInputs = [ libadd ];
        propagatedBuildInputs = [ libadd ];

        buildPhase = ''
          $CC -Os -c mul.c -o mul.o
          $AR rcs libmul.a mul.o
        '';

        installPhase = ''
          mkdir -p $out/lib $out/include
          cp libmul.a $out/lib/
          cp mul.h    $out/include/
        '';
      };

      # =================================================================
      # 7. Worked example: bring your own compiler (TCC)
      # =================================================================
      # TCC is not packaged in nixpkgs here, so we build it from its own
      # source.  The point is the wiring: any derivation that provides a
      # compiler driver can become the `cc` of a stdenv.
      #
      # TCC only generates x86-64 code, so this example builds natively
      # (hostPlatform == buildPlatform).  For an embedded target you need
      # a compiler with that backend; the wiring is identical.

      tccSrc = nativePkgs.fetchurl {
        url = "https://github.com/TinyCC/tinycc/archive/refs/heads/mob.tar.gz";
        sha256 = "sha256-ljez32vc4VpWxEQYOxZLBx4VL27gkMcM8/eiKmGEt7c=";
      };

      tcc = nativePkgs.stdenv.mkDerivation {
        pname = "tcc";
        version = "mob";
        src = tccSrc;

        # TCC needs to know where the libc headers/start files live,
        # because there is no /usr/include on NixOS.  {B} and {R} are
        # TCC's own placeholders for "build dir" and "install root".
        buildPhase = ''
          ./configure --prefix=$out --cc=$CC \
            --sysincludepaths='{B}/include:{R}/include:${nativePkgs.glibc.dev}/include' \
            --crtprefix=${nativePkgs.glibc}/lib \
            --libpaths=${nativePkgs.glibc}/lib
          make -j1
        '';
        installPhase = "make install";
      };

      # nixpkgs' cc-wrapper installs the compiler under a name it
      # recognises (`gcc`, `clang` or `arocc`).  TCC's driver is called
      # `tcc`, so expose a `gcc` symlink to it.  That is the whole
      # "adapter" needed for a GCC-compatible command line.
      # Result: the wrapper's setup hook exports CC=gcc (native build:
      # targetPrefix is empty), and `$CC` executes TCC.
      #
      # --- Where $CC is defined in this example -------------------------
      #   1. tccAsGcc puts a driver named `gcc` in $out/bin.
      #   2. When the cc-wrapper is built, its installPhase
      #      (pkgs/build-support/cc-wrapper/default.nix) does:
      #          export named_cc=${targetPrefix}cc
      #          if [ -e $ccPath/${targetPrefix}gcc ]; then
      #              wrap ${targetPrefix}gcc <wrapper> $ccPath/${targetPrefix}gcc
      #              ln -s ${targetPrefix}gcc $out/bin/${targetPrefix}cc
      #              export named_cc=${targetPrefix}gcc
      #      With targetPrefix="" (native) that sets named_cc=gcc and
      #      creates $out/bin/cc -> gcc.
      #   3. setup-hook.sh (pkgs/build-support/cc-wrapper/setup-hook.sh)
      #      contains `export CC${role_post}=@named_cc@`; substituteAll
      #      replaces @named_cc@ when the wrapper is built, giving
      #          export CC${role_post}=gcc
      #   4. At build time getRole sets role_post="" for the package's own
      #      (host) role, so the build environment gets exactly `CC=gcc`.
      #      `gcc` resolves on PATH to $wrapper/bin/gcc (the wrapper script),
      #      which execs $tccAsGcc/bin/gcc, i.e. the tcc binary.
      #   The ARM target uses the same mechanism with targetPrefix set to
      #   "arm-none-eabi-", which is why CC is arm-none-eabi-gcc there.
      #   Without the `gcc` name, installPhase would create no bin/cc and
      #   named_cc would stay at its default `cc`, which does not exist.
      #
      #   What each driver name produces (verified):
      #     gcc/clang/arocc -> bin/<prefix>cc -> that driver, and
      #                        CC=<prefix>gcc|clang|arocc (the wrapper script)
      #     bin/cc only     -> wrapper installs nothing; CC=<prefix>cc
      #                        resolves to that RAW driver (wrapper bypassed)
      #     any other name  -> CC=<prefix>cc, unresolved (build fails)
      #   Alternatives: ship a bin/cc that is already a wrapper (nixpkgs' zig
      #   does this), or provide bin/<prefix>cc plus a
      #   nix-support/setup-hook yourself and use stdenv.override { cc = ...; }
      #   -- which is exactly what wrapCCWith does.
      #
      # The `passthru` below tells the cc-wrapper which hardening flags this
      # compiler cannot handle.  The wrapper calls
      #   cc.hardeningUnsupportedFlagsByTargetPlatform targetPlatform
      # and substitutes the result into @hardening_unsupported_flags@ in
      # nix-support/add-hardening.sh, so those flags are filtered out for
      # every consumer.  It is metadata on the compiler package -- no
      # per-derivation option is needed.
      tccAsGcc = (nativePkgs.runCommand "tcc-as-gcc" { } ''
        mkdir -p $out/bin
        ln -s ${tcc}/bin/tcc $out/bin/gcc
      '').overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          hardeningUnsupportedFlagsByTargetPlatform = _: [
            "fortify" "fortify3" "shadowstack" "stackprotector"
            "stackclashprotection" "nostrictaliasing" "pacret"
            "strictflexarrays1" "strictflexarrays3" "pic"
            "strictoverflow" "libcxxhardeningfast" "libcxxhardeningextensive"
            "glibcxxassertions" "format" "trivialautovarinit"
            "zerocallusedregs" "pie" "relro" "bindnow"
          ];
        };
      });

      # Binutils for TCC: GNU binutils for the same machine TCC emits code
      # for (x86-64 Linux).  TCC has its own assembler/code generator, so
      # only `ar` (archive) and `ld` (link) are used.  Declaring it
      # explicitly here is how you would substitute your own binutils
      # build: `wrapBintoolsWith { bintools = myBinutils; ... }` wraps any
      # package that has $out/bin/{ar,as,ld,nm,objcopy,...}.
      # Result: the setup hook exports AR=ar, AS=as, LD=ld, ... (native
      # build, so no prefix) and those names run this binutils.
      tccBintools = nativePkgs.wrapBintoolsWith {
        bintools = nativePkgs.binutils-unwrapped;
        libc = null;
      };

      # The compiler wrapper: driver + binutils + (no) libc.
      # `libc = null` because TCC carries its own include/library search
      # paths and rejects the -idirafter flags the wrapper adds for glibc.
      # Concretely: with libc = null there are no libc-cflags /
      # libc-crt1-cflags / libc-ldflags entries, so the wrapper adds no
      # -idirafter/-B flags for a C library.
      # (Pass `libc = myLibc;` instead if your compiler wants one.)
      tccCC = nativePkgs.wrapCCWith {
        cc = tccAsGcc;
        bintools = tccBintools;
        libc = null;
      };

      # Everything a stdenv needs: the same re-targeting as section 5.
      tccStdenv = nativePkgs.stdenv.override {
        cc = tccCC;
        hasCC = true;
        allowedRequisites = null;
      };

      tccDemo = tccStdenv.mkDerivation {
        pname = "libadd-built-with-tcc";
        version = "0.1.0";
        src = ./lib/add;

        # No `hardeningDisable` needed: tccAsGcc's passthru declares which
        # hardening flags TCC cannot handle, and the wrapper filters exactly
        # those out of NIX_HARDENING_ENABLE (see section 7).

        buildPhase = ''
          $CC -Os -c add.c -o add.o
          $AR rcs libadd.a add.o
        '';
        installPhase = "mkdir -p $out/lib; cp libadd.a $out/lib";
      };

      # =================================================================
      # 8. TCC exposed as bin/cc (your own wrapper script)
      # =================================================================
      # The cc-wrapper has branches only for drivers named gcc/clang/arocc.
      # If your package ships `bin/cc` instead, the wrapper installs nothing
      # for `cc`; its setup hook still exports CC=cc, and because the cc
      # package's bin/ is put on PATH, `$CC` resolves to THIS script.  So
      # the nixpkgs wrapper script is bypassed: the flags are whatever you
      # write here.  ($AR/$LD still come from the wrapped bintools.)
      tccBinCc = nativePkgs.runCommand "tcc-bincc" { } ''
        mkdir -p $out/bin
        {
          echo '#!${nativePkgs.runtimeShell}'
          echo 'exec ${tcc}/bin/tcc -DTCC_FROM_BINCC=1 "$@"'
        } > $out/bin/cc
        chmod +x $out/bin/cc
      '';

      tccBinCcCC = nativePkgs.wrapCCWith {
        cc = tccBinCc;
        bintools = tccBintools;
        libc = null;
      };
      tccBinCcStdenv = nativePkgs.stdenv.override {
        cc = tccBinCcCC;
        hasCC = true;
        allowedRequisites = null;
      };

      binccDemo = tccBinCcStdenv.mkDerivation {
        pname = "libadd-built-with-bincc";
        version = "0.1.0";
        src = ./lib/add;
        buildPhase = ''
          echo "CC=$CC"
          echo "resolves to: $(command -v "$CC")"

          # The -D flag lives in our bin/cc wrapper; if the wrapper were not
          # used, this file would fail to compile.
          printf '#ifndef TCC_FROM_BINCC\n#error "bin/cc wrapper was not used"\n#endif\nint from_bincc(void) { return TCC_FROM_BINCC; }\n' > check.c
          $CC -Os -c check.c -o check.o

          $CC -Os -c add.c -o add.o
          $AR rcs libadd.a add.o check.o
        '';
        installPhase = "mkdir -p $out/lib; cp libadd.a $out/lib";
      };

      # =================================================================
      # 9. A hand-written cc package (no wrapCCWith at all)
      # =================================================================
      # What wrapCCWith produces is just a package with a driver in bin/ and
      # a nix-support/setup-hook that exports CC.  You can write that
      # yourself and hand it straight to stdenv.override.
      #
      # The setup-hook is mandatory: without it nothing sets $CC (verified
      # -- a bin/cc without a hook leaves CC empty and the build fails).
      tccOwnCc = nativePkgs.runCommand "tcc-own-cc" { } ''
        mkdir -p $out/bin $out/nix-support
        ln -s ${tcc}/bin/tcc $out/bin/cc
        {
          echo 'export CC=cc'
          echo 'export AR=${nativePkgs.binutils-unwrapped}/bin/ar'
          echo 'export RANLIB=${nativePkgs.binutils-unwrapped}/bin/ranlib'
          echo 'export STRIP=${nativePkgs.binutils-unwrapped}/bin/strip'
          echo 'export LD=${nativePkgs.binutils-unwrapped}/bin/ld'
        } > $out/nix-support/setup-hook
      '';

      tccOwnStdenv = nativePkgs.stdenv.override {
        cc = tccOwnCc;
        hasCC = true;
        allowedRequisites = null;
      };

      ownccDemo = tccOwnStdenv.mkDerivation {
        pname = "libadd-built-with-owncc";
        version = "0.1.0";
        src = ./lib/add;
        buildPhase = ''
          echo "CC=$CC"
          echo "resolves to: $(command -v "$CC")"
          echo "AR=$AR"
          $CC -Os -c add.c -o add.o
          $AR rcs libadd.a add.o
        '';
        installPhase = "mkdir -p $out/lib; cp libadd.a $out/lib";
      };

      # =================================================================
      # 10. Show the translation instead of describing it
      # =================================================================
      # Same rule nixpkgs uses for naming tools and variables.
      targetPrefix =
        if targetPlatform != buildPlatform
        then targetPlatform.config + "-"
        else "";

      # `nix run .#explain` prints the concrete variables and flags that the
      # setup hooks and wrapper scripts will produce for this environment.
      explain = nativePkgs.writeShellScriptBin "explain-cross-env" ''
        set -eu
        echo "== target =="
        echo "buildPlatform  = ${buildPlatform.system}"
        echo "targetPlatform = ${targetPlatform.config}"
        echo "targetPrefix   = '${targetPrefix}' (empty == native build)"

        echo
        echo "== variables exported by the setup hooks =="
        echo "(CC is just the conventional name for the C compiler command;"
        echo " its value is the driver name the wrapper found in the cc package.)"
        echo "CC    = ${targetPrefix}gcc"
        echo "CXX   = ${targetPrefix}g++"
        echo "AR    = ${targetPrefix}ar"
        echo "AS    = ${targetPrefix}as"
        echo "LD    = ${targetPrefix}ld"
        echo "NM    = ${targetPrefix}nm"
        echo "OBJCOPY = ${targetPrefix}objcopy"
        echo "RANLIB  = ${targetPrefix}ranlib"
        echo "STRIP   = ${targetPrefix}strip"

        echo
        echo "== raw compiler vs cc-wrapper (two different packages) =="
        echo "raw compiler: $(cat "${cc}/nix-support/orig-cc")"
        echo "  provides bin/ drivers and passthru metadata; exports NO CC."
        echo "wrapper:      ${cc}"
        echo "  provides bin/${targetPrefix}cc -> ${targetPrefix}gcc and"
        echo "  nix-support/setup-hook, which contains the 'export CC=...' line."
        echo "  stdenv's setup.sh sources that hook in every build; Nix itself"
        echo "  never sets CC."

        echo
        echo "== where the CC line lives =="
        echo "template (nixpkgs): pkgs/build-support/cc-wrapper/setup-hook.sh:119"
        echo '  export CC''${role_post}=@named_cc@'
        echo "built wrapper (derivation installPhase sets named_cc):"
        echo "  ${cc}"
        grep -n 'export CC' "${cc}/nix-support/setup-hook" | sed 's/^/  /'
        echo "at build time stdenv sources this file (_addToEnv); role_post is"
        echo "empty for the host role, so the line above executes as:"
        echo "  export CC=${targetPrefix}gcc"

        echo
        echo "== flags injected by the cc-wrapper =="
        for f in cc-cflags cc-cflags-before cc-ldflags libc-cflags libc-crt1-cflags libc-ldflags; do
          if [ -s "${cc}/nix-support/$f" ]; then
            echo "--- $f"
            cat "${cc}/nix-support/$f"
            echo
          fi
        done

        echo
        echo "== the wrapper script and the real compiler =="
        echo "wrapper: ${cc}/bin/${targetPrefix}gcc"
        echo -n "execs:   "
        grep -E '^[[:space:]]*exec ' "${cc}/bin/${targetPrefix}gcc" | head -1 | sed -E 's/^[[:space:]]*exec //'

        echo
        echo "== where CC comes from in the TCC example =="
        echo "1. tcc package:        ${tcc}/bin/tcc"
        echo "2. tccAsGcc exposes:   ${tccAsGcc}/bin/gcc -> $(readlink "${tccAsGcc}/bin/gcc")"
        echo "3. cc-wrapper sees a driver named 'gcc' (native build: targetPrefix is"
        echo "   empty), so during the wrapper build it does:"
        echo "     wraps it as   ${tccCC}/bin/gcc"
        echo "     symlinks      ${tccCC}/bin/cc -> gcc"
        echo "     sets          named_cc=gcc"
        echo "4. its nix-support/setup-hook contains (role_post is empty for the host"
        echo "   role, so the first line is literally 'export CC=gcc'):"
        grep -E '^export (NIX_CC|CC|CXX)' "${tccCC}/nix-support/setup-hook" | sed 's/^/     /'
        echo "   (Without the 'gcc' name the wrapper creates no bin/cc and CC would"
        echo "    point at a nonexistent command.)"
        echo "5. on PATH, 'gcc' is the wrapper above, which execs:"
        grep -E '^[[:space:]]*exec ' "${tccCC}/bin/gcc" | head -1 | sed 's/^/     /'
      '';
    in
    {
      packages.${localSystem} = {
        # the ARM bare-metal target from section 1
        libadd = libadd;
        libmul = libmul;

        # "bring your own parts" examples (native, verified to build)
        tcc-demo = tccDemo;
        bincc-demo = binccDemo;
        owncc-demo = ownccDemo;

        # `nix run .#explain` shows the resulting CC/CXX/AR/... and flags
        explain = explain;
      };

      # Expose the declaration and the environment it produces so they can
      # be inspected or reused, e.g.
      #   nix eval .#env.cc.name
      #   nix eval .#env.targetPlatform.config
      crossSystem = crossSystem;
      env = {
        buildPlatform = buildPlatform;
        targetPlatform = targetPlatform;
        nativePkgs = nativePkgs;
        targetPkgs = targetPkgs;
        cc = cc;
        binutils = binutils;
        libc = libc;
        stdenv = stdenv;

        # the "bring your own parts" wrappers, for inspection
        tccCC = tccCC;
        tccBintools = tccBintools;
        tccBinCc = tccBinCc;
        tccOwnCc = tccOwnCc;
      };
    };
}
