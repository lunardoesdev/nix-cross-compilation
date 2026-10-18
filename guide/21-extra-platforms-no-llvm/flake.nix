{
  description = "Chapter 21 — extra platforms that need no LLVM build (musl, riscv64, AVR, WASI, FreeBSD, Zig)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # =======================================================================
      # The rule: prefer targets whose toolchain is in the binary cache.
      # =======================================================================
      # Each entry below uses a toolchain nixpkgs already ships (GNU gcc/clang or
      # a prebuilt Zig), so nothing as large as LLVM or a whole gcc is built
      # from source.  If a target needed that, it would be the wrong target to
      # add casually -- see the note on `aarch64-android` in chapter 16.
      targets = {
        musl-static       = pkgs.pkgsCross.musl64;            # x86_64-linux-musl
        riscv64-linux     = pkgs.pkgsCross.riscv64;           # riscv64-linux-gnu
        avr               = pkgs.pkgsCross.avr;               # avr-none (8-bit MCUs)
        riscv64-embedded  = pkgs.pkgsCross.riscv64-embedded;  # riscv64-none (bare metal)
        wasi              = pkgs.pkgsCross.wasi32;            # wasm32-wasip1
        freebsd           = pkgs.pkgsCross.x86_64-freebsd;    # x86_64-freebsd
      };

      # Static archives work on every one of these (bare-metal and WASI have no
      # shared objects; musl/riscv64/freebsd we keep static for portability).
      mkLib = target: { pname, version ? "1.0.0", src, sources, headers ? []
                      , libName, deps ? [], linkLibs ? [] }:
        target.callPackage ({ lib, stdenv }:
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
        in
        {
          "${name}-libadd" = libadd;
          "${name}-libmul" = libmul;
        };

      # =======================================================================
      # Zig: one prebuilt binary that can target many platforms.
      # =======================================================================
      # `zig cc` bundles its own clang/LLVM *as a prebuilt binary*, so using it
      # does not build LLVM.  This makes Zig a cheap way to reach platforms you
      # do not otherwise have a toolchain for.
      mkZig = zigTarget: pkgs.stdenv.mkDerivation {
        pname = "libadd-zig-${builtins.replaceStrings [ "-" ] [ "_" ] zigTarget}";
        version = "1.0.0";
        src = ./src;
        nativeBuildInputs = [ pkgs.zig ];
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          export HOME="$TMPDIR"
          mkdir -p obj
          zig cc -target ${zigTarget} -O2 -c add.c -o obj/add.o
          zig ar rcs libadd.a obj/add.o
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p "$out/lib" "$out/include"
          cp libadd.a "$out/lib/"
          cp add.h    "$out/include/"
          runHook postInstall
        '';
      };
    in
    {
      packages.${system} =
        mkFor "musl-static" targets.musl-static
        // mkFor "riscv64-linux" targets.riscv64-linux
        // mkFor "avr" targets.avr
        // mkFor "riscv64-embedded" targets.riscv64-embedded
        // mkFor "wasi" targets.wasi
        // mkFor "freebsd" targets.freebsd
        // {
          zig-linux-musl    = mkZig "x86_64-linux-musl";
          zig-windows       = mkZig "x86_64-windows-gnu";
          zig-macos         = mkZig "x86_64-macos";
          zig-freestanding  = mkZig "x86_64-freestanding";
          default = (mkFor "musl-static" targets.musl-static)."musl-static-libadd";
        };

      inherit targets;
    };
}
