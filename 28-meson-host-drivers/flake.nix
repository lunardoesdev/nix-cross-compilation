{
  description = "Chapter 28 — Meson: SDL3 + OpenGL app depending on libmul -> libadd, host drivers only";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # Common Meson toolchain for every package in this chapter.
      mesonTools = with pkgs; [ meson ninja pkg-config ];

      # =======================================================================
      # 1. libadd — a Meson project that installs headers, a shared library and
      #    a pkg-config file.  No compiler flags are written by hand.
      # =======================================================================
      libadd = pkgs.stdenv.mkDerivation {
        pname = "libadd";
        version = "1.0.0";
        src = ./src/libadd;
        nativeBuildInputs = mesonTools;
        strictDeps = true;
        enableParallelBuilding = false;
        doCheck = false;
      };

      # =======================================================================
      # 2. libmul — depends on libadd the normal Nix way.
      # =======================================================================
      # `buildInputs = [ libadd ]` puts libadd's lib/pkgconfig on PKG_CONFIG_PATH
      # (via the pkg-config setup hook), so Meson's `dependency('libadd')` just
      # works.  This is the whole dependency mechanism: no paths, no flags.
      libmul = pkgs.stdenv.mkDerivation {
        pname = "libmul";
        version = "1.0.0";
        src = ./src/libmul;
        nativeBuildInputs = mesonTools;
        buildInputs = [ libadd ];
        # Forward libadd to anything that links libmul: libmul.pc says
        # `Requires: libadd`, so consumers need libadd's pkg-config file too.
        propagatedBuildInputs = [ libadd ];
        strictDeps = true;
        enableParallelBuilding = false;
        doCheck = false;
      };

      # =======================================================================
      # 3. The application — Meson again, depending on libmul (+ SDL3, epoxy).
      # =======================================================================
      app = pkgs.stdenv.mkDerivation {
        pname = "sdl3-triangle";
        version = "1.0.0";
        src = ./src/app;

        nativeBuildInputs = mesonTools ++ [ pkgs.xvfb-run ];
        # libGL/mesa are here only so the build-time check has a driver to use;
        # the shipped bundle includes none of them.
        buildInputs = [ libmul pkgs.sdl3 pkgs.libepoxy pkgs.libGL pkgs.mesa ];

        strictDeps = true;
        enableParallelBuilding = false;

        doCheck = true;
        checkPhase = ''
          runHook preCheck
          export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
          export LIBGL_DRIVERS_PATH="${pkgs.mesa}/lib/dri"
          export __GLX_VENDOR_LIBRARY_NAME=mesa
          export __EGL_VENDOR_LIBRARY_FILENAMES="${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
          export LD_LIBRARY_PATH="${pkgs.mesa}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          export SDL_VIDEODRIVER=x11
          output="$(xvfb-run -a -s "-screen 0 1024x768x24" \
            ./build/sdl3-triangle --seconds 1)"
          echo "$output"
          echo "$output" | grep -q 'score = mul(3, 14) = 42'
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
      # 4. Host-driver-only portable bundle (as in chapter 27).
      # =======================================================================
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

            cp -L ${pkgs.glibc}/lib/*.so* "$out/lib/"
            chmod -R u+w "$out/lib"

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
        checkCommand = ''
          if ls "$out"/lib/libGL.so.1 "$out"/lib/libgallium-*.so >/dev/null 2>&1; then
            echo "ERROR: the bundle contains a GL driver" >&2; exit 1
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
          echo "$output" | grep -q 'score = mul(3, 14) = 42'
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
        inherit libadd libmul app sharun;
        portable = portable;
        portable-tar = mkTarball { name = "sdl3-triangle"; appdir = portable; };
        portable-appimage = mkAppImage { name = "sdl3-triangle"; appdir = portable; };
        default = portable;
      };
    };
}
