{
  description = "Chapter 36 — customizing nixpkgs: overlays, override, overrideAttrs, clang";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # 1. An overlay: add packages to a package set.
      # =======================================================================
      # An overlay is `final: prev: { ... }`.  `final` is the set being built
      # (so `final.callPackage` sees the overlay's own additions), `prev` is the
      # set before the overlay.
      overlay = final: prev: {
        libadd = final.callPackage ./src/libadd { };
        libmul = final.callPackage ./src/libmul { };
      };

      myPkgs = pkgs.extend overlay;

      # =======================================================================
      # 2. The plain packages, from the extended set.
      # =======================================================================
      libadd = myPkgs.libadd;
      libmul = myPkgs.libmul;

      # =======================================================================
      # 3. `override` — change a *function argument* of the package.
      # =======================================================================
      # `libadd` is `{ stdenv, optLevel ? "-O2" }: ...`, so `.override` can
      # change `optLevel`.  This is the safe, intended way to tweak a package.
      libadd-o0 = libadd.override { optLevel = "-O0"; };

      # =======================================================================
      # 4. `overrideAttrs` — change the derivation itself.
      # =======================================================================
      # Here we add a compile-time define and a new symbol, without touching the
      # package definition.
      libadd-extra = libadd.overrideAttrs (old: {
        pname = "libadd-extra";
        buildPhase = old.buildPhase + ''
          $CC -DLIBADD_EXTRA -c add.c -o add_extra.o
          $AR rcs libadd.a add.o add_extra.o
        '';
      });

      # =======================================================================
      # 5. A different compiler — clangStdenv (or `overrideCC`).
      # =======================================================================
      libadd-clang = pkgs.clangStdenv.callPackage ./src/libadd { };
    in
    {
      packages.${system} = {
        inherit libadd libmul libadd-o0 libadd-extra libadd-clang;
        default = libmul;
      };

      # The overlay itself, so it can be reused:
      #   nix eval .#overlay
      inherit overlay;
    };
}
