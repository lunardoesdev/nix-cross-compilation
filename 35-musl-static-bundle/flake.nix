{
  description = "Chapter 35 — a musl-static app + sharun bundle: the 'runs anywhere' case";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # =======================================================================
      # The fully static package set.
      # =======================================================================
      # `pkgsStatic` is nixpkgs built with musl and every library static.  A
      # binary from here has no dynamic loader and no libc dependency at all.
      static = pkgs.pkgsStatic;

      libadd = static.stdenv.mkDerivation {
        pname = "libadd";
        version = "1.0.0";
        src = ./src;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC -Os -c add.c -o add.o
          $AR rcs libadd.a add.o
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/include
          cp libadd.a $out/lib/
          cp add.h    $out/include/
          runHook postInstall
        '';
      };

      libmul = static.stdenv.mkDerivation {
        pname = "libmul";
        version = "1.0.0";
        src = ./src;
        buildInputs = [ libadd ];
        propagatedBuildInputs = [ libadd ];
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC -Os -c mul.c -o mul.o
          $AR rcs libmul.a mul.o
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/include
          cp libmul.a $out/lib/
          cp mul.h    $out/include/
          runHook postInstall
        '';
      };

      uselib2 = static.stdenv.mkDerivation {
        pname = "uselib2";
        version = "1.0.0";
        src = ./src;
        buildInputs = [ libmul libadd ];
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC -Os main.c -o uselib2 \
            -I"${libmul}/include" -I"${libadd}/include" \
            -L"${libmul}/lib" -lmul -L"${libadd}/lib" -ladd
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp uselib2 $out/bin/
          runHook postInstall
        '';
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          output="$(./uselib2)"; echo "$output"
          echo "$output" | grep -q 'mul(6, 7) = 42'
          runHook postCheck
        '';
        meta.mainProgram = "uselib2";
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
      # The bundle: a STATIC binary + sharun, and nothing else.
      # =======================================================================
      # No glibc, no loader, no libraries.  sharun notices the target is a static
      # ELF and just executes it; it is still useful as the AppDir/AppImage
      # wrapper and for the `.desktop` integration.
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
          pname = "${name}-portable-static";
          version = "1";
          dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
          nativeBuildInputs = with pkgs; [ bash coreutils findutils gnused gnugrep patchelf ];
          installPhase = ''
            set -eu
            bin="${uselib2}/bin/${mainProgram}"
            mkdir -p "$out/bin" "$out/shared/bin"

            cp -L "$bin" "$out/shared/bin/${mainProgram}"
            cp -L ${sharun} "$out/sharun"; chmod +x "$out/sharun"
            ln "$out/sharun" "$out/AppRun"
            ln "$out/sharun" "$out/bin/${mainProgram}"

            # Nothing else: no lib/, no loader.
            : > "$out/.env"
            cp ${desktopFile} "$out/${name}.desktop"
            echo "bundle contents:"
            find "$out" \( -type f -o -type l \) | sort
          '';
          doInstallCheck = checkCommand != "";
          installCheckPhase = ''
            runHook preInstallCheck
            ${checkCommand}
            runHook postInstallCheck
          '';
        };

      portable = mkPortable {
        name = "uselib2";
        checkCommand = ''
          # no dynamic loader and no lib directory at all
          ! test -e "$out/lib/ld-linux-x86-64.so.2"
          ! test -d "$out/lib"
          # and it runs with a completely empty environment
          output="$(env -i "$out/bin/uselib2")"
          echo "$output"
          echo "$output" | grep -q 'mul(6, 7) = 42'
        '';
      };

      mkTarball = { name, appdir }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable-static-tar";
          version = "1";
          dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
          nativeBuildInputs = [ pkgs.zstd pkgs.coreutils ];
          installPhase = ''
            set -eu
            mkdir -p "$out"
            cp -r ${appdir} "./${name}-portable-static"
            chmod -R u+w "./${name}-portable-static"
            tar --zstd -cf "$out/${name}-portable-static-x86_64.tar.zst" "${name}-portable-static"
          '';
        };

      mkAppImage = { name, appdir }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "${name}-portable-static-appimage";
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
            cat ./runtime app.squashfs > "$out/${name}-static-x86_64.AppImage"
            chmod +x "$out/${name}-static-x86_64.AppImage"
          '';
        };
    in
    {
      packages.${system} = {
        inherit libadd libmul uselib2 sharun;
        portable = portable;
        portable-tar = mkTarball { name = "uselib2"; appdir = portable; };
        portable-appimage = mkAppImage { name = "uselib2"; appdir = portable; };
        default = portable;
      };
    };
}
