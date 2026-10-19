{
  description = "Chapter 22 — devkitPro toolchains via devkitNix: GBA/NDS/3DS, Switch and GameCube/Wii/WiiU";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

    # devkitNix packages the official devkitPro Docker images as Nix
    # derivations and exposes stdenvs for them.
    devkitNix.url = "github:bandithedoge/devkitNix";

    # Use OUR pinned nixpkgs for devkitNix too, so everything is one universe.
    devkitNix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, devkitNix }:
    let
      system = "x86_64-linux";

      # devkitNix provides an overlay adding `pkgs.devkitNix.*`.
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ devkitNix.overlays.default ];
      };

      # =======================================================================
      # The three devkitPro toolchains.
      # =======================================================================
      # Each is a complete toolchain (compiler + binutils + libc/headers + all
      # the console libraries and portlibs).  devkitNix also provides matching
      # stdenvs, but the important thing here is the driver path, because these
      # stdenvs do NOT set $CC -- you call the toolchain's gcc yourself.
      #
      #   devkitARM : arm-none-eabi   (GBA, NDS, 3DS)
      #   devkitA64 : aarch64-none-elf (Nintendo Switch)
      #   devkitPPC : powerpc-eabi    (GameCube, Wii, WiiU)
      arm = pkgs.devkitNix.devkitARM;
      a64 = pkgs.devkitNix.devkitA64;
      ppc = pkgs.devkitNix.devkitPPC;

      armGcc = "${arm}/opt/devkitpro/devkitARM/bin/arm-none-eabi-gcc";
      armAr  = "${arm}/opt/devkitpro/devkitARM/bin/arm-none-eabi-ar";
      a64Gcc = "${a64}/opt/devkitpro/devkitA64/bin/aarch64-none-elf-gcc";
      a64Ar  = "${a64}/opt/devkitpro/devkitA64/bin/aarch64-none-elf-ar";
      ppcGcc = "${ppc}/opt/devkitpro/devkitPPC/bin/powerpc-eabi-gcc";
      ppcAr  = "${ppc}/opt/devkitpro/devkitPPC/bin/powerpc-eabi-ar";

      # =======================================================================
      # Build the two libraries with an explicit toolchain.
      # =======================================================================
      # Bare-metal console targets: static archives, no shared objects.
      mkLib = { stdenv, gcc, ar, pname, version ? "1.0.0", src, sources
              , headers ? [], libName }:
        stdenv.mkDerivation {
          inherit pname version src;
          dontConfigure = true;
          enableParallelBuilding = false;
          buildPhase = ''
            runHook preBuild
            mkdir -p obj
            for f in ${pkgs.lib.concatStringsSep " " sources}; do
              ${gcc} -O2 -Wall -Wextra -c "$f" -o "obj/$(basename "$f" .c).o"
            done
            ${ar} rcs "lib${libName}.a" obj/*.o
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

      # One pair of libraries per toolchain.
      mkFor = name: stdenv: gcc: ar:
        let
          libadd = mkLib {
            inherit stdenv gcc ar;
            pname = "libadd"; src = ./src;
            sources = [ "add.c" ]; headers = [ "add.h" ]; libName = "add";
          };
          libmul = mkLib {
            inherit stdenv gcc ar;
            pname = "libmul"; src = ./src;
            sources = [ "mul.c" ]; headers = [ "mul.h" ]; libName = "mul";
          };
        in
        {
          "${name}-libadd" = libadd;
          "${name}-libmul" = libmul;
        };
    in
    {
      packages.${system} =
        mkFor "devkitarm" pkgs.devkitNix.stdenvARM armGcc armAr
        // mkFor "devkita64" pkgs.devkitNix.stdenvA64 a64Gcc a64Ar
        // mkFor "devkitppc" pkgs.devkitNix.stdenvPPC ppcGcc ppcAr
        // {
          # convenience: the toolchains themselves
          inherit (pkgs.devkitNix) devkitARM devkitA64 devkitPPC;
          default = (mkFor "devkitarm" pkgs.devkitNix.stdenvARM armGcc armAr).devkitarm-libmul;
        };
    };
}
