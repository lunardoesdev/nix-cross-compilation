{
  description = "Chapter 26 — SHARUN_MESA_PATH: a swappable Mesa in its own directory";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # 1. The application (same C++ SDL3 + OpenGL triangle as chapters 24–25).
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
      # 2. Mesa in its own directory, behind SHARUN_MESA_PATH.
      # =======================================================================
      # `sharun` reads `SHARUN_MESA_PATH` and treats it as a Mesa prefix:
      #
      #   <path>/lib/dri/               -> LIBGL_DRIVERS_PATH
      #   <path>/lib/gbm/               -> GBM_BACKENDS_PATH
      #   <path>/share/glvnd/egl_vendor.d/  -> __EGL_VENDOR_LIBRARY_DIRS
      #   <path>/share/vulkan/icd.d/    -> VK_DRIVER_FILES
      #   <path>/share/drirc.d/         -> DRIRC_CONFIGDIR
      #
      # Because the vendor libs live in <path>/lib (not the bundle's lib/), we
      # also add it to the loader search path with SHARUN_EXTRA_LIBRARY_PATH so
      # glvnd can dlopen them by soname.
      mkPortable = { name, mainProgram ? name, checkCommand ? "" }:
        let
          desktopFile = pkgs.writeText "${name}.desktop" ''
            [Desktop Entry]
            Type=Application
            Name=${name}
            Exec=${mainProgram}
            Terminal=true
            Categories=Development;
          '';
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable-mesa-path";
          version = "1";
          dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
          nativeBuildInputs = with pkgs; [
            bash coreutils findutils gnused gnugrep patchelf glibc.bin zstd xvfb-run
          ];
          installPhase = ''
            set -eu
            bin="${app}/bin/${mainProgram}"
            mkdir -p "$out/bin" "$out/shared/bin" "$out/lib" \
                     "$out/mesa/lib/dri" "$out/mesa/share/glvnd/egl_vendor.d"

            cp -L "$bin" "$out/shared/bin/${mainProgram}"
            cp -L ${sharun} "$out/sharun"; chmod +x "$out/sharun"
            ln "$out/sharun" "$out/AppRun"
            ln "$out/sharun" "$out/bin/${mainProgram}"

            # glibc + glvnd entry points in the normal lib/
            cp -L ${pkgs.glibc}/lib/*.so* "$out/lib/"
            for f in libGL.so.1 libGLX.so.0 libEGL.so.1 libGLdispatch.so.0 libOpenGL.so.0; do
              cp -L ${pkgs.libGL}/lib/"$f"* "$out/lib/" 2>/dev/null || true
            done

            # Mesa itself in $APPDIR/mesa/{lib,share}
            cp -L ${pkgs.mesa}/lib/libGLX_mesa.so.0* "$out/mesa/lib/"
            cp -L ${pkgs.mesa}/lib/libEGL_mesa.so.0* "$out/mesa/lib/"
            cp -L ${pkgs.mesa}/lib/libgallium-*.so   "$out/mesa/lib/"
            cp -L ${pkgs.mesa}/lib/dri/*.so          "$out/mesa/lib/dri/" 2>/dev/null || true
            # bare soname so the manifest stays relocatable
            sed 's#"[^"]*libEGL_mesa.so.0"#"libEGL_mesa.so.0"#' \
              ${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json \
              > "$out/mesa/share/glvnd/egl_vendor.d/50_mesa.json"

            # DT_NEEDED closure of the app, plus the Mesa seeds (into mesa/lib)
            chmod -R u+w "$out/lib" "$out/mesa"
            for seed in "$out/shared/bin/${mainProgram}" \
                        "$out/mesa/lib/libgallium-"*.so \
                        "$out/mesa/lib/libGLX_mesa.so.0" \
                        "$out/mesa/lib/libEGL_mesa.so.0" \
                        "$out/lib/libGL.so.1"; do
              [ -e "$seed" ] || continue
              ${pkgs.glibc.bin}/bin/ldd "$seed" 2>/dev/null | grep -o '/nix/store/[^ ]*' || true
            done | sort -u | while IFS= read -r l; do
              case "$l" in
                */libgallium-*.so|*/libGLX_mesa.so.0|*/libEGL_mesa.so.0)
                  cp -Lf --no-preserve=mode,ownership "$l" "$out/mesa/lib/$(basename "$l")" ;;
                *)
                  cp -Lf --no-preserve=mode,ownership "$l" "$out/lib/$(basename "$l")" ;;
              esac
            done

            test -f "$out/lib/ld-linux-x86-64.so.2" || {
              echo "missing dynamic linker" >&2; exit 1; }

            chmod -R u+w "$out/lib" "$out/mesa" "$out/shared/bin"
            for f in "$out"/lib/*.so* "$out"/mesa/lib/*.so* "$out"/mesa/lib/dri/*.so \
                     "$out/shared/bin/${mainProgram}"; do
              [ -f "$f" ] || continue
              [ -L "$f" ] && continue
              case "$(basename "$f")" in ld-*) continue ;; esac
              if [ "$(dd if="$f" bs=1 count=4 2>/dev/null)" = "$(printf '\177ELF')" ]; then
                patchelf --remove-rpath "$f" || true
              fi
            done

            cat > "$out/.env" <<'EOF'
            SHARUN_MESA_PATH=$APPDIR/mesa
            SHARUN_EXTRA_LIBRARY_PATH=$APPDIR/mesa/lib
            LIBGL_ALWAYS_SOFTWARE=1
            GALLIUM_DRIVER=llvmpipe
            EOF

            cp ${desktopFile} "$out/${name}.desktop"
            echo "bundled $(find "$out/lib" -maxdepth 1 -type f | wc -l) libs + mesa"
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
        # Reproduce what sharun sets from SHARUN_MESA_PATH, then run through the
        # bundled loader.
        checkCommand = ''
          export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
          export LIBGL_DRIVERS_PATH="$out/mesa/lib/dri"
          export __EGL_VENDOR_LIBRARY_DIRS="$out/mesa/share/glvnd/egl_vendor.d"
          export __GLX_VENDOR_LIBRARY_NAME=mesa
          export SDL_VIDEODRIVER=x11
          output="$(xvfb-run -a -s "-screen 0 1024x768x24" \
            "$out/lib/ld-linux-x86-64.so.2" \
            --library-path "$out/lib:$out/mesa/lib" \
            "$out/shared/bin/sdl3-triangle" --seconds 1)"
          echo "$output"
          echo "$output" | grep -q 'rendered'
        '';
      };

      mkTarball = { name, appdir }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable-mesa-path-tar";
          version = "1";
          dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
          nativeBuildInputs = [ pkgs.zstd pkgs.coreutils ];
          installPhase = ''
            set -eu
            mkdir -p "$out"
            cp -r ${appdir} "./${name}-portable-mesa-path"
            chmod -R u+w "./${name}-portable-mesa-path"
            tar --zstd -cf "$out/${name}-portable-mesa-path-x86_64.tar.zst" "${name}-portable-mesa-path"
          '';
        };

      mkAppImage = { name, appdir }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable-mesa-path-appimage";
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
            cat ./runtime app.squashfs > "$out/${name}-mesa-path-x86_64.AppImage"
            chmod +x "$out/${name}-mesa-path-x86_64.AppImage"
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
