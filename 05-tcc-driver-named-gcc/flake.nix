{
  description = "Chapter 05 — TCC variant 1: expose the driver as `gcc` and reuse the nixpkgs cc-wrapper";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # =======================================================================
      # 0. TCC itself (identical to chapter 04, fixes included).
      # =======================================================================
      tccSrc = pkgs.fetchurl {
        url = "https://github.com/TinyCC/tinycc/archive/refs/heads/mob.tar.gz";
        sha256 = "sha256-ljez32vc4VpWxEQYOxZLBx4VL27gkMcM8/eiKmGEt7c=";
      };

      tcc = pkgs.stdenv.mkDerivation {
        pname = "tcc";
        version = "mob";
        src = tccSrc;
        buildPhase = ''
          runHook preBuild
          prefix="$out"
          ./configure --prefix="$prefix" --cc=$CC \
            --sysincludepaths="{B}/include:$prefix/include:${pkgs.glibc.dev}/include" \
            --crtprefix="$prefix/lib/tcc:${pkgs.glibc}/lib" \
            --libpaths="$prefix/lib/tcc:${pkgs.glibc}/lib" \
            --elfinterp="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
          make -j1
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          make install
          runHook postInstall
        '';
        enableParallelBuilding = false;
      };

      # =======================================================================
      # 1. Variant 1 — name the driver `gcc`.
      # =======================================================================
      # The cc-wrapper (nixpkgs' own wrapper, chapter 03) looks for a driver
      # called `gcc`, `clang` or `arocc` in the cc package's $out/bin.  TCC's
      # driver is called `tcc`, so we expose it under the name `gcc`.  That single
      # symlink is the entire adapter: the wrapper now treats TCC as "the C
      # compiler" and exports CC=gcc (native build => empty prefix).
      #
      # The `passthru` tells the wrapper which hardening flags TCC cannot handle.
      # The wrapper calls
      #   cc.hardeningUnsupportedFlagsByTargetPlatform targetPlatform
      # and substitutes the result into nix-support/add-hardening.sh, so those
      # flags are filtered out for every consumer.  No per-derivation
      # `hardeningDisable` is needed.
      tccAsGcc = (pkgs.runCommand "tcc-as-gcc" { } ''
        mkdir -p $out/bin
        ln -s ${tcc}/bin/tcc $out/bin/gcc

        # The cc-wrapper always adds `-B<cc-package>/lib` to the compiler flags
        # because for gcc that is where libgcc/crt live.  TCC, however, reads
        # `-Bdir` as "my private dir": it then looks for its own headers and
        # `libtcc1.a` in `dir/`.  So point `$out/lib` at TCC's real private dir,
        # and the injected `-B` becomes correct instead of breaking the include
        # search (otherwise you get `error: include file 'stddef.h' not found`).
        ln -s ${tcc}/lib/tcc $out/lib
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

      # =======================================================================
      # 2. Binutils for TCC.
      # =======================================================================
      # TCC has its own assembler and code generator, so it only ever uses `ar`
      # (to archive) and `ld` (if it delegates linking).  Any binutils that can
      # handle TCC's output works; the native GNU binutils do.
      tccBintools = pkgs.wrapBintoolsWith {
        bintools = pkgs.binutils-unwrapped;
        libc = null;
      };

      # =======================================================================
      # 3. The compiler wrapper.
      # =======================================================================
      # driver + binutils + no libc.  `libc = null` because TCC carries its own
      # include/library search paths (baked in at configure time, chapter 04) and
      # would choke on the -idirafter flags the wrapper adds for glibc.
      tccCC = pkgs.wrapCCWith {
        cc = tccAsGcc;
        bintools = tccBintools;
        libc = null;
      };

      # =======================================================================
      # 4. A stdenv whose compiler is that wrapper.
      # =======================================================================
      tccStdenv = pkgs.stdenv.override {
        cc = tccCC;
        hasCC = true;
        allowedRequisites = null;
      };

      # =======================================================================
      # 5. Build something with it: the same libadd + hello.
      # =======================================================================
      # Note there is no reference to TCC anywhere below: the build script uses
      # `$CC`/`$AR` exactly like a native gcc build would.
      libadd = tccStdenv.mkDerivation {
        pname = "libadd-built-with-tcc";
        version = "1.0.0";
        src = ./src;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          echo "CC=$CC  -> $(command -v "$CC")"
          $CC -c add.c -o add.o
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

      hello = tccStdenv.mkDerivation {
        pname = "tcc-hello-wrapped";
        version = "1.0.0";
        src = ./src;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC main.c add.c -o hello
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
          output="$(./hello)"
          echo "$output"
          echo "$output" | grep -q 'add(6, 7) = 13'
          runHook postCheck
        '';
      };
    in
    {
      packages.${system} = {
        inherit tcc libadd hello;
        default = hello;
      };

      # Inspect the pieces, e.g.:
      #   nix eval --raw .#env.tccCC
      #   grep 'export CC' "$(nix eval --raw .#env.tccCC)/nix-support/setup-hook"
      env = { inherit tcc tccAsGcc tccBintools tccCC tccStdenv; };
    };
}
