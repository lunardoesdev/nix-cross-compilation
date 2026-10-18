# -----------------------------------------------------------------------------
# Portable "FHS" Linux bundles built with sharun.
#
# sharun (https://github.com/pkgforge-dev/Anylinux-sharun) is a single static
# launcher.  An AppDir produced here has this layout:
#
#   AppDir/
#     sharun                 # static launcher (hardlink target)
#     AppRun      -> sharun  # hardlink
#     bin/<app>   -> sharun  # hardlink; argv[0] selects the real binary
#     shared/bin/<app>       # the real ELF
#     lib/                   # bundled dynamic linker + every runtime .so
#     .env                   # extra environment for the app
#
# At runtime sharun runs
#
#     $APPDIR/lib/ld-linux-x86-64.so.2 --library-path $APPDIR/lib \
#         $APPDIR/shared/bin/<app> "$@"
#
# so the bundle never needs /nix/store, nix, nix-portable or nixGL.  sharun also
# appends the host's library directories (/usr/lib, /lib, the ld.so cache and
# /run/opengl-driver/lib) *after* the bundled ones, which is how the game picks
# up the host's GPU drivers while still shipping a complete userspace.
# -----------------------------------------------------------------------------
{ pkgs }:
let
  # Pinned sharun release (x86_64).  Fixed-output derivation: the hash below is
  # the sha256 of the upstream asset, so the download is reproducible.
  sharun = pkgs.fetchurl {
    url = "https://github.com/pkgforge-dev/Anylinux-sharun/releases/download/3.5.1/sharun-x86_64";
    hash = "sha256-XbkqdJL4sb75wrplM0ZDaot8xBMSZxWlCZPKBdl0ZbQ=";
  };

  # Pinned AppImage runtime: VHSgunzo's `uruntime` (SquashFS, AppImage flavour).
  # Unlike the classic type-2 runtime it does not require FUSE: when mounting
  # fails it extracts and runs instead (see URUNTIME_EXTRACT below).
  appimageRuntime = pkgs.fetchurl {
    url = "https://github.com/VHSgunzo/uruntime/releases/download/v0.8.1/uruntime-appimage-squashfs-lite-x86_64";
    hash = "sha256-MsYCShT/N1dJ7jvtMzDBWGpt0r/t27186swFOuwrJ6M=";
  };

  # GPU / kernel-facing libraries deliberately NOT bundled: they must match the
  # machine that actually runs the game (its Mesa, NVIDIA driver and kernel).
  # sharun's host fallback path finds them at runtime.
  hostDriverLibs = [
    "libEGL*"
    "libGL.so*"
    "libGLX*"
    "libGLdispatch*"
    "libOpenGL*"
    "libGLESv1*"
    "libGLESv2*"
    "libgbm*"
    "libvulkan*"
    "libdrm*"
    "libLLVM*"
    "libgallium*"
    "libglapi*"
    "libxatracker*"
  ];

  hostDriverPattern = builtins.concatStringsSep "|" hostDriverLibs;

  # ---------------------------------------------------------------------------
  # mkPortable: assemble one AppDir.
  #
  #   app          - the normal Nix package (e.g. linux-uselib2)
  #   mainProgram  - the binary inside $app/bin
  #   checkCommand - optional shell snippet run inside the build (native only)
  # ---------------------------------------------------------------------------
  mkPortable = { name
    , app
    , mainProgram ? name
    , glibc ? pkgs.glibc
    , interpreter ? "ld-linux-x86-64.so.2"
    , isTerminal ? true
    , checkCommand ? ""
    }:
    let
      # AppRun reads Exec= from the first .desktop file in the AppDir, so one
      # has to exist for `./AppRun` to work.
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
      # Keep the tree exactly as assembled; fixup would strip/patchelf it again.
      dontFixup = true;

      nativeBuildInputs = with pkgs; [
        bash
        coreutils
        findutils
        gnused
        gnugrep
        patchelf
        glibc.bin
        zstd
      ];

      installPhase = ''
        set -eu

        app="${app}/bin/${mainProgram}"
        mkdir -p "$out/bin" "$out/shared/bin" "$out/lib"

        # 1. real ELF, hidden in shared/bin
        cp -L "$app" "$out/shared/bin/${mainProgram}"

        # 2. launcher + the two hardlinks sharun looks for
        cp -L ${sharun} "$out/sharun"
        chmod +x "$out/sharun"
        ln "$out/sharun" "$out/AppRun"
        ln "$out/sharun" "$out/bin/${mainProgram}"

        # 3. the complete glibc (loader, libc, NSS modules, ...)
        cp -L ${glibc}/lib/*.so* "$out/lib/"
        # store files are read-only; we need to overwrite/patchelf them below
        chmod -R u+w "$out/lib"

        # 4. every store library the program links against.  `ldd` resolves the
        #    whole DT_NEEDED tree, including transitive dependencies.  For each
        #    directory we copy *all* of its .so* files (preserving symlinks), so
        #    versioned libraries keep their `libfoo.so.<major>` names, which is
        #    what DT_NEEDED actually refers to.
        ${pkgs.glibc.bin}/bin/ldd "$app" \
          | grep -o '/nix/store/[^ ]*' \
          | xargs -r -n1 dirname \
          | sort -u \
          | while IFS= read -r dir; do
              for lib in "$dir"/*.so*; do
                [ -e "$lib" ] || continue
                base="$(basename "$lib")"
                # shellcheck disable=SC2254
                case "$base" in
                  ${hostDriverPattern})
                    echo "sharun-bundle: leaving ''${base} to the host (GPU driver)"
                    continue
                    ;;
                esac
                cp -a --no-preserve=mode,ownership "$lib" "$out/lib/$base"
              done
            done

        # 4b. the bundled dynamic linker must be present
        test -f "$out/lib/${interpreter}" || {
          echo "sharun-bundle: missing dynamic linker ${interpreter}" >&2
          exit 1
        }

        # 5. Drop Nix store RPATHs so nothing can quietly load a /nix/store
        #    library on the target machine.  The bundled loader + --library-path
        #    is all the bundle needs.  Never touch the loader itself, and leave
        #    the (relative) symlinks alone.
        chmod -R u+w "$out/lib" "$out/shared/bin"
        for f in "$out"/lib/*.so* "$out/shared/bin/${mainProgram}"; do
          [ -f "$f" ] || continue
          [ -L "$f" ] && continue
          base="$(basename "$f")"
          case "$base" in
            ld-*) continue ;;
          esac
          patchelf --remove-rpath "$f" || true
        done

        # 6. desktop entry (AppRun reads Exec= from it) and an empty env file
        cp ${desktopFile} "$out/${name}.desktop"
        : > "$out/.env"

        echo "sharun-bundle: $(find "$out/lib" -maxdepth 1 \( -type f -o -type l \) | wc -l) libraries bundled"
        du -sh "$out"
      '';

      doCheck = false;
      # installCheckPhase runs *after* installPhase, which is what we want.
      doInstallCheck = checkCommand != "";
      installCheckPhase = ''
        runHook preInstallCheck
        ${checkCommand}
        runHook postInstallCheck
      '';

      meta = {
        description = "${name} as a portable sharun AppDir (runs without Nix)";
        platforms = [ "x86_64-linux" ];
      };
    };

  # ---------------------------------------------------------------------------
  # mkTarball: wrap an AppDir in a .tar.zst (still no FUSE/AppImage runtime
  # needed, and it preserves the executable bits).
  # ---------------------------------------------------------------------------
  mkTarball = { name, appdir }:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "${name}-portable-tar";
      version = "1";
      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      dontFixup = true;
      nativeBuildInputs = [ pkgs.zstd pkgs.coreutils ];

      installPhase = ''
        set -eu
        mkdir -p "$out"
        # stage under a friendly name so the archive extracts to `uselib2-portable/`
        cp -r ${appdir} "./${name}-portable"
        chmod -R u+w "./${name}-portable"
        tar --zstd -cf "$out/${name}-portable-x86_64.tar.zst" "${name}-portable"
        echo "created $out/${name}-portable-x86_64.tar.zst"
      '';

      meta = {
        description = "${name} portable sharun bundle as a tar.zst";
        platforms = [ "x86_64-linux" ];
      };
    };

  # ---------------------------------------------------------------------------
  # mkAppImage: `runtime || squashfs` around an AppDir.  This is the only piece
  # that needs the AppImage runtime; the plain directory and tar.zst above are
  # the primary deliverables.
  # ---------------------------------------------------------------------------
  mkAppImage = { name, appdir }:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "${name}-portable-appimage";
      version = "1";
      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      dontFixup = true;
      nativeBuildInputs = [ pkgs.squashfsTools pkgs.coreutils ];

      installPhase = ''
        set -eu
        mkdir -p "$out"

        cp -r ${appdir} ./AppDir
        chmod -R u+w ./AppDir

        mksquashfs ./AppDir app.squashfs \
          -root-owned -noappend -comp zstd -quiet

        # uruntime embeds its launch policy as fixed-width strings in the ELF.
        # Force "try FUSE, then always extract" (URUNTIME_EXTRACT=2) so the
        # image also starts on machines without FUSE, whatever its size.
        cp ${appimageRuntime} ./runtime
        chmod u+w ./runtime
        sed -i 's/URUNTIME_EXTRACT=[0-9]/URUNTIME_EXTRACT=2/' ./runtime
        grep -a -q 'URUNTIME_EXTRACT=2' ./runtime

        cat ./runtime app.squashfs > "$out/${name}-x86_64.AppImage"
        chmod +x "$out/${name}-x86_64.AppImage"
        echo "created $out/${name}-x86_64.AppImage"
      '';

      meta = {
        description = "${name} as a single-file AppImage";
        platforms = [ "x86_64-linux" ];
      };
    };
in
{
  inherit sharun appimageRuntime mkPortable mkTarball mkAppImage;
}
