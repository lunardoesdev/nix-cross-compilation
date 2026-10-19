{
  description = "Chapter 38 — the Canadian cross: build != host != target, and how nixpkgs actually models it";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # A normal cross package set: build on x86_64, run on arm-none-eabi.
      cross = import nixpkgs {
        inherit system;
        crossSystem = { config = "arm-none-eabi"; libc = "newlib"; };
      };

      triples = s: {
        build  = s.buildPlatform.system;
        host   = s.hostPlatform.system;
        target = s.targetPlatform.system;
      };

      libadd = cross.stdenv.mkDerivation {
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
    in
    {
      packages.${system} = {
        inherit libadd;
        default = libadd;
      };

      # The three package sets that matter, and their platform triples.
      platformTriples = {
        native        = triples pkgs.stdenv;                 # (x86_64, x86_64, x86_64)
        cross         = triples cross.stdenv;                # (x86_64, arm,    arm)
        buildPackages = triples cross.buildPackages.stdenv;  # (x86_64, x86_64, arm)
      };

      # The compiler that runs on the build machine and targets arm.
      crossCompiler = cross.buildPackages.gcc;
    };
}
