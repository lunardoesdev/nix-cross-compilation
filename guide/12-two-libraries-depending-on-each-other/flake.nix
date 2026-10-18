{
  description = "Chapter 12 — two C libraries that depend on each other, for multiple platforms";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      localSystem = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit localSystem;
        config.allowUnfree = true;
      };

      # The same target table as chapter 11.  Add a row, get a new platform.
      targets = {
        linux = pkgs;
        windows = pkgs.pkgsCross.mingwW64;
      };

      # =======================================================================
      # Generic library builder (static + shared)
      # =======================================================================
      # Differences per platform, all handled here so the recipe stays shared:
      #
      #   * Windows: produces libfoo.dll + an import library libfoo.dll.a.
      #   * ELF (Linux/Android): a versioned libfoo.so.<version> with the usual
      #     libfoo.so.<major> and libfoo.so symlinks and DT_SONAME.
      #
      # `deps` are ordinary derivations; headers come from $dep/include and
      # libraries from $dep/lib.  Nix manages them (buildInputs); the -I/-L flags
      # are spelled out so the same builder also works with emcc later.
      mkLib =
        target:
        { pname
        , version ? "1.0.0"
        , src
        , sources
        , headers ? []
        , libName
        , deps ? []
        , linkLibs ? []
        , shared ? true
        }:
        target.callPackage ({ lib, stdenv }:
          let
            isWindows = stdenv.hostPlatform.isWindows;

            includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
            depFlags =
              lib.concatMapStringsSep " " (d: "-L${d}/lib") deps
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
            doCheck = false;
            enableParallelBuilding = false;

            buildPhase = ''
              runHook preBuild
              mkdir -p obj
              for f in ${lib.concatStringsSep " " sources}; do
                $CC -O2 -fPIC -Wall -Wextra ${includeFlags} \
                  -c "$f" -o "obj/$(basename "$f" .c).o"
              done
              $AR rcs "lib${libName}.a" obj/*.o
            '' + lib.optionalString shared (
              if isWindows then ''

                $CC -shared -o "lib${libName}.dll" obj/*.o ${depFlags} \
                  -Wl,--out-implib,"lib${libName}.dll.a"
              '' else ''

                $CC -shared -Wl,-soname,"${soMajorLink}" \
                  -o "${soReal}" obj/*.o ${depFlags}
                ln -sf "${soReal}" "${soMajorLink}"
                ln -sf "${soReal}" "${soDevLink}"
              ''
            ) + ''
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib" "$out/include"
            '' + lib.optionalString isWindows ''
              mkdir -p "$out/bin"
            '' + lib.concatMapStringsSep "\n"
              (line: "  ${line}")
              ([ ''cp "lib${libName}.a" "$out/lib/"'' ]
                ++ lib.optional shared (
                  if isWindows
                  then ''cp "lib${libName}.dll" "$out/bin/" && cp "lib${libName}.dll.a" "$out/lib/"''
                  else ''
                    cp "${soReal}" "$out/lib/"
                    ln -sf "${soReal}" "$out/lib/${soMajorLink}"
                    ln -sf "${soReal}" "$out/lib/${soDevLink}"
                  ''
                )
                ++ map (h: ''cp "${h}" "$out/include/"'') headers) + ''
              runHook postInstall
            '';

            meta.description = "${pname} (${libName}) for ${stdenv.hostPlatform.system}";
          }) { };

      # =======================================================================
      # Two libraries, one depending on the other.
      # =======================================================================
      mkFor = name: target:
        let
          libadd = mkLib target {
            pname = "libadd";
            src = ./src;
            sources = [ "add.c" ];
            headers = [ "add.h" ];
            libName = "add";
          };

          # libmul DEPENDS ON libadd: `deps` is an ordinary Nix dependency list,
          # `linkLibs` is how it is linked.
          libmul = mkLib target {
            pname = "libmul";
            src = ./src;
            sources = [ "mul.c" ];
            headers = [ "mul.h" ];
            libName = "mul";
            deps = [ libadd ];
            linkLibs = [ "add" ];
          };
        in
        {
          "${name}-libadd" = libadd;
          "${name}-libmul" = libmul;
        };

    in
    {
      packages.${localSystem} =
        mkFor "linux" targets.linux
        // mkFor "windows" targets.windows
        // { default = (mkFor "linux" targets.linux).linux-libmul; };

      inherit targets;
    };
}
