{
  description = "Chapter 31 — cross-compiling with build systems: a Meson cross file generated from the Nix stdenv";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      lib = pkgs.lib;

      mesonTools = with pkgs; [ meson ninja pkg-config ];

      # =======================================================================
      # Generate a Meson cross file from a (cross) stdenv.
      # =======================================================================
      # A Meson cross file needs the tool names and the host machine.  Every one
      # of those facts is already in the stdenv, so we do not hard-code a triple:
      #
      #   * the tool names carry the target prefix (`x86_64-w64-mingw32-cc`, ...)
      #     and are on PATH via the cc/binutils wrappers;
      #   * the machine description is `stdenv.hostPlatform`.
      mkCrossFile = stdenv: pkgs.writeText "meson-cross.ini" ''
        [binaries]
        c     = '${stdenv.cc.targetPrefix}cc'
        cpp   = '${stdenv.cc.targetPrefix}c++'
        ar    = '${stdenv.cc.targetPrefix}ar'
        strip = '${stdenv.cc.targetPrefix}strip'

        [host_machine]
        system     = '${if stdenv.hostPlatform.isWindows then "windows"
                        else if stdenv.hostPlatform.isAndroid then "android"
                        else "linux"}'
        cpu_family = '${stdenv.hostPlatform.parsed.cpu.name}'
        cpu        = '${stdenv.hostPlatform.parsed.cpu.name}'
        endian     = 'little'
      '';

      # =======================================================================
      # Build the same three Meson projects for any target.
      # =======================================================================
      mkFor = name: target:
        let
          stdenv = target.stdenv;
          crossFile = mkCrossFile stdenv;
          common = {
            nativeBuildInputs = mesonTools;
            mesonFlags = [ "--cross-file=${crossFile}" ];
            strictDeps = true;
            enableParallelBuilding = false;
            doCheck = false;   # cross binaries cannot run on the build machine
          };

          libadd = stdenv.mkDerivation (common // {
            pname = "libadd";
            version = "1.0.0";
            src = ./src/libadd;
          });

          libmul = stdenv.mkDerivation (common // {
            pname = "libmul";
            version = "1.0.0";
            src = ./src/libmul;
            buildInputs = [ libadd ];
            propagatedBuildInputs = [ libadd ];
          });

          uselib2 = stdenv.mkDerivation (common // {
            pname = "uselib2";
            version = "1.0.0";
            src = ./src/uselib2;
            buildInputs = [ libmul ];
          });
        in
        {
          "${name}-libadd" = libadd;
          "${name}-libmul" = libmul;
          "${name}-uselib2" = uselib2;
        };
    in
    {
      packages.${system} =
        mkFor "windows" pkgs.pkgsCross.mingwW64
        // mkFor "android" pkgs.pkgsCross.aarch64-android-prebuilt
        // {
          # The cross files themselves, for inspection:
          crossFiles = {
            windows = mkCrossFile pkgs.pkgsCross.mingwW64.stdenv;
            android = mkCrossFile pkgs.pkgsCross.aarch64-android-prebuilt.stdenv;
          };
          default = (mkFor "windows" pkgs.pkgsCross.mingwW64)."windows-uselib2";
        };

      inherit mkCrossFile;
    };
}
