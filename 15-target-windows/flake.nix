{
  description = "Chapter 15 — target: Windows x86_64 via mingw-w64";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # -----------------------------------------------------------------------
      # The Windows target: a complete nixpkgs set whose stdenv is mingw-w64.
      # The compiler is x86_64-w64-mingw32-gcc and produces PE/COFF objects.
      # -----------------------------------------------------------------------
      target = pkgs.pkgsCross.mingwW64;

      # A shared-library builder for PE/COFF: no SONAME, and an import library
      # (`libfoo.dll.a`) that consumers link against.
      mkLib = { pname, version ? "1.0.0", src, sources, headers ? [], libName
              , deps ? [], linkLibs ? [] }:
        target.callPackage ({ lib, stdenv }:
          let
            includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
            depFlags = lib.concatMapStringsSep " " (d: "-L${d}/lib") deps
              + " " + lib.concatMapStringsSep " " (l: "-l${l}") linkLibs;
          in
          stdenv.mkDerivation {
            inherit pname version src;
            buildInputs = deps;
            strictDeps = true;
            dontConfigure = true;
            enableParallelBuilding = false;
            buildPhase = ''
              runHook preBuild
              mkdir -p obj
              for f in ${lib.concatStringsSep " " sources}; do
                $CC -O2 -fPIC -Wall -Wextra ${includeFlags} \
                  -c "$f" -o "obj/$(basename "$f" .c).o"
              done
              $AR rcs "lib${libName}.a" obj/*.o
              $CC -shared -o "lib${libName}.dll" obj/*.o ${depFlags} \
                -Wl,--out-implib,"lib${libName}.dll.a"
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib" "$out/bin" "$out/include"
              cp "lib${libName}.a"     "$out/lib/"
              cp "lib${libName}.dll.a" "$out/lib/"
              cp "lib${libName}.dll"   "$out/bin/"
              ${lib.concatMapStringsSep "\n" (h: ''cp "${h}" "$out/include/"'') headers}
              runHook postInstall
            '';
          }) { };

      libadd = mkLib {
        pname = "libadd"; src = ./src;
        sources = [ "add.c" ]; headers = [ "add.h" ]; libName = "add";
      };

      libmul = mkLib {
        pname = "libmul"; src = ./src;
        sources = [ "mul.c" ]; headers = [ "mul.h" ]; libName = "mul";
        deps = [ libadd ]; linkLibs = [ "add" ];
      };

      uselib2 = target.callPackage ({ lib, stdenv }:
        stdenv.mkDerivation {
          pname = "uselib2";
          version = "1.0.0";
          src = ./src;
          buildInputs = [ libmul libadd ];
          strictDeps = true;
          dontConfigure = true;
          enableParallelBuilding = false;
          buildPhase = ''
            runHook preBuild
            $CC -O2 -Wall -Wextra \
              -I${libmul}/include -I${libadd}/include main.c \
              -o uselib2.exe \
              -L${libmul}/lib -lmul -L${libadd}/lib -ladd
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin"
            cp uselib2.exe "$out/bin/"
            runHook postInstall
          '';
        }) { };
    in
    {
      packages.${system} = {
        inherit libadd libmul uselib2;
        default = uselib2;
      };
    };
}
