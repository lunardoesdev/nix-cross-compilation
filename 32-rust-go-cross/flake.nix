{
  description = "Chapter 32 — cross-compiling Rust and Go";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # Rust — cross via a target `rustPlatform`.
      # =======================================================================
      # `pkgsCross.<target>.rustPlatform` is a Rust toolchain that emits code for
      # that target (its `cargo` is even named after the triple, e.g.
      # `x86_64-unknown-linux-musl-cargo`).  `buildRustPackage` then builds the
      # crate for that target with no flags written by hand.
      mkRust = targetPkgs: name: targetPkgs.rustPlatform.buildRustPackage {
        pname = "rusthello";
        version = "0.1.0";
        src = ./src/rusthello;
        cargoLock.lockFile = ./src/rusthello/Cargo.lock;
        strictDeps = true;
        enableParallelBuilding = false;
        # A Rust `targetPlatform` implies the target; no Cargo target flags.
        meta.description = "rusthello for ${name}";
      };

      rust-musl = mkRust pkgs.pkgsCross.musl64 "x86_64-linux-musl";
      rust-windows = mkRust pkgs.pkgsCross.mingwW64 "x86_64-windows";

      # =======================================================================
      # Go — cross via GOOS/GOARCH on the native toolchain.
      # =======================================================================
      # Pure Go needs no cross toolchain: the ordinary `go` command can emit code
      # for any GOOS/GOARCH.  `CGO_ENABLED=0` keeps it pure Go (no C toolchain).
      mkGo = { goos, goarch }: pkgs.buildGoModule {
        pname = "gohello";
        version = "0.1.0";
        src = ./src/gohello;
        vendorHash = null;          # no dependencies
        env = {
          GOOS = goos;
          GOARCH = goarch;
          CGO_ENABLED = "0";
        };
        strictDeps = true;
        enableParallelBuilding = false;
        meta.description = "gohello for ${goos}/${goarch}";
      };

      go-windows = mkGo { goos = "windows"; goarch = "amd64"; };
      go-linux-arm64 = mkGo { goos = "linux"; goarch = "arm64"; };
    in
    {
      packages.${system} = {
        inherit rust-musl rust-windows go-windows go-linux-arm64;
        default = rust-musl;
      };
    };
}
