{
  description = "Chapter 07 — TCC variant 3: a hand-written cc package with a setup hook (no wrapCCWith)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # TCC itself (same as chapters 04–06).
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
      # Variant 3 — write the `cc` package yourself.
      # =======================================================================
      # `wrapCCWith` is not magic.  It produces exactly two things:
      #
      #   1. a driver in $out/bin (under the wrapped name), and
      #   2. a `nix-support/setup-hook` that exports CC (and friends).
      #
      # You can write both by hand and hand the result straight to
      # `stdenv.override { cc = ...; }`.  The setup hook is MANDATORY: without it
      # nothing sets $CC at all (the build then fails with an empty CC).
      tccOwnCc = pkgs.runCommand "tcc-own-cc" { } ''
        mkdir -p $out/bin $out/nix-support

        # 1. the driver
        ln -s ${tcc}/bin/tcc $out/bin/cc

        # 2. the setup hook.  This is the entire interface the stdenv needs.
        {
          echo 'export CC=cc'
          echo 'export AR=${pkgs.binutils-unwrapped}/bin/ar'
          echo 'export RANLIB=${pkgs.binutils-unwrapped}/bin/ranlib'
          echo 'export STRIP=${pkgs.binutils-unwrapped}/bin/strip'
          echo 'export LD=${pkgs.binutils-unwrapped}/bin/ld'
        } > $out/nix-support/setup-hook
      '';

      # A stdenv that uses the hand-written cc package.  No wrapCCWith anywhere.
      tccOwnStdenv = pkgs.stdenv.override {
        cc = tccOwnCc;
        hasCC = true;
        allowedRequisites = null;
      };

      # =======================================================================
      # Build with it.
      # =======================================================================
      ownccDemo = tccOwnStdenv.mkDerivation {
        pname = "libadd-built-with-owncc";
        version = "1.0.0";
        src = ./src;
        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild
          echo "CC=$CC  -> $(command -v "$CC")"
          echo "AR=$AR"
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
        inherit tcc tccOwnCc ownccDemo;
        default = ownccDemo;
      };

      env = { inherit tcc tccOwnCc tccOwnStdenv; };
    };
}
