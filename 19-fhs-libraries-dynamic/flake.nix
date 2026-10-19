{
  description = "Chapter 19 — FHS libraries, the dynamic way: versioned .so + SONAME + $ORIGIN";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # -----------------------------------------------------------------------
      # The two libraries, built as real versioned shared objects.
      # -----------------------------------------------------------------------
      mkLib = { pname, version ? "1.0.0", src, sources, headers ? [], libName
              , deps ? [], linkLibs ? [] }:
        pkgs.callPackage ({ lib, stdenv }:
          let
            includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
            depFlags = lib.concatMapStringsSep " " (d: "-L${d}/lib") deps
              + " " + lib.concatMapStringsSep " " (l: "-l${l}") linkLibs;
            soMajor = lib.versions.major version;
            soReal = "lib${libName}.so.${version}";
            soMajorLink = "lib${libName}.so.${soMajor}";
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
              $CC -shared -Wl,-soname,"${soMajorLink}" -o "${soReal}" obj/*.o ${depFlags}
              ln -sf "${soReal}" "${soMajorLink}"
              ln -sf "${soReal}" "lib${libName}.so"
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib" "$out/include"
              cp "${soReal}" "$out/lib/"
              ln -sf "${soReal}" "$out/lib/${soMajorLink}"
              ln -sf "${soReal}" "$out/lib/lib${libName}.so"
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
      # The FHS bundle: headers + shared libs + relocatable pkg-config, with a
      # `$ORIGIN` RUNPATH so the tree can be dropped anywhere.
      # -----------------------------------------------------------------------
      fhsLibs = pkgs.stdenv.mkDerivation {
        pname = "cdemo-libs";
        version = "1.0.0";
        dontUnpack = true;
        dontConfigure = true;
        dontBuild = true;
        # Keep the `$ORIGIN` RUNPATH we set below.
        dontFixup = true;
        nativeBuildInputs = [ pkgs.patchelf pkgs.pkg-config ];
        buildInputs = [ libadd libmul ];

        installPhase = ''
          runHook preInstall
          mkdir -p "$out/lib" "$out/include"
          for dep in ${libadd} ${libmul}; do
            cp -a --no-preserve=mode,ownership "$dep"/lib/.     "$out/lib/"
            cp -a --no-preserve=mode,ownership "$dep"/include/. "$out/include/"
          done
          chmod -R u+w "$out"

          # Relocatable RUNPATH: libmul.so finds libadd.so right next to it.
          find "$out/lib" -type f -name '*.so*' \
            -exec patchelf --set-rpath '$ORIGIN' {} \;

          # A relocatable pkg-config file for each library.  The heredoc is
          # QUOTED ('EOF') so the shell writes pcfiledir/prefix/libdir verbatim
          # for pkg-config to expand at use time; Nix's escape keeps Nix from
          # interpolating them too.
          mkdir -p "$out/lib/pkgconfig"
          cat > "$out/lib/pkgconfig/libadd.pc" <<'EOF'
          prefix=''${pcfiledir}/../..
          exec_prefix=''${prefix}
          libdir=''${prefix}/lib
          includedir=''${prefix}/include

          Name: libadd
          Description: cross-compilation demo library
          Version: 1.0.0
          Libs: -L''${libdir} -ladd
          Cflags: -I''${includedir}
          EOF
          cat > "$out/lib/pkgconfig/libmul.pc" <<'EOF'
          prefix=''${pcfiledir}/../..
          exec_prefix=''${prefix}
          libdir=''${prefix}/lib
          includedir=''${prefix}/include

          Name: libmul
          Description: cross-compilation demo library
          Version: 1.0.0
          Libs: -L''${libdir} -lmul
          Cflags: -I''${includedir}
          EOF
          runHook postInstall
        '';

        # Prove the tree is usable the way a distro would use it.
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

          echo "== dynamic link =="
          $CC test.c -I"$out/include" -L"$out/lib" -lmul -ladd -o test_dynamic
          LD_LIBRARY_PATH="$out/lib" ./test_dynamic

          echo "== pkg-config =="
          PKG_CONFIG_PATH="$out/lib/pkgconfig" pkg-config --cflags --libs libmul
          runHook postInstallCheck
        '';
      };

      fhsLibsTar = pkgs.stdenvNoCC.mkDerivation {
        pname = "cdemo-libs-tar";
        version = "1";
        dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
        nativeBuildInputs = [ pkgs.zstd pkgs.coreutils ];
        installPhase = ''
          set -eu
          mkdir -p "$out"
          cp -r ${fhsLibs} ./cdemo-libs
          chmod -R u+w ./cdemo-libs
          tar --zstd -cf "$out/cdemo-libs-x86_64.tar.zst" cdemo-libs
        '';
      };
    in
    {
      packages.${system} = {
        inherit libadd libmul;
        fhs-libs = fhsLibs;
        fhs-libs-tar = fhsLibsTar;
        default = fhsLibs;
      };
    };
}
