{
  description = "Chapter 23 — a C++ SDL3 + OpenGL app as a portable sharun + uruntime bundle (musl-friendly)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # 1. The application.
      # =======================================================================
      # C++17, SDL3 for the window/GL context, libepoxy to load GL functions.
      # libGL and mesa are build inputs so that the build-time check (and the
      # native binary) can find a GL implementation; the *bundle* gets its own
      # copies, see section 3.
      app = pkgs.stdenv.mkDerivation {
        pname = "sdl3-opengl-triangle";
        version = "1.0.0";
        src = ./src;

        nativeBuildInputs = [ pkgs.pkg-config pkgs.xvfb-run ];
        buildInputs = [ pkgs.sdl3 pkgs.libepoxy pkgs.libGL pkgs.mesa ];

        strictDeps = true;
        dontConfigure = true;
        enableParallelBuilding = false;

        buildPhase = ''
          runHook preBuild
          $CXX -std=c++17 -O2 -Wall -Wextra \
            -I${lib.getDev pkgs.sdl3}/include \
            -I${lib.getDev pkgs.libepoxy}/include \
            main.cpp -o sdl3-triangle \
            -L${lib.getLib pkgs.sdl3}/lib -lSDL3 \
            -L${lib.getLib pkgs.libepoxy}/lib -lepoxy
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin"
          cp sdl3-triangle "$out/bin/"
          runHook postInstall
        '';

        # Headless check: Xvfb + Mesa's llvmpipe software rasteriser.
        #
        # On NixOS (and in the sandbox) a GL app must be told where Mesa's
        # glvnd vendor libraries and DRI drivers are -- this is exactly the
        # job nixGL normally does.  The bundle sets the same variables in its
        # `.env` (section 4), pointing into its own lib/ directory.
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          export LIBGL_ALWAYS_SOFTWARE=1
          export GALLIUM_DRIVER=llvmpipe
          export LIBGL_DRIVERS_PATH="${pkgs.mesa}/lib/dri"
          export __GLX_VENDOR_LIBRARY_NAME=mesa
          export __EGL_VENDOR_LIBRARY_FILENAMES="${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
          export LD_LIBRARY_PATH="${pkgs.mesa}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          export SDL_VIDEODRIVER=x11
          output="$(xvfb-run -a -s "-screen 0 1024x768x24" \
            ./sdl3-triangle --seconds 1)"
          echo "$output"
          echo "$output" | grep -q 'OpenGL'
          echo "$output" | grep -q 'rendered'
          runHook postCheck
        '';

        meta = {
          description = "C++ SDL3 + OpenGL 3.3 triangle";
          mainProgram = "sdl3-triangle";
          platforms = [ "x86_64-linux" ];
        };
      };
    in
    {
      packages.${system} = {
        inherit app;
        default = app;
      };
    };
}
