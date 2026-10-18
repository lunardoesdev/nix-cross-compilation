{
  description = "Chapter 10 — compiler metadata that changes flags: hardeningUnsupportedFlags and nixSupport";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # TCC (same as chapters 04–07).
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
      # 1. Metadata the cc-wrapper reads: hardeningUnsupportedFlags
      # =======================================================================
      # The wrapper translates NIX_HARDENING_ENABLE (fortify, pic, relro, ...)
      # into concrete flags.  A compiler that cannot handle some of them
      # advertises that on the compiler PACKAGE via passthru, and the wrapper
      # substitutes the list into nix-support/add-hardening.sh so those flags
      # are never passed.  It is metadata, not a per-derivation option.
      tccAsGcc = (pkgs.runCommand "tcc-as-gcc" { } ''
        mkdir -p $out/bin
        ln -s ${tcc}/bin/tcc $out/bin/gcc
        # the wrapper injects -B<cc>/lib; TCC reads -B as its private dir
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

      tccBintools = pkgs.wrapBintoolsWith {
        bintools = pkgs.binutils-unwrapped;
        libc = null;
      };

      # =======================================================================
      # 2. Metadata that ADDS flags: nixSupport
      # =======================================================================
      # `nixSupport` lets the compiler package contribute files to the wrapper:
      #   * "cc-cflags"        -> extra flags on every invocation
      #   * "cc-ldflags"       -> extra linker flags
      #   * "cc-cflags-before" -> flags prepended before the user's own
      # Here we add a marker macro so the demo can prove the flag was injected.
      tccCC = pkgs.wrapCCWith {
        cc = tccAsGcc;
        bintools = tccBintools;
        libc = null;
        nixSupport = {
          "cc-cflags" = "-DTCC_FROM_NIXSUPPORT=1";
        };
      };

      tccStdenv = pkgs.stdenv.override {
        cc = tccCC;
        hasCC = true;
        allowedRequisites = null;
      };

      # =======================================================================
      # 3. Build with it.
      # =======================================================================
      metadataDemo = tccStdenv.mkDerivation {
        pname = "tcc-metadata-demo";
        version = "1.0.0";
        src = ./src;
        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild

          # The flag comes from nixSupport above; without it this fails to
          # compile.
          printf '#ifndef TCC_FROM_NIXSUPPORT\n#error "nixSupport cc-cflags was not applied"\n#endif\n' > check.c
          $CC -c check.c -o check.o
          $CC main.c add.c check.o -o hello

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
        inherit tcc metadataDemo;
        default = metadataDemo;
      };

      # Inspect the wrapper's generated files:
      #   w=$(nix eval --raw .#env.tccCC)
      #   cat "$w/nix-support/cc-cflags"        # -DTCC_FROM_NIXSUPPORT=1
      #   grep -A2 'unsupported' "$w/nix-support/add-hardening.sh"
      env = { inherit tcc tccAsGcc tccCC tccStdenv; };
    };
}
