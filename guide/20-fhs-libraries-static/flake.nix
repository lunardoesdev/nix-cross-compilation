{
  description = "Chapter 20 — FHS libraries, the static way: plain .a archives, no runtime dependency";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # -----------------------------------------------------------------------
      # The two libraries, as STATIC archives only.
      # No -fPIC needed, no -shared step, no SONAME, no runtime dependency.
      # -----------------------------------------------------------------------
      mkLib = { pname, version ? "1.0.0", src, sources, headers ? [], libName
              , deps ? [], linkLibs ? [] }:
        pkgs.callPackage ({ lib, stdenv }:
          let
            includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
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
                $CC -O2 -Wall -Wextra ${includeFlags} \
                  -c "$f" -o "obj/$(basename "$f" .c).o"
              done
              $AR rcs "lib${libName}.a" obj/*.o
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib" "$out/include"
              cp "lib${libName}.a" "$out/lib/"
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

      # -----------------------------------------------------------------------
      # The FHS static bundle: headers + archives + pkg-config.
      # -----------------------------------------------------------------------
      fhsStatic = pkgs.stdenv.mkDerivation {
        pname = "cdemo-libs-static";
        version = "1.0.0";
        dontUnpack = true;
        dontConfigure = true;
        dontBuild = true;
        dontFixup = true;
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ libadd libmul ];

        installPhase = ''
          runHook preInstall
          mkdir -p "$out/lib/pkgconfig" "$out/include"
          for dep in ${libadd} ${libmul}; do
            cp -a --no-preserve=mode,ownership "$dep"/lib/.     "$out/lib/"
            cp -a --no-preserve=mode,ownership "$dep"/include/. "$out/include/"
          done
          chmod -R u+w "$out"

          # Static pkg-config: libmul's archive references add(), so a consumer
          # must link BOTH archives -- hence `-lmul -ladd` in libmul.pc.
          cat > "$out/lib/pkgconfig/libadd.pc" <<'EOF'
          prefix=''${pcfiledir}/../..
          libdir=''${prefix}/lib
          includedir=''${prefix}/include

          Name: libadd
          Description: cross-compilation demo library (static)
          Version: 1.0.0
          Libs: -L''${libdir} -ladd
          Cflags: -I''${includedir}
          EOF
          cat > "$out/lib/pkgconfig/libmul.pc" <<'EOF'
          prefix=''${pcfiledir}/../..
          libdir=''${prefix}/lib
          includedir=''${prefix}/include

          Name: libmul
          Description: cross-compilation demo library (static)
          Version: 1.0.0
          Libs: -L''${libdir} -lmul -ladd
          Cflags: -I''${includedir}
          EOF
          runHook postInstall
        '';

        doInstallCheck = true;
        installCheckPhase = ''
          runHook preInstallCheck
          cat > test.c <<'EOF'
          #include <stdio.h>
          #include <add.h>
          #include <mul.h>
          int main(void) {
              printf("mul(6, 7) = %d\n", mul(6, 7));
              return mul(6, 7) == 42 ? 0 : 1;
          }
          EOF

          echo "== static libs, dynamic libc =="
          $CC test.c -I"$out/include" -L"$out/lib" \
            -Wl,-Bstatic -lmul -ladd -Wl,-Bdynamic -o test_static
          ./test_static

          echo "== fully static =="
          $CC test.c -static -I"$out/include" -L"$out/lib" -lmul -ladd -o test_fully_static
          ./test_fully_static
          file test_fully_static

          echo "== pkg-config =="
          PKG_CONFIG_PATH="$out/lib/pkgconfig" pkg-config --cflags --libs libmul
          runHook postInstallCheck
        '';
      };

      fhsStaticTar = pkgs.stdenvNoCC.mkDerivation {
        pname = "cdemo-libs-static-tar";
        version = "1";
        dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
        nativeBuildInputs = [ pkgs.zstd pkgs.coreutils ];
        installPhase = ''
          set -eu
          mkdir -p "$out"
          cp -r ${fhsStatic} ./cdemo-libs-static
          chmod -R u+w ./cdemo-libs-static
          tar --zstd -cf "$out/cdemo-libs-static-x86_64.tar.zst" cdemo-libs-static
        '';
      };
    in
    {
      packages.${system} = {
        inherit libadd libmul;
        fhs-libs-static = fhsStatic;
        fhs-libs-static-tar = fhsStaticTar;
        default = fhsStatic;
      };
    };
}
