{
  description = "Chapter 03 — the invisible chain: how cc/binutils become $CC/$AR/$LD and where flags come from";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      localSystem = "x86_64-linux";
      crossSystem = {
        config = "arm-none-eabi";
        libc = "newlib";
      };

      buildPlatform  = nixpkgs.lib.systems.elaborate localSystem;
      targetPlatform = nixpkgs.lib.systems.elaborate crossSystem;

      nativePkgs = import nixpkgs { inherit localSystem; };
      targetPkgs = import nixpkgs { inherit localSystem crossSystem; };

      cc       = targetPkgs.buildPackages.gcc;
      binutils = targetPkgs.buildPackages.binutils;
      libc     = targetPkgs.newlib;

      stdenv = nativePkgs.stdenv.override {
        inherit buildPlatform;
        hostPlatform = targetPlatform;
        targetPlatform = targetPlatform;
        inherit cc;
        hasCC = true;
        extraBuildInputs = [ ];
        overrides = _: _: { };
        allowedRequisites = null;
      };

      # The target prefix nixpkgs computes and puts in front of every tool and
      # variable name: "arm-none-eabi-".  It is empty for a native build.
      targetPrefix =
        if targetPlatform != buildPlatform then targetPlatform.config + "-" else "";

      # A tiny library we can inspect the build of.
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
      };

      # =======================================================================
      # `explain` — show the translation instead of describing it.
      # =======================================================================
      # Every fact below is read out of the *real* packages nixpkgs produced:
      # the wrapper's setup hook, its flag files, and the script it runs.
      explain = nativePkgs.writeShellScriptBin "explain-cross-env" ''
        set -eu
        echo "== target =="
        echo "buildPlatform  = ${buildPlatform.system}"
        echo "targetPlatform = ${targetPlatform.config}"
        echo "targetPrefix   = '${targetPrefix}'  (empty == a native build)"

        echo
        echo "== variables the setup hooks export =="
        echo "CC      = ${targetPrefix}gcc"
        echo "CXX     = ${targetPrefix}g++"
        echo "AR      = ${targetPrefix}ar"
        echo "AS      = ${targetPrefix}as"
        echo "LD      = ${targetPrefix}ld"
        echo "NM      = ${targetPrefix}nm"
        echo "OBJCOPY = ${targetPrefix}objcopy"
        echo "RANLIB  = ${targetPrefix}ranlib"
        echo "STRIP   = ${targetPrefix}strip"

        echo
        echo "== raw compiler vs cc-wrapper (two different packages) =="
        echo "raw compiler : $(cat "${cc}/nix-support/orig-cc")"
        echo "               (provides bin/ and passthru metadata; exports NO CC)"
        echo "wrapper      : ${cc}"
        echo "               (bin/${targetPrefix}cc -> ${targetPrefix}gcc plus"
        echo "                nix-support/setup-hook with 'export CC=...')"

        echo
        echo "== the CC line that makes \$CC exist =="
        echo "template in nixpkgs: pkgs/build-support/cc-wrapper/setup-hook.sh"
        echo "  export CC\''${role_post}=@named_cc@"
        echo "built wrapper file  : ${cc}/nix-support/setup-hook"
        grep -n 'export CC' "${cc}/nix-support/setup-hook" | sed 's/^/  /'
        echo "at build time stdenv sources that file; role_post is empty for the"
        echo "host role, so it runs as:  export CC=${targetPrefix}gcc"

        echo
        echo "== flags the cc-wrapper injects (its nix-support/ files) =="
        for f in cc-cflags cc-cflags-before cc-ldflags \
                 libc-cflags libc-crt1-cflags libc-ldflags; do
          if [ -s "${cc}/nix-support/$f" ]; then
            echo "--- $f"
            cat "${cc}/nix-support/$f"
            echo
          else
            echo "--- $f (empty)"
          fi
        done

        echo "== the wrapper script and the real compiler =="
        echo "wrapper: ${cc}/bin/${targetPrefix}gcc"
        echo -n "execs:   "
        grep -E '^[[:space:]]*exec ' "${cc}/bin/${targetPrefix}gcc" \
          | head -1 | sed -E 's/^[[:space:]]*exec //'
      '';
    in
    {
      packages.${localSystem} = {
        inherit libadd;
        default = explain;
      };

      # `nix run .#explain`
      apps.${localSystem}.explain = {
        type = "app";
        program = "${explain}/bin/explain-cross-env";
      };

      inherit stdenv cc binutils libc crossSystem;
      platforms = {
        build = buildPlatform.system;
        target = targetPlatform.config;
      };
    };
}
