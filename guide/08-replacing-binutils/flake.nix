{
  description = "Chapter 08 — replacing binutils, and the one rule that decides which binutils are suitable";

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

      # =======================================================================
      # The one rule
      # =======================================================================
      # Binutils must target the SAME architecture and object format as the code
      # your compiler emits.  That is the entire suitability rule:
      #
      #   * gcc  -> GNU binutils for the same triple (here arm-none-eabi).
      #   * tcc  -> it has its own code generator/assembler, so it never calls
      #             `as`; it only needs `ar` (to archive) and `ld` (if it links).
      #   * a mismatched pair (x86-64 binutils with an ARM compiler) fails: the
      #             assembler cannot parse the emitted assembly and the linker
      #             rejects the object format.
      #
      # Section "negative test" below builds that mismatch on purpose and proves
      # it fails.

      # =======================================================================
      # Explicitly wrapped binutils
      # =======================================================================
      # `wrapBintoolsWith` is to binutils what `wrapCCWith` is to a compiler: it
      # produces the package whose setup hook exports AR/AS/LD/NM/RANLIB/... .
      # Any package providing $out/bin/<prefix>{ar,as,ld,...} works.
      myBintools = nativePkgs.wrapBintoolsWith {
        bintools = targetPkgs.buildPackages.binutils-unwrapped;
        libc = targetPkgs.newlib;
      };

      # A compiler that uses exactly those binutils.
      myCC = nativePkgs.wrapCCWith {
        cc = targetPkgs.buildPackages.gcc;
        bintools = myBintools;
        libc = targetPkgs.newlib;
      };

      stdenv = nativePkgs.stdenv.override {
        inherit buildPlatform;
        hostPlatform = targetPlatform;
        targetPlatform = targetPlatform;
        cc = myCC;
        hasCC = true;
        extraBuildInputs = [ ];
        overrides = _: _: { };
        allowedRequisites = null;
      };

      libadd = stdenv.mkDerivation {
        pname = "libadd";
        version = "1.0.0";
        src = ./src;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          echo "AR=$AR  -> $(command -v "$AR")"
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
      # Negative test: a mismatched assembler must be rejected.
      # =======================================================================
      # We produce ARM assembly with the ARM compiler, then feed it to the host's
      # x86-64 `as`.  The assembler must refuse it.  This turns "suitable
      # binutils" from a slogan into something the build checks.
      mismatch = nativePkgs.runCommand "binutils-mismatch" {
        nativeBuildInputs = [ targetPkgs.buildPackages.gcc nativePkgs.binutils ];
      } ''
        echo 'int add(int a, int b) { return a + b; }' > add.c

        # ARM assembly, emitted by the ARM compiler.
        arm-none-eabi-gcc -S add.c -o add.s
        grep -q '\.arm\|\.syntax' add.s || true

        # The x86-64 assembler must NOT accept it.
        if as add.s -o add.o 2> err; then
          echo "ERROR: the x86-64 assembler accepted ARM assembly" >&2
          exit 1
        fi

        echo "as expected: the x86-64 assembler rejected ARM assembly:" > "$out"
        echo "---- assembler output ----" >> "$out"
        head -5 err >> "$out"
      '';
    in
    {
      packages.${localSystem} = {
        inherit libadd mismatch;
        default = libadd;
      };

      env = {
        inherit myBintools myCC stdenv;
        # The default binutils for this target, for comparison:
        defaultBintools = targetPkgs.buildPackages.binutils;
      };
    };
}
