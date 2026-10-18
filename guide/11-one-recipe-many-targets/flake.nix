{
  description = "Chapter 11 — one recipe, many targets: a target table and a generic C library builder";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      localSystem = "x86_64-linux";

      # allowUnfree is needed later for the Android NDK; harmless here.
      pkgs = import nixpkgs {
        inherit localSystem;
        config.allowUnfree = true;
      };

      # =======================================================================
      # 1. The target table
      # =======================================================================
      # Each entry is a COMPLETE nixpkgs package set whose `stdenv` targets that
      # platform.  That is the whole cross-compilation story: a package written
      # once can be instantiated through the package set of the platform we
      # want, and Nix resolves the compiler, libc and every dependency from it.
      #
      # Adding a platform is one line.  Chapters 14–17 add Windows (mingw),
      # Android (NDK) and Emscripten; this chapter keeps two so the pattern is
      # easy to read.
      targets = {
        # native Linux x86_64 (glibc)
        linux = pkgs;

        # Windows x86_64 via mingw-w64
        windows = pkgs.pkgsCross.mingwW64;
      };

      # =======================================================================
      # 2. The generic builder
      # =======================================================================
      # `target.callPackage` resolves `lib` and `stdenv` from the target package
      # set and passes them to this function.  Everything else is closed over.
      # The SAME code therefore builds for every row of the table.
      mkLib =
        target:
        { pname
        , version ? "1.0.0"
        , src
        , sources            # e.g. [ "add.c" ]
        , headers ? []       # e.g. [ "add.h" ]
        , libName            # e.g. "add" -> libadd.a
        , deps ? []          # other libraries (Nix dependencies)
        , linkLibs ? []      # -l flags for deps
        }:
        target.callPackage ({ lib, stdenv }:
          let
            isWindows = stdenv.hostPlatform.isWindows;

            # Dependencies are searched with -I/-L; the cc-wrapper would inject
            # these for `buildInputs`, but we pass them explicitly here because
            # the builder must also work under emcc (chapter 17).
            includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
            depFlags =
              lib.concatMapStringsSep " " (d: "-L${d}/lib") deps
              + " " + lib.concatMapStringsSep " " (l: "-l${l}") linkLibs;
          in
          stdenv.mkDerivation {
            inherit pname version src;

            buildInputs = deps;
            strictDeps = true;
            dontConfigure = true;
            doCheck = false;

            # The single-core rule.
            enableParallelBuilding = false;

            buildPhase = ''
              runHook preBuild
              mkdir -p obj
              for f in ${lib.concatStringsSep " " sources}; do
                $CC -O2 -fPIC -Wall -Wextra ${includeFlags} \
                  -c "$f" -o "obj/$(basename "$f" .c).o"
              done
              $AR rcs "lib${libName}.a" obj/*.o
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib" "$out/include"
              cp "lib${libName}.a" "$out/lib/"
            '' + lib.concatMapStringsSep "\n"
              (h: ''  cp "${h}" "$out/include/"'')
              headers + ''
              runHook postInstall
            '';

            meta = {
              description = "${pname} (${libName}) for ${stdenv.hostPlatform.system}";
              inherit (stdenv.hostPlatform) system;
            };
          }) { };

      # =======================================================================
      # 3. Instantiate the SAME recipe for every target.
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
        in
        { "${name}-libadd" = libadd; };

    in
    {
      packages.${localSystem} =
        mkFor "linux" targets.linux
        // mkFor "windows" targets.windows
        // { default = (mkFor "linux" targets.linux).linux-libadd; };

      # The table itself, for inspection:
      #   nix eval .#targets.windows.stdenv.hostPlatform.system
      inherit targets;
    };
}
