{
  description = "Chapter 04 — building TinyCC from source, the compiler we will plug into a stdenv";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # =======================================================================
      # Part 2 in one sentence
      # =======================================================================
      # Chapters 04–07 replace the `cc` part of a stdenv with TinyCC.  TCC is not
      # in nixpkgs, so we build it from source.  The point is NOT TCC itself: it
      # is that a compiler is just *a package with a driver in $out/bin*, and a
      # stdenv can be told to use it.  The same three techniques work for any
      # compiler you have.
      #
      # TCC only emits x86-64 machine code, so this part of the guide builds
      # *natively* (buildPlatform == hostPlatform == x86_64-linux).  That keeps
      # the focus on the wiring.  For a real cross target you would use a
      # compiler that has that target's backend; the wiring is identical.

      # =======================================================================
      # 1. The TCC source.
      # =======================================================================
      # Pinned by hash: if upstream ever moves the `mob` branch, the fixed-output
      # download fails loudly instead of changing under our feet.
      tccSrc = pkgs.fetchurl {
        url = "https://github.com/TinyCC/tinycc/archive/refs/heads/mob.tar.gz";
        sha256 = "sha256-ljez32vc4VpWxEQYOxZLBx4VL27gkMcM8/eiKmGEt7c=";
      };

      # =======================================================================
      # 2. Build TCC with the ordinary Nix toolchain.
      # =======================================================================
      # Nothing special here -- TCC is built by gcc like any other C program.
      tcc = pkgs.stdenv.mkDerivation {
        pname = "tcc";
        version = "mob";
        src = tccSrc;

        # TCC has no /usr/include to fall back on, so it must be told where the
        # C library headers, the start files and the libraries are.  `{B}` is
        # TCC's placeholder for its own build directory.  We use the literal
        # `$out` (which --prefix already sets) rather than `{R}`: only `{B}` is
        # substituted by TCC, so `{R}` would expand to nothing at runtime.
        #
        # `$out/lib/tcc` MUST come first in --libpaths: `tcc_add_support()`
        # searches the *library* path for its own runtime `libtcc1.a`
        # (`tcc.c` prints it as `library_paths[0]/libtcc1.a`).  Without it,
        # compiling is fine (`tcc -c`) but linking fails with
        # `tcc: error: file 'libtcc1.a' not found`.
        #
        # --crtprefix is separate and is where crt1.o/crti.o are looked up; it
        # gets nixpkgs' glibc.
        buildPhase = ''
          runHook preBuild
          prefix="$out"
          ./configure --prefix="$prefix" --cc=$CC \
            --sysincludepaths="{B}/include:$prefix/include:${pkgs.glibc.dev}/include" \
            --crtprefix="$prefix/lib/tcc:${pkgs.glibc}/lib" \
            --libpaths="$prefix/lib/tcc:${pkgs.glibc}/lib"
          make -j1            # single job, as everywhere in this guide
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          make install
          runHook postInstall
        '';

        enableParallelBuilding = false;

        meta = {
          description = "TinyCC, built from source";
          platforms = [ "x86_64-linux" ];
        };
      };

      # =======================================================================
      # 3. Prove TCC works, without any stdenv wiring yet.
      # =======================================================================
      # We call TCC by absolute path.  `$AR` and the rest are still the native
      # ones from the ordinary stdenv; only the C compiler is TCC.  Chapter 05
      # replaces the stdenv properly, so that `$CC` *is* TCC.
      tccDemo = pkgs.stdenv.mkDerivation {
        pname = "tcc-hello";
        version = "1.0.0";
        src = ./src;

        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild

          # Compile the library and the program with TCC.
          ${tcc}/bin/tcc -c add.c -o add.o
          $AR rcs libadd.a add.o
          ${tcc}/bin/tcc main.c libadd.a -o hello

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp hello $out/bin/
          runHook postInstall
        '';

        # TCC emits x86-64 code here, so we can actually run the result.
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          output="$(./hello)"
          echo "$output"
          echo "$output" | grep -q 'add(6, 7) = 13'
          runHook postCheck
        '';

        meta.description = "libadd + hello, compiled directly with TCC";
      };
    in
    {
      packages.${system} = {
        inherit tcc tccDemo;
        default = tccDemo;
      };

      # `nix eval --raw .#tcc` prints the store path of the compiler.
      inherit tcc tccSrc;
    };
}
