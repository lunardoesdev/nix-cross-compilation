{
  description = "Chapter 14 — target: Linux x86_64, the native baseline";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # -----------------------------------------------------------------------
      # Linux is the "target" you already have: the native package set.
      # Nothing is cross here -- build == host == x86_64-linux -- which makes it
      # the baseline to compare every other chapter against.
      # -----------------------------------------------------------------------
      target = pkgs;

      mkLib = { pname, version ? "1.0.0", src, sources, headers ? [], libName
              , deps ? [], linkLibs ? [] }:
        target.callPackage ({ lib, stdenv }:
          let
            includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
            depFlags = lib.concatMapStringsSep " " (d: "-L${d}/lib") deps
              + " " + lib.concatMapStringsSep " " (l: "-l${l}") linkLibs;
            soMajor = lib.versions.major version;
            soReal = "lib${libName}.so.${version}";
            soMajorLink = "lib${libName}.so.${soMajor}";
            soDevLink = "lib${libName}.so";
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
              $CC -shared -Wl,-soname,"${soMajorLink}" -o "${soReal}" obj/*.o ${depFlags}
              ln -sf "${soReal}" "${soMajorLink}"
              ln -sf "${soReal}" "${soDevLink}"
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib" "$out/include"
              cp "lib${libName}.a" "$out/lib/"
              cp "${soReal}" "$out/lib/"
              ln -sf "${soReal}" "$out/lib/${soMajorLink}"
              ln -sf "${soReal}" "$out/lib/${soDevLink}"
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
              -o uselib2 \
              -L${libmul}/lib -lmul -L${libadd}/lib -ladd
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin"
            cp uselib2 "$out/bin/"
            runHook postInstall
          '';
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            output="$(./uselib2)"; echo "$output"
            echo "$output" | grep -q 'mul(6, 7) = 42'
            runHook postCheck
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
