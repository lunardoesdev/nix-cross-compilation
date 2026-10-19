{
  description = "Chapter 18 — portable FHS Linux bundles with sharun + uruntime (no nix, no nixGL)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # 1. The libraries and applications (native Linux).
      # =======================================================================
      mkLib = { pname, version ? "1.0.0", src, sources, headers ? [], libName
              , deps ? [], linkLibs ? [] }:
        pkgs.callPackage ({ lib, stdenv }:
          let
            includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
            depFlags = lib.concatMapStringsSep " " (d: "-L${d}/lib") deps
              + " " + lib.concatMapStringsSep " " (l: "-l${l}") linkLibs;
            soMajor = lib.versions.major version;
            soReal = "lib${libName}.so.${version}";
            soMajorLink = "lib${libName}.so.${soMajor}";
          in
          stdenv.mkDerivation {
            inherit pname version src;
            buildInputs = deps;
            strictDeps = true;
            dontConfigure = true;
            enableParallelBuilding = false;
            buildPhase = ''
              runHook preBuild
              mkdir -p obj
              for f in ${lib.concatStringsSep " " sources}; do
                $CC -O2 -fPIC -Wall -Wextra ${includeFlags} \
                  -c "$f" -o "obj/$(basename "$f" .c).o"
              done
              $AR rcs "lib${libName}.a" obj/*.o
              $CC -shared -Wl,-soname,"${soMajorLink}" -o "${soReal}" obj/*.o ${depFlags}
              ln -sf "${soReal}" "${soMajorLink}"
              ln -sf "${soReal}" "lib${libName}.so"
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib" "$out/include"
              cp "lib${libName}.a" "$out/lib/"
              cp "${soReal}" "$out/lib/"
              ln -sf "${soReal}" "$out/lib/${soMajorLink}"
              ln -sf "${soReal}" "$out/lib/lib${libName}.so"
              ${lib.concatMapStringsSep "\n" (h: ''cp "${h}" "$out/include/"'') headers}
              runHook postInstall
            '';
          }) { };

      libadd = mkLib {
        pname = "libadd"; src = ./src;
        sources = [ "add.c" ]; headers = [ "add.h" ]; libName = "add";
      };
      libmul = mkLib {
        pname = "libmul"; src = ./src;
        sources = [ "mul.c" ]; headers = [ "mul.h" ]; libName = "mul";
        deps = [ libadd ]; linkLibs = [ "add" ];
      };

      uselib2 = pkgs.stdenv.mkDerivation {
        pname = "uselib2";
        version = "1.0.0";
        src = ./src;
        buildInputs = [ libmul libadd ];
        strictDeps = true;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC -O2 -Wall -Wextra \
            -I${libmul}/include -I${libadd}/include uselib2.c \
            -o uselib2 -L${libmul}/lib -lmul -L${libadd}/lib -ladd
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin"
          cp uselib2 "$out/bin/"
          runHook postInstall
        '';
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          output="$(./uselib2)"; echo "$output"
          echo "$output" | grep -q 'mul(6, 7) = 42'
          runHook postCheck
        '';
      };

      sdl3-game = pkgs.stdenv.mkDerivation {
        pname = "sdl3-game";
        version = "1.0.0";
        src = ./src;
        buildInputs = [ pkgs.sdl3 libmul libadd ];
        strictDeps = true;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC -O2 -Wall -Wextra \
            -I${lib.getDev pkgs.sdl3}/include \
            -I${libmul}/include -I${libadd}/include game.c \
            -o sdl3-game \
            -L${libmul}/lib -lmul -L${libadd}/lib -ladd \
            -L${lib.getLib pkgs.sdl3}/lib -lSDL3
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin"
          cp sdl3-game "$out/bin/"
          runHook postInstall
        '';
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          output="$(SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy \
            ./sdl3-game --frames 5)"
          echo "$output"
          echo "$output" | grep -q 'score = mul(3, 14) = 42'
          runHook postCheck
        '';
        meta.mainProgram = "sdl3-game";
      };

      # =======================================================================
      # 2. Pinned sharun and the AppImage runtime.
      # =======================================================================
      sharun = pkgs.fetchurl {
        url = "https://github.com/pkgforge-dev/Anylinux-sharun/releases/download/3.5.1/sharun-x86_64";
        hash = "sha256-XbkqdJL4sb75wrplM0ZDaot8xBMSZxWlCZPKBdl0ZbQ=";
      };
      appimageRuntime = pkgs.fetchurl {
        url = "https://github.com/VHSgunzo/uruntime/releases/download/v0.8.1/uruntime-appimage-squashfs-lite-x86_64";
        hash = "sha256-MsYCShT/N1dJ7jvtMzDBWGpt0r/t27186swFOuwrJ6M=";
      };

      # GPU / kernel-facing libraries are NOT bundled: they must match the
      # machine that runs the game.  sharun falls back to the host's copies.
      hostDriverLibs = [
        "libEGL*" "libGL.so*" "libGLX*" "libGLdispatch*" "libOpenGL*"
        "libGLESv1*" "libGLESv2*" "libgbm*" "libvulkan*" "libdrm*"
        "libLLVM*" "libgallium*" "libglapi*" "libxatracker*"
      ];
      hostDriverPattern = builtins.concatStringsSep "|" hostDriverLibs;

      # =======================================================================
      # 3. mkPortable: assemble one sharun AppDir.
      # =======================================================================
      mkPortable = { name, app, mainProgram ? name, isTerminal ? true, checkCommand ? "" }:
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
            app="${app}/bin/${mainProgram}"
            mkdir -p "$out/bin" "$out/shared/bin" "$out/lib"

            cp -L "$app" "$out/shared/bin/${mainProgram}"

            cp -L ${sharun} "$out/sharun"
            chmod +x "$out/sharun"
            ln "$out/sharun" "$out/AppRun"
            ln "$out/sharun" "$out/bin/${mainProgram}"

            cp -L ${pkgs.glibc}/lib/*.so* "$out/lib/"
            chmod -R u+w "$out/lib"

            ${pkgs.glibc.bin}/bin/ldd "$app" \
              | grep -o '/nix/store/[^ ]*' \
              | xargs -r -n1 dirname \
              | sort -u \
              | while IFS= read -r dir; do
                  for lib in "$dir"/*.so*; do
                    [ -e "$lib" ] || continue
                    base="$(basename "$lib")"
                    case "$base" in
                      ${hostDriverPattern})
                        echo "leaving ''${base} to the host (GPU driver)"
                        continue
                        ;;
                    esac
                    cp -a --no-preserve=mode,ownership "$lib" "$out/lib/$base"
                  done
                done

            test -f "$out/lib/ld-linux-x86-64.so.2" || {
              echo "missing dynamic linker" >&2; exit 1; }

            chmod -R u+w "$out/lib" "$out/shared/bin"
            for f in "$out"/lib/*.so* "$out/shared/bin/${mainProgram}"; do
              [ -f "$f" ] || continue
              [ -L "$f" ] && continue
              case "$(basename "$f")" in ld-*) continue ;; esac
              patchelf --remove-rpath "$f" || true
            done

            cp ${desktopFile} "$out/${name}.desktop"
            : > "$out/.env"

            echo "bundled $(find "$out/lib" -maxdepth 1 \( -type f -o -type l \) | wc -l) libraries"
          '';
          doInstallCheck = checkCommand != "";
          installCheckPhase = ''
            runHook preInstallCheck
            ${checkCommand}
            runHook postInstallCheck
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
            # uruntime: try FUSE, otherwise always extract (works without FUSE)
            sed -i 's/URUNTIME_EXTRACT=[0-9]/URUNTIME_EXTRACT=2/' ./runtime
            grep -a -q 'URUNTIME_EXTRACT=2' ./runtime
            cat ./runtime app.squashfs > "$out/${name}-x86_64.AppImage"
            chmod +x "$out/${name}-x86_64.AppImage"
          '';
        };

      portableCli = mkPortable {
        name = "uselib2";
        app = uselib2;
        checkCommand = ''
          output="$("$out/lib/ld-linux-x86-64.so.2" \
            --library-path "$out/lib" "$out/shared/bin/uselib2")"
          echo "$output"
          echo "$output" | grep -q 'mul(6, 7) = 42'
        '';
      };
      portableGame = mkPortable {
        name = "sdl3-game";
        app = sdl3-game;
        isTerminal = false;
      };
    in
    {
      packages.${system} = {
        inherit libadd libmul uselib2 sdl3-game sharun;
        uselib2-portable = portableCli;
        sdl3-game-portable = portableGame;
        uselib2-portable-tar = mkTarball { name = "uselib2"; appdir = portableCli; };
        sdl3-game-portable-tar = mkTarball { name = "sdl3-game"; appdir = portableGame; };
        uselib2-portable-appimage = mkAppImage { name = "uselib2"; appdir = portableCli; };
        sdl3-game-portable-appimage = mkAppImage { name = "sdl3-game"; appdir = portableGame; };
        default = portableCli;
      };
    };
}
