{
  description = "Chapter 27 — host drivers only: the smallest portable GL app (glibc hosts, no musl)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # 1. The application (same C++ SDL3 + OpenGL triangle as chapters 24–26).
      # =======================================================================
      # It is built against SDL3 + libepoxy only.  libGL and mesa are build
      # inputs *for the build-time check* (they simulate a host that has a
      # driver); the bundle itself ships none of them.
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
      # 2. The bundle — app + glibc + its DT_NEEDED closure.  NO GL driver.
      # =======================================================================
      # Nothing GPU-facing is copied: no Mesa, no glvnd, no DRI drivers.  At
      # runtime SDL dlopens the *host's* libGL.so.1 and the host's driver, and
      # sharun appends the host's library directories (/usr/lib, /lib, the
      # ld.so cache, /run/opengl-driver/lib) after the bundled ones.
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
          pname = "${name}-portable-host-drivers";
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

            # complete glibc (loader, libc, NSS modules, ...)
            cp -L ${pkgs.glibc}/lib/*.so* "$out/lib/"
            chmod -R u+w "$out/lib"

            # DT_NEEDED closure of the app (libstdc++, SDL3, epoxy, X11, audio,
            # ...).  Deliberately nothing else: no Mesa, no glvnd.
            ${pkgs.glibc.bin}/bin/ldd "$out/shared/bin/${mainProgram}" \
              | grep -o '/nix/store/[^ ]*' \
              | sort -u | while IFS= read -r l; do
                  cp -Lf --no-preserve=mode,ownership "$l" "$out/lib/$(basename "$l")"
                done

            test -f "$out/lib/ld-linux-x86-64.so.2" || {
              echo "missing dynamic linker" >&2; exit 1; }

            chmod -R u+w "$out/lib" "$out/shared/bin"
            for f in "$out"/lib/*.so* "$out/shared/bin/${mainProgram}"; do
              [ -f "$f" ] || continue
              [ -L "$f" ] && continue
              case "$(basename "$f")" in ld-*) continue ;; esac
              if [ "$(dd if="$f" bs=1 count=4 2>/dev/null)" = "$(printf '\177ELF')" ]; then
                patchelf --remove-rpath "$f" || true
              fi
            done

            : > "$out/.env"
            cp ${desktopFile} "$out/${name}.desktop"
            echo "bundled $(find "$out/lib" -maxdepth 1 -type f | wc -l) libraries (no GL driver)"
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
        # Prove the bundle ships NO GL driver, then run it against a simulated
        # host driver: nixpkgs' Mesa on the loader search path, exactly where a
        # real host's /usr/lib would be.
        checkCommand = ''
          if ls "$out"/lib/libGL.so.1 "$out"/lib/libGLX_mesa.so.0 \
                "$out"/lib/libgallium-*.so >/dev/null 2>&1; then
            echo "ERROR: the bundle contains a GL driver" >&2
            exit 1
          fi

          export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe SDL_VIDEODRIVER=x11
          export LIBGL_DRIVERS_PATH="${pkgs.mesa}/lib/dri"
          export __GLX_VENDOR_LIBRARY_NAME=mesa
          export __EGL_VENDOR_LIBRARY_FILENAMES="${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
          output="$(xvfb-run -a -s "-screen 0 1024x768x24" \
            "$out/lib/ld-linux-x86-64.so.2" \
            --library-path "$out/lib:${pkgs.mesa}/lib:${pkgs.libGL}/lib" \
            "$out/shared/bin/sdl3-triangle" --seconds 1)"
          echo "$output"
          echo "$output" | grep -q 'rendered'
        '';
      };

      mkTarball = { name, appdir }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable-host-drivers-tar";
          version = "1";
          dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
          nativeBuildInputs = [ pkgs.zstd pkgs.coreutils ];
          installPhase = ''
            set -eu
            mkdir -p "$out"
            cp -r ${appdir} "./${name}-portable-host-drivers"
            chmod -R u+w "./${name}-portable-host-drivers"
            tar --zstd -cf "$out/${name}-host-drivers-x86_64.tar.zst" "${name}-portable-host-drivers"
          '';
        };

      mkAppImage = { name, appdir }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable-host-drivers-appimage";
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
            cat ./runtime app.squashfs > "$out/${name}-host-drivers-x86_64.AppImage"
            chmod +x "$out/${name}-host-drivers-x86_64.AppImage"
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
