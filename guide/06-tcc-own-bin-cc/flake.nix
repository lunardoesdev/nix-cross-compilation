{
  description = "Chapter 06 — TCC variant 2: ship your own bin/cc, bypassing the nixpkgs cc-wrapper";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # TCC itself (same as chapters 04/05).
      tcc = pkgs.stdenv.mkDerivation {
        pname = "tcc";
        version = "mob";
        src = pkgs.fetchurl {
          url = "https://github.com/TinyCC/tinycc/archive/refs/heads/mob.tar.gz";
          sha256 = "sha256-ljez32vc4VpWxEQYOxZLBx4VL27gkMcM8/eiKmGEt7c=";
        };
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
      # Variant 2 — ship your own `bin/cc`.
      # =======================================================================
      # The cc-wrapper has branches only for drivers named gcc/clang/arocc.  If
      # the cc package instead ships a `bin/cc`, the wrapper:
      #
      #   * installs nothing for `cc` (there is no `cc` branch), but
      #   * still exports `CC=cc` from its setup hook, and
      #   * puts the cc package's `bin/` on PATH,
      #
      # so `$CC` resolves to OUR script.  The wrapper's flag injection is
      # bypassed entirely: the flags are exactly what we write.  ($AR/$LD still
      # come from the wrapped binutils.)
      tccBinCc = pkgs.runCommand "tcc-bincc" { } ''
        mkdir -p $out/bin
        {
          echo '#!${pkgs.runtimeShell}'
          # -DTCC_FROM_BINCC is a marker so the demo can PROVE this script ran.
          echo 'exec ${tcc}/bin/tcc -DTCC_FROM_BINCC=1 "$@"'
        } > $out/bin/cc
        chmod +x $out/bin/cc
      '';

      tccBintools = pkgs.wrapBintoolsWith {
        bintools = pkgs.binutils-unwrapped;
        libc = null;
      };

      tccBinCcCC = pkgs.wrapCCWith {
        cc = tccBinCc;
        bintools = tccBintools;
        libc = null;
      };

      tccBinCcStdenv = pkgs.stdenv.override {
        cc = tccBinCcCC;
        hasCC = true;
        allowedRequisites = null;
      };

      # =======================================================================
      # Build with it.
      # =======================================================================
      binccDemo = tccBinCcStdenv.mkDerivation {
        pname = "libadd-built-with-bincc";
        version = "1.0.0";
        src = ./src;
        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild

          echo "CC=$CC"
          echo "resolves to: $(command -v "$CC")"

          # If our bin/cc script were NOT used, -DTCC_FROM_BINCC would be
          # missing and this file would fail to compile.
          printf '#ifndef TCC_FROM_BINCC\n#error "bin/cc wrapper was not used"\n#endif\nint from_bincc(void) { return TCC_FROM_BINCC; }\n' > check.c
          $CC -c check.c -o check.o

          $CC main.c add.c check.o -o hello

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin $out/lib $out/include
          cp hello   $out/bin/
          cp add.h   $out/include/
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
        inherit tcc tccBinCc binccDemo;
        default = binccDemo;
      };

      env = { inherit tcc tccBinCc tccBintools tccBinCcCC tccBinCcStdenv; };
    };
}
