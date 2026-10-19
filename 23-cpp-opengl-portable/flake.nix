{
  description = "Chapter 23 — a C++ SDL3 + OpenGL app as a portable sharun + uruntime bundle (musl-friendly)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # 1. The application (C++17, SDL3, OpenGL 3.3, libepoxy).
      # =======================================================================
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
        # On NixOS (and in the sandbox) a GL app must be told where Mesa's glvnd
        # vendor libraries and DRI drivers are -- exactly what nixGL normally
        # does.  The bundle sets the same variables in its `.env` (section 3),
        # pointing into its own lib/ directory.
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

      # =======================================================================
      # 2. Pinned sharun launcher and uruntime AppImage runtime.
      # =======================================================================
      sharun = pkgs.fetchurl {
        url = "https://github.com/pkgforge-dev/Anylinux-sharun/releases/download/3.5.1/sharun-x86_64";
        hash = "sha256-XbkqdJL4sb75wrplM0ZDaot8xBMSZxWlCZPKBdl0ZbQ=";
      };
      appimageRuntime = pkgs.fetchurl {
        url = "https://github.com/VHSgunzo/uruntime/releases/download/v0.8.1/uruntime-appimage-squashfs-lite-x86_64";
        hash = "sha256-MsYCShT/N1dJ7jvtMzDBWGpt0r/t27186swFOuwrJ6M=";
      };

      # =======================================================================
      # 3. The portable bundle.
      # =======================================================================
      # Unlike chapter 18, this bundle SHIPS a GL implementation (Mesa's
      # llvmpipe software renderer).  That is what makes it work on a musl
      # system: the host's Mesa is built against musl and cannot be loaded into
      # our glibc process, so we bring our own.
      mkPortable = { name, mainProgram ? name, isTerminal ? true, checkCommand ? "" }:
        let
          desktopFile = pkgs.writeText "${name}.desktop" ''
            [Desktop Entry]
            Type=Application
            Name=${name}
            Exec=${mainProgram}
            Icon=${name}
            Terminal=${if isTerminal then "true" else "false"}
            Categories=Development;
          '';
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable";
          version = "1";
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          dontFixup = true;

          nativeBuildInputs = with pkgs; [
            bash coreutils findutils gnused gnugrep patchelf glibc.bin zstd
          ];

          installPhase = ''
            set -eu
            bin="${app}/bin/${mainProgram}"
            mkdir -p "$out/bin" "$out/shared/bin" "$out/lib" \
                     "$out/lib/dri" "$out/lib/glvnd/egl_vendor.d"

            # real ELF + launcher + hardlinks
            cp -L "$bin" "$out/shared/bin/${mainProgram}"
            cp -L ${sharun} "$out/sharun"
            chmod +x "$out/sharun"
            ln "$out/sharun" "$out/AppRun"
            ln "$out/sharun" "$out/bin/${mainProgram}"

            # the complete glibc (loader, libc, libstdc++ comes from ldd below)
            cp -L ${pkgs.glibc}/lib/*.so* "$out/lib/"
            chmod -R u+w "$out/lib"

            # glvnd entry points (dlopened by SDL/epoxy, so absent from ldd)
            for f in libGL.so.1 libGLX.so.0 libEGL.so.1 libGLdispatch.so.0 libOpenGL.so.0; do
              cp -L ${pkgs.libGL}/lib/"$f"* "$out/lib/" 2>/dev/null || true
            done

            # Mesa vendor libraries + the software DRI drivers
            cp -L ${pkgs.mesa}/lib/libGLX_mesa.so.0* "$out/lib/"
            cp -L ${pkgs.mesa}/lib/libEGL_mesa.so.0* "$out/lib/"
            cp -L ${pkgs.mesa}/lib/libgallium-*.so   "$out/lib/"
            cp -L ${pkgs.mesa}/lib/dri/*.so          "$out/lib/dri/" 2>/dev/null || true

            # glvnd vendor manifest, rewritten to a bare soname so the bundle
            # stays relocatable (glvnd then dlopens it via the loader path).
            sed 's#"[^"]*libEGL_mesa.so.0"#"libEGL_mesa.so.0"#' \
              ${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json \
              > "$out/lib/glvnd/egl_vendor.d/50_mesa.json"

            # copy the DT_NEEDED closure of the app AND the Mesa seeds
            for seed in "$out/shared/bin/${mainProgram}" \
                        "$out/lib/libgallium-"*.so \
                        "$out/lib/libGLX_mesa.so.0" \
                        "$out/lib/libEGL_mesa.so.0" \
                        "$out/lib/libGL.so.1"; do
              [ -e "$seed" ] || continue
              ${pkgs.glibc.bin}/bin/ldd "$seed" 2>/dev/null \
                | grep -o '/nix/store/[^ ]*' || true
            done | sort -u | while IFS= read -r l; do
              cp -a --no-preserve=mode,ownership "$l" "$out/lib/$(basename "$l")"
            done

            test -f "$out/lib/ld-linux-x86-64.so.2" || {
              echo "missing dynamic linker" >&2; exit 1; }

            # Drop store RPATHs.
            chmod -R u+w "$out/lib" "$out/shared/bin"
            for f in "$out"/lib/*.so* "$out"/lib/dri/*.so "$out/shared/bin/${mainProgram}"; do
              [ -f "$f" ] || continue
              [ -L "$f" ] && continue
              case "$(basename "$f")" in ld-*) continue ;; esac
              patchelf --remove-rpath "$f" || true
            done

            # Runtime environment: point Mesa's loader at the bundled drivers.
            # (A quoted heredoc keeps $APPDIR literal; sharun expands it.)
            cat > "$out/.env" <<'EOF'
            LIBGL_ALWAYS_SOFTWARE=1
            GALLIUM_DRIVER=llvmpipe
            LIBGL_DRIVERS_PATH=$APPDIR/lib/dri
            __GLX_VENDOR_LIBRARY_NAME=mesa
            __EGL_VENDOR_LIBRARY_FILENAMES=$APPDIR/lib/glvnd/egl_vendor.d/50_mesa.json
            EOF

            cp ${desktopFile} "$out/${name}.desktop"
            echo "bundled $(find "$out/lib" -maxdepth 1 -type f | wc -l) libraries"
            du -sh "$out"
          '';

          doInstallCheck = checkCommand != "";
          installCheckPhase = ''
            runHook preInstallCheck
            ${checkCommand}
            runHook postInstallCheck
          '';
        };

      portable = mkPortable {
        name = "sdl3-triangle";
        isTerminal = true;
        # Smoke test through the BUNDLED loader, with the bundled Mesa paths.
        checkCommand = ''
          export LIBGL_ALWAYS_SOFTWARE=1
          export GALLIUM_DRIVER=llvmpipe
          export LIBGL_DRIVERS_PATH="$out/lib/dri"
          export __GLX_VENDOR_LIBRARY_NAME=mesa
          export __EGL_VENDOR_LIBRARY_FILENAMES="$out/lib/glvnd/egl_vendor.d/50_mesa.json"
          export SDL_VIDEODRIVER=x11
          output="$(xvfb-run -a -s "-screen 0 1024x768x24" \
            "$out/lib/ld-linux-x86-64.so.2" --library-path "$out/lib" \
            "$out/shared/bin/sdl3-triangle" --seconds 1)"
          echo "$output"
          echo "$output" | grep -q 'rendered'
        '';
      };

      mkTarball = { name, appdir }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable-tar";
          version = "1";
          dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
          nativeBuildInputs = [ pkgs.zstd pkgs.coreutils ];
          installPhase = ''
            set -eu
            mkdir -p "$out"
            cp -r ${appdir} "./${name}-portable"
            chmod -R u+w "./${name}-portable"
            tar --zstd -cf "$out/${name}-portable-x86_64.tar.zst" "${name}-portable"
          '';
        };

      mkAppImage = { name, appdir }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable-appimage";
          version = "1";
          dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
          nativeBuildInputs = [ pkgs.squashfsTools pkgs.coreutils ];
          installPhase = ''
            set -eu
            mkdir -p "$out"
            cp -r ${appdir} ./AppDir
            chmod -R u+w ./AppDir
            mksquashfs ./AppDir app.squashfs -root-owned -noappend -comp zstd -quiet
            cp ${appimageRuntime} ./runtime
            chmod u+w ./runtime
            sed -i 's/URUNTIME_EXTRACT=[0-9]/URUNTIME_EXTRACT=2/' ./runtime
            grep -a -q 'URUNTIME_EXTRACT=2' ./runtime
            cat ./runtime app.squashfs > "$out/${name}-x86_64.AppImage"
            chmod +x "$out/${name}-x86_64.AppImage"
          '';
        };
    in
    {
      packages.${system} = {
        inherit app sharun;
        portable = portable;
        portable-tar = mkTarball { name = "sdl3-triangle"; appdir = portable; };
        portable-appimage = mkAppImage { name = "sdl3-triangle"; appdir = portable; };
        default = portable;
      };
    };
}
