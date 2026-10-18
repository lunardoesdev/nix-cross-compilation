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

      nativePkgs = import nixpkgs { inherit localSystem; };
      targetPkgs = import nixpkgs { inherit localSystem crossSystem; };

      # =======================================================================
      # The one rule
      # =======================================================================
      # Binutils must target the SAME architecture and object format as the code
      # your compiler emits.  That is the entire suitability rule:
      #
      #   * gcc -> GNU binutils for the same triple (arm-none-eabi for the ARM
      #            target, plain x86-64 binutils for a native build).
      #   * tcc -> it has its own code generator/assembler, so it never calls
      #            `as`; it only needs `ar` (to archive) and `ld` (if it links).
      #   * a mismatched pair (x86-64 binutils with an ARM compiler) fails: the
      #            assembler cannot parse the emitted assembly.
      #
      # The `mismatch` output below builds that mismatch on purpose and proves it
      # fails, so the rule is checked rather than merely stated.
      #
      # This chapter demonstrates the substitution NATIVELY (x86-64), because
      # that is the case where the wiring is short enough to read.  For a cross
      # target the very same `wrapBintoolsWith`/`wrapCCWith` calls are used by
      # nixpkgs internally, with the target's platform descriptions filled in --
      # see `pkgs/stdenv/cross/default.nix`.

      # =======================================================================
      # 1. Explicitly wrapped binutils.
      # =======================================================================
      # `wrapBintoolsWith` is to binutils what `wrapCCWith` is to a compiler: it
      # produces the package whose setup hook exports AR/AS/LD/NM/RANLIB/... .
      # Any package providing $out/bin/{ar,as,ld,nm,objcopy,ranlib,strip,...}
      # works, as long as it matches the compiler's target.
      myBintools = nativePkgs.wrapBintoolsWith {
        bintools = nativePkgs.binutils-unwrapped;
        libc = null;
      };

      # =======================================================================
      # 2. A compiler that uses exactly those binutils.
      # =======================================================================
      # The `cc` argument must be the RAW compiler (gcc-unwrapped), because
      # `wrapCCWith` looks for a driver named `gcc` in its $out/bin.  We also give
      # it a libc, since this is a hosted (Linux) target.
      myCC = nativePkgs.wrapCCWith {
        cc = nativePkgs.gcc-unwrapped;
        bintools = myBintools;
        libc = nativePkgs.glibc;
      };

      stdenv = nativePkgs.stdenv.override {
        cc = myCC;
        hasCC = true;
        allowedRequisites = null;
      };

      # =======================================================================
      # 3. Build with it.
      # =======================================================================
      hello = stdenv.mkDerivation {
        pname = "hello-with-my-binutils";
        version = "1.0.0";
        src = ./src;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          echo "AR=$AR  -> $(command -v "$AR")"
          echo "LD=$LD  -> $(command -v "$LD")"
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
          output="$(./hello)"
          echo "$output"
          echo "$output" | grep -q 'add(6, 7) = 13'
          runHook postCheck
        '';
      };

      # =======================================================================
      # 4. Negative test: a mismatched assembler must be rejected.
      # =======================================================================
      # Emit ARM assembly with the ARM compiler, then feed it to the host's
      # x86-64 `as`.  The assembler must refuse it.  This turns "suitable
      # binutils" into something the build actually checks.
      mismatch = nativePkgs.runCommand "binutils-mismatch" {
        nativeBuildInputs = [ targetPkgs.buildPackages.gcc nativePkgs.binutils ];
      } ''
        echo 'int add(int a, int b) { return a + b; }' > add.c

        # ARM assembly, emitted by the ARM compiler.
        arm-none-eabi-gcc -S add.c -o add.s

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
        inherit hello mismatch;
        default = hello;
      };

      env = {
        inherit myBintools myCC stdenv;
        defaultNativeBintools = nativePkgs.binutils;
        crossBintools = targetPkgs.buildPackages.binutils;
      };
    };
}
