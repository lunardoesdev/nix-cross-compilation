{
  description = "Chapter 16 — target: Android arm64-v8a via the NDK (aarch64-android-prebuilt)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";

      # The NDK (and therefore aarch64-android-prebuilt) is UNFREE, so it must
      # be allowed explicitly.
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # -----------------------------------------------------------------------
      # The Android target: the prebuilt NDK stdenv.
      #
      # `aarch64-android-prebuilt` ships a ready-made NDK (clang + a reduced
      # bionic sysroot), so nothing is built from source.  The alternative,
      # `aarch64-android`, builds the whole LLVM/bionic toolchain from source --
      # avoid it (see chapter 21's rule).
      #
      # Output is a native arm64 ELF (bionic libc), NOT an APK.
      # -----------------------------------------------------------------------
      target = pkgs.pkgsCross.aarch64-android-prebuilt;

      # Android convention is an *unversioned* `libfoo.so`.
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
              $CC -shared -o "lib${libName}.so" obj/*.o ${depFlags}
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib" "$out/include"
              cp "lib${libName}.a"  "$out/lib/"
              cp "lib${libName}.so" "$out/lib/"
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

      # A small arm64 executable.  It cannot run on the build machine; it is
      # meant to be pushed to a device together with the two .so files.
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
        }) { };
    in
    {
      packages.${system} = {
        inherit libadd libmul uselib2;
        default = uselib2;
      };
    };
}
