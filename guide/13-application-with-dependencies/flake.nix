{
  description = "Chapter 13 — an application with dependencies, built from the same recipes";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      localSystem = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit localSystem;
        config.allowUnfree = true;
      };

      targets = {
        linux = pkgs;
        windows = pkgs.pkgsCross.mingwW64;
      };

      # -----------------------------------------------------------------------
      # The library builder (identical to chapter 12).
      # -----------------------------------------------------------------------
      mkLib =
        target:
        { pname, version ? "1.0.0", src, sources, headers ? [], libName
        , deps ? [], linkLibs ? [], shared ? true }:
        target.callPackage ({ lib, stdenv }:
          let
            isWindows = stdenv.hostPlatform.isWindows;
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
          }) { };

      # -----------------------------------------------------------------------
      # The application builder.
      # -----------------------------------------------------------------------
      # `deps` are ordinary Nix dependencies.  The link order matters for static
      # archives: libmul before libadd (mul references add).
      mkApp =
        target:
        { pname, version ? "1.0.0", src, sources ? [ "main.c" ], binName ? pname
        , deps ? [], linkLibs ? [], extraCflags ? "", extraLdflags ? ""
        , checkCommand ? "" }:
        target.callPackage ({ lib, stdenv }:
          let
            isWindows = stdenv.hostPlatform.isWindows;
            exeExt = if isWindows then ".exe" else "";
            includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
            libraryFlags = lib.concatMapStringsSep " " (d: "-L${d}/lib") deps;
            linkFlags = lib.concatMapStringsSep " " (l: "-l${l}") linkLibs;
            canRun = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
            runCheck = canRun && checkCommand != "";
          in
          stdenv.mkDerivation {
            inherit pname version src;
            buildInputs = deps;
            strictDeps = true;
            dontConfigure = true;
            enableParallelBuilding = false;
            buildPhase = ''
              runHook preBuild
              $CC -O2 -Wall -Wextra ${extraCflags} ${includeFlags} \
                ${lib.concatStringsSep " " sources} \
                -o "${binName}${exeExt}" \
                ${libraryFlags} ${linkFlags} ${extraLdflags}
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin"
              cp "${binName}${exeExt}" "$out/bin/"
              runHook postInstall
            '';
            doCheck = runCheck;
            checkPhase = lib.optionalString runCheck ''
              runHook preCheck
              ${checkCommand}
              runHook postCheck
            '';
            meta.mainProgram = "${binName}${exeExt}";
          }) { };

      # -----------------------------------------------------------------------
      # Instantiate libraries + application per target.
      # -----------------------------------------------------------------------
      mkFor = name: target:
        let
          libadd = mkLib target {
            pname = "libadd"; src = ./src;
            sources = [ "add.c" ]; headers = [ "add.h" ]; libName = "add";
          };
          libmul = mkLib target {
            pname = "libmul"; src = ./src;
            sources = [ "mul.c" ]; headers = [ "mul.h" ]; libName = "mul";
            deps = [ libadd ]; linkLibs = [ "add" ];
          };
          uselib2 = mkApp target {
            pname = "uselib2"; src = ./src; sources = [ "main.c" ];
            deps = [ libmul libadd ];
            linkLibs = [ "mul" "add" ];
            checkCommand = ''
              output="$(./uselib2)"
              echo "$output"
              echo "$output" | grep -q 'mul(6, 7) = 42'
            '';
          };
        in
        {
          "${name}-libadd" = libadd;
          "${name}-libmul" = libmul;
          "${name}-uselib2" = uselib2;
        };

    in
    {
      packages.${localSystem} =
        mkFor "linux" targets.linux
        // mkFor "windows" targets.windows
        // { default = (mkFor "linux" targets.linux).linux-uselib2; };

      inherit targets;
    };
}
