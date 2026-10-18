{
  description = "Chapter 09 — replacing libc: newlib, newlib-nano, picolibc, freestanding, or your own";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      localSystem = "x86_64-linux";
      nativePkgs = import nixpkgs { inherit localSystem; };
      buildPlatform = nixpkgs.lib.systems.elaborate localSystem;

      # =======================================================================
      # libc is one field in `crossSystem`
      # =======================================================================
      # nixpkgs maps `crossSystem.libc` to a package that must provide:
      #
      #   $out/include/   the headers
      #   $out/lib/       crt1.o, libc.a (and/or libc.so)
      #
      # and wires it into the compiler wrapper's flag files:
      #
      #   libc-cflags       -> -idirafter <libc>/<target>/include
      #   libc-crt1-cflags  -> -B <libc>/<target>/lib
      #   libc-ldflags      -> linker flags for the C library
      #
      # Changing the string changes which package is used.  `null` means
      # "freestanding": no libc flags at all.
      mkVariant = crossSystem:
        let
          targetPlatform = nixpkgs.lib.systems.elaborate crossSystem;
          targetPkgs = import nixpkgs { inherit localSystem crossSystem; };
          stdenv = nativePkgs.stdenv.override {
            inherit buildPlatform;
            hostPlatform = targetPlatform;
            targetPlatform = targetPlatform;
            cc = targetPkgs.buildPackages.gcc;   # already wrapped with this libc
            hasCC = true;
            extraBuildInputs = [ ];
            overrides = _: _: { };
            allowedRequisites = null;
          };
          libadd = stdenv.mkDerivation {
            pname = "libadd";
            version = "1.0.0";
            src = ./src;
            dontConfigure = true;
            enableParallelBuilding = false;
            buildPhase = ''
              runHook preBuild
              $CC -Os -c add.c -o add.o
              $AR rcs libadd.a add.o
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out/lib $out/include
              cp libadd.a $out/lib/
              cp add.h    $out/include/
              runHook postInstall
            '';
          };
        in
        {
          inherit stdenv libadd targetPkgs;
          cc = targetPkgs.buildPackages.gcc;
        };

      newlib       = mkVariant { config = "arm-none-eabi"; libc = "newlib"; };
      newlibNano   = mkVariant { config = "arm-none-eabi"; libc = "newlib-nano"; };
      picolibc     = mkVariant { config = "arm-none-eabi"; libc = "picolibc"; };
      freestanding = mkVariant { config = "arm-none-eabi"; libc = null; };
    in
    {
      packages.${localSystem} = {
        newlib-libadd       = newlib.libadd;
        newlib-nano-libadd  = newlibNano.libadd;
        picolibc-libadd     = picolibc.libadd;
        freestanding-libadd = freestanding.libadd;
        default = newlib.libadd;
      };

      # Inspect the wrappers, e.g.:
      #   nix eval --raw .#variants.picolibc.cc
      #   cat "$(nix eval --raw .#variants.picolibc.cc)/nix-support/libc-cflags"
      variants = {
        inherit newlib newlibNano picolibc freestanding;
      };
    };
}
