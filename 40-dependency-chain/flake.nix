{
  description = "Chapter 40 — a realistic dependency chain: zlib -> libpng -> app, for Linux and Windows";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # The app, built for one target package set.
      # =======================================================================
      # `buildInputs = [ target.libpng ]` is enough: nixpkgs' libpng propagates
      # zlib, and its pkg-config file carries the flags.  There is no -I/-L/-l
      # in the build command.
      mkApp = target: exeExt: target.stdenv.mkDerivation {
        pname = "png-demo";
        version = "1.0.0";
        src = ./src;

        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ target.libpng ];

        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild
          # We call zlib directly (zlibVersion), and libpng.pc lists zlib only as
          # Requires.private -- so a direct zlib user must ask pkg-config for it.
          $CC app.c -o png-demo${exeExt} $(pkg-config --cflags --libs libpng zlib)
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin"
          cp png-demo${exeExt} "$out/bin/"
          runHook postInstall
        '';

        # The Linux build can be run; the Windows one cannot.
        doCheck = target.stdenv.buildPlatform.canExecute target.stdenv.hostPlatform;
        checkPhase = ''
          runHook preCheck
          output="$(./png-demo${exeExt})"
          echo "$output"
          echo "$output" | grep -q 'round-trip 2x2 ok'
          runHook postCheck
        '';

        meta.description = "libpng + zlib round-trip demo for ${target.stdenv.hostPlatform.system}";
      };

      linuxApp = mkApp pkgs "";
      windowsApp = mkApp pkgs.pkgsCross.mingwW64 ".exe";
    in
    {
      packages.${system} = {
        linux-png-demo = linuxApp;
        windows-png-demo = windowsApp;
        default = linuxApp;
      };

      # Show the chain the build inputs resolve to.
      chain = {
        native = {
          libpng = pkgs.libpng.version;
          zlib = pkgs.zlib.version;
        };
        windows = {
          libpng = pkgs.pkgsCross.mingwW64.libpng.version;
          zlib = pkgs.pkgsCross.mingwW64.zlib.version;
        };
      };
    };
}
