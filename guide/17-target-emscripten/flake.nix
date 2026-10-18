{
  description = "Chapter 17 — target: Emscripten / WebAssembly";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # -----------------------------------------------------------------------
      # Emscripten is not a stdenv here.
      #
      # nixpkgs' `emscriptenStdenv` wraps mkDerivation with `emconfigure`, which
      # is meant for autoconf projects.  Our packages are direct-compiler builds,
      # so we keep the normal stdenv and pass `emcc`/`emar` explicitly.  This is
      # still ordinary Nix dependency management: `emscripten` is a build input.
      # -----------------------------------------------------------------------
      emscripten = pkgs.emscripten;
      emcc = "${emscripten}/bin/emcc";
      emar = "${emscripten}/bin/emar";

      # emcc writes a cache; give it a writable HOME inside the sandbox.
      emscriptenEnv = ''
        export HOME="$TMPDIR"
        export EM_CACHE="$TMPDIR/emscripten-cache"
      '';

      # Emscripten output is static-only here.
      mkLib = { pname, version ? "1.0.0", src, sources, headers ? [], libName
              , deps ? [], linkLibs ? [] }:
        pkgs.stdenv.mkDerivation {
          inherit pname version src;
          nativeBuildInputs = [ emscripten ];
          strictDeps = true;
          dontConfigure = true;
          enableParallelBuilding = false;
          buildPhase = ''
            runHook preBuild
            ${emscriptenEnv}
            mkdir -p obj
            for f in ${pkgs.lib.concatStringsSep " " sources}; do
              ${emcc} -O2 -c "$f" -o "obj/$(basename "$f" .c).o" \
                ${pkgs.lib.concatMapStringsSep " " (d: "-I${d}/include") deps}
            done
            ${emar} rcs "lib${libName}.a" obj/*.o
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/lib" "$out/include"
            cp "lib${libName}.a" "$out/lib/"
            ${pkgs.lib.concatMapStringsSep "\n" (h: ''cp "${h}" "$out/include/"'') headers}
            runHook postInstall
          '';
        };

      libadd = mkLib {
        pname = "libadd"; src = ./src;
        sources = [ "add.c" ]; headers = [ "add.h" ]; libName = "add";
      };

      libmul = mkLib {
        pname = "libmul"; src = ./src;
        sources = [ "mul.c" ]; headers = [ "mul.h" ]; libName = "mul";
        deps = [ libadd ]; linkLibs = [ "add" ];
      };

      # Link the program into an .html + .js + .wasm trio.
      uselib2 = pkgs.stdenv.mkDerivation {
        pname = "uselib2-web";
        version = "1.0.0";
        src = ./src;
        nativeBuildInputs = [ emscripten ];
        strictDeps = true;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          ${emscriptenEnv}
          ${emcc} -O2 \
            -I${libmul}/include -I${libadd}/include \
            main.c \
            ${libmul}/lib/libmul.a ${libadd}/lib/libadd.a \
            -o uselib2.html \
            -sALLOW_MEMORY_GROWTH=1 \
            -sEXIT_RUNTIME=1
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin"
          cp uselib2.html uselib2.js uselib2.wasm "$out/bin/"
          runHook postInstall
        '';
      };
    in
    {
      packages.${system} = {
        inherit libadd libmul uselib2;
        default = uselib2;
      };
    };
}
