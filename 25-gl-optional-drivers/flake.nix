{
  description = "Chapter 25 — optional GL drivers: a host-driver bundle by default, plus a bundled-Mesa variant";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # 1. The application (same C++ SDL3 + OpenGL triangle as chapter 24).
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
          mkdir -p "$out/bin"; cp sdl3-triangle "$out/bin/"
          runHook postInstall
        '';
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
          export LIBGL_DRIVERS_PATH="${pkgs.mesa}/lib/dri"
          export __GLX_VENDOR_LIBRARY_NAME=mesa
          export __EGL_VENDOR_LIBRARY_FILENAMES="${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
          export LD_LIBRARY_PATH="${pkgs.mesa}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          export SDL_VIDEODRIVER=x11
          output="$(xvfb-run -a -s "-screen 0 1024x768x24" ./sdl3-triangle --seconds 1)"
          echo "$output"
          echo "$output" | grep -q 'rendered'
          runHook postCheck
        '';
        meta.mainProgram = "sdl3-triangle";
      };

      sharun = pkgs.fetchurl {
        url = "https://github.com/pkgforge-dev/Anylinux-sharun/releases/download/3.5.1/sharun-x86_64";
        hash = "sha256-XbkqdJL4sb75wrplM0ZDaot8xBMSZxWlCZPKBdl0ZbQ=";
      };
      appimageRuntime = pkgs.fetchurl {
        url = "https://github.com/VHSgunzo/uruntime/releases/download/v0.8.1/uruntime-appimage-squashfs-lite-x86_64";
        hash = "sha256-MsYCShT/N1dJ7jvtMzDBWGpt0r/t27186swFOuwrJ6M=";
      };

      # =======================================================================
      # 2. mkPortable — with or without a bundled GL stack.
      # =======================================================================
      #   bundleGL = false  -> HOST drivers: ship nothing GPU-facing.  Tiny, and
      #                        the only way to use the proprietary NVIDIA driver.
      #                        Works where the host driver matches the app's libc.
      #   bundleGL = true   -> BUNDLED Mesa: ship a glibc Mesa (llvmpipe).  Big,
      #                        but renders anywhere, including musl.
      mkPortable = { name, mainProgram ? name, bundleGL, checkCommand ? "" }:
        let
          desktopFile = pkgs.writeText "${name}.desktop" ''
            [Desktop Entry]
            Type=Application
            Name=${name}
            Exec=${mainProgram}
            Terminal=true
            Categories=Development;
          '';
          # GL bits only used when bundleGL = true.  Only LITERAL values: sharun
          # does not expand $APPDIR in .env.  The Mesa paths are auto-detected
          # from the layout (lib/dri, share/glvnd/egl_vendor.d).
          glEnv = lib.optionalString bundleGL ''
            LIBGL_ALWAYS_SOFTWARE=1
            GALLIUM_DRIVER=llvmpipe
            __GLX_VENDOR_LIBRARY_NAME=mesa
          '';
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable${lib.optionalString bundleGL "-bundled-gl"}";
          version = "1";
          dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
          nativeBuildInputs = with pkgs; [
            bash coreutils findutils gnused gnugrep patchelf glibc.bin zstd xvfb-run
          ];
          installPhase = ''
            set -eu
            bin="${app}/bin/${mainProgram}"
            mkdir -p "$out/bin" "$out/shared/bin" "$out/lib"
            cp -L "$bin" "$out/shared/bin/${mainProgram}"
            cp -L ${sharun} "$out/sharun"; chmod +x "$out/sharun"
            ln "$out/sharun" "$out/AppRun"
            ln "$out/sharun" "$out/bin/${mainProgram}"

            cp -L ${pkgs.glibc}/lib/*.so* "$out/lib/"
            chmod -R u+w "$out/lib"
          '' + lib.optionalString bundleGL ''
            mkdir -p "$out/lib/dri" "$out/share/glvnd/egl_vendor.d"
            for f in libGL.so.1 libGLX.so.0 libEGL.so.1 libGLdispatch.so.0 libOpenGL.so.0; do
              cp -L ${pkgs.libGL}/lib/"$f"* "$out/lib/" 2>/dev/null || true
            done
            cp -L ${pkgs.mesa}/lib/libGLX_mesa.so.0* "$out/lib/"
            cp -L ${pkgs.mesa}/lib/libEGL_mesa.so.0* "$out/lib/"
            cp -L ${pkgs.mesa}/lib/libgallium-*.so   "$out/lib/"
            cp -L ${pkgs.mesa}/lib/dri/*.so          "$out/lib/dri/" 2>/dev/null || true
            sed 's#"[^"]*libEGL_mesa.so.0"#"libEGL_mesa.so.0"#' \
              ${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json \
              > "$out/share/glvnd/egl_vendor.d/50_mesa.json"
            chmod -R u+w "$out/lib" "$out/share"
          '' + ''
            # DT_NEEDED closure of the app, plus the Mesa seeds when bundling GL.
            # Unmatched globs (host-driver mode) are skipped by the `-e` test.
            chmod -R u+w "$out/lib"
            for seed in "$out/shared/bin/${mainProgram}" \
                        "$out/lib/libgallium-"*.so \
                        "$out/lib/libGLX_mesa.so.0" \
                        "$out/lib/libEGL_mesa.so.0" \
                        "$out/lib/libGL.so.1"; do
              [ -e "$seed" ] || continue
              ${pkgs.glibc.bin}/bin/ldd "$seed" 2>/dev/null | grep -o '/nix/store/[^ ]*' || true
            done | sort -u | while IFS= read -r l; do
              cp -Lf --no-preserve=mode,ownership "$l" "$out/lib/$(basename "$l")"
            done

            test -f "$out/lib/ld-linux-x86-64.so.2" || {
              echo "missing dynamic linker" >&2; exit 1; }

            chmod -R u+w "$out/lib" "$out/shared/bin"
            for f in "$out"/lib/*.so* "$out"/lib/dri/*.so "$out/shared/bin/${mainProgram}"; do
              [ -f "$f" ] || continue
              [ -L "$f" ] && continue
              case "$(basename "$f")" in ld-*) continue ;; esac
              if [ "$(dd if="$f" bs=1 count=4 2>/dev/null)" = "$(printf '\177ELF')" ]; then
                patchelf --remove-rpath "$f" || true
              fi
            done

            cat > "$out/.env" <<'EOF'
            ${glEnv}
            EOF
            cp ${desktopFile} "$out/${name}.desktop"
            echo "$(find "$out/lib" -maxdepth 1 -type f | wc -l) libraries"
          '';
          doInstallCheck = checkCommand != "";
          installCheckPhase = ''
            runHook preInstallCheck
            ${checkCommand}
            runHook postInstallCheck
          '';
        };

      # A host that provides Mesa.  In the sandbox there is no /usr/lib GL, so we
      # point the *host-driver* bundle at nixpkgs' Mesa to simulate one.  The
      # directories go on the loader's search path (sharun appends the host's
      # real ones at runtime).
      hostGLDir = "${pkgs.mesa}/lib:${pkgs.libGL}/lib";
      hostGLEnv = ''
        export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
        export LIBGL_DRIVERS_PATH="${pkgs.mesa}/lib/dri"
        export __GLX_VENDOR_LIBRARY_NAME=mesa
        export __EGL_VENDOR_LIBRARY_FILENAMES="${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
        export SDL_VIDEODRIVER=x11
      '';

      # Run the bundle through its bundled loader.  `extraPath` simulates the
      # host directories sharun appends to the library path.
      runViaLoader = { check, extraPath ? "" }: ''
        output="$(xvfb-run -a -s "-screen 0 1024x768x24" \
          "$out/lib/ld-linux-x86-64.so.2" --library-path "$out/lib${extraPath}" \
          "$out/shared/bin/sdl3-triangle" --seconds 1)"
        echo "$output"
        echo "$output" | grep -q '${check}'
      '';

      # The bundled-Mesa check must set the GL env itself, because it bypasses
      # sharun (and therefore the bundle's `.env`).
      bundledGLEnv = ''
        export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
        export LD_LIBRARY_PATH="$out/lib"
        export LIBGL_DRIVERS_PATH="$out/lib/dri"
        export __GLX_VENDOR_LIBRARY_NAME=mesa
        export __EGL_VENDOR_LIBRARY_DIRS="$out/share/glvnd/egl_vendor.d"
        export SDL_VIDEODRIVER=x11
      '';

      portable = mkPortable {
        name = "sdl3-triangle";
        bundleGL = false;
        checkCommand = hostGLEnv + runViaLoader {
          check = "rendered";
          extraPath = ":${hostGLDir}";
        };
      };
      portableBundled = mkPortable {
        name = "sdl3-triangle";
        bundleGL = true;
        checkCommand = bundledGLEnv + runViaLoader { check = "rendered"; };
      };

      mkTarball = { name, appdir, suffix ? "" }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable${suffix}-tar";
          version = "1";
          dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
          nativeBuildInputs = [ pkgs.zstd pkgs.coreutils ];
          installPhase = ''
            set -eu
            mkdir -p "$out"
            cp -r ${appdir} "./${name}-portable${suffix}"
            chmod -R u+w "./${name}-portable${suffix}"
            tar --zstd -cf "$out/${name}-portable${suffix}-x86_64.tar.zst" "${name}-portable${suffix}"
          '';
        };

      mkAppImage = { name, appdir, suffix ? "" }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable${suffix}-appimage";
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
            cat ./runtime app.squashfs > "$out/${name}${suffix}-x86_64.AppImage"
            chmod +x "$out/${name}${suffix}-x86_64.AppImage"
          '';
        };
    in
    {
      packages.${system} = {
        inherit app sharun;
        # host drivers (default)
        portable = portable;
        portable-tar = mkTarball { name = "sdl3-triangle"; appdir = portable; };
        portable-appimage = mkAppImage { name = "sdl3-triangle"; appdir = portable; };
        # bundled Mesa variant
        portable-bundled-gl = portableBundled;
        portable-bundled-gl-tar = mkTarball { name = "sdl3-triangle"; appdir = portableBundled; suffix = "-bundled-gl"; };
        portable-bundled-gl-appimage = mkAppImage { name = "sdl3-triangle"; appdir = portableBundled; suffix = "-bundled-gl"; };
        default = portable;
      };
    };
}
