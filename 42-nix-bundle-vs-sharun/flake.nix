{
  description = "Chapter 42 — nix bundle vs sharun";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      libadd = pkgs.stdenv.mkDerivation {
        pname = "libadd"; version = "1.0.0"; src = ./src;
        dontConfigure = true; enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC -O2 -fPIC -c add.c -o add.o
          $AR rcs libadd.a add.o
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/include
          cp libadd.a $out/lib/; cp add.h $out/include/
          runHook postInstall
        '';
      };

      libmul = pkgs.stdenv.mkDerivation {
        pname = "libmul"; version = "1.0.0"; src = ./src;
        buildInputs = [ libadd ];
        propagatedBuildInputs = [ libadd ];
        dontConfigure = true; enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC -O2 -fPIC -c mul.c -o mul.o
          $AR rcs libmul.a mul.o
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/include
          cp libmul.a $out/lib/; cp mul.h $out/include/
          runHook postInstall
        '';
      };

      uselib2 = pkgs.stdenv.mkDerivation {
        pname = "uselib2"; version = "1.0.0"; src = ./src;
        buildInputs = [ libmul libadd ];
        dontConfigure = true; enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC -O2 main.c -o uselib2 -lmul -ladd
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin; cp uselib2 $out/bin/
          runHook postInstall
        '';
        doCheck = true;
        checkPhase = ''
          output="$(./uselib2)"; echo "$output"
          echo "$output" | grep -q 'mul(6, 7) = 42'
        '';
        meta.mainProgram = "uselib2";
      };
    in
    {
      packages.${system} = { inherit libadd libmul uselib2; default = uselib2; };
    };
}
