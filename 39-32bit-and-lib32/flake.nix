{
  description = "Chapter 39 — 32-bit targets and the lib32 bundle layout";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # i686-linux: the 32-bit x86 Linux package set (built on this x86_64 host
      # via 32-bit compatibility).
      i686 = pkgs.pkgsi686Linux;

      # i686-windows: 32-bit PE, for comparison.
      mingw32 = pkgs.pkgsCross.mingw32;

      mkLib = stdenv: { pname, sources, headers, deps ? [] }:
        stdenv.mkDerivation {
          inherit pname;
          version = "1.0.0";
          src = ./src;
          buildInputs = deps;
          dontConfigure = true;
          enableParallelBuilding = false;
          buildPhase = ''
            runHook preBuild
            mkdir -p obj
            for f in ${nixpkgs.lib.concatStringsSep " " sources}; do
              $CC -O2 -fPIC -c "$f" -o "obj/$(basename "$f" .c).o"
            done
            $AR rcs "lib${pname}.a" obj/*.o
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/lib" "$out/include"
            cp "lib${pname}.a" "$out/lib/"
            ${nixpkgs.lib.concatMapStringsSep "\n" (h: ''cp "${h}" "$out/include/"'') headers}
            runHook postInstall
          '';
        };

      # buildInputs supply -isystem/-L via the cc-wrapper, so only -l flags here.
      mkApp = stdenv: exeExt: deps: stdenv.mkDerivation {
        pname = "uselib2";
        version = "1.0.0";
        src = ./src;
        buildInputs = deps;
        dontConfigure = true;
        enableParallelBuilding = false;
        buildPhase = ''
          runHook preBuild
          $CC -O2 main.c -o uselib2${exeExt} -lmul -ladd
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cp uselib2${exeExt} $out/bin/
          runHook postInstall
        '';
      };

      mkFor = stdenv: exeExt:
        let
          libadd = mkLib stdenv { pname = "add"; sources = [ "add.c" ]; headers = [ "add.h" ]; };
          libmul = mkLib stdenv { pname = "mul"; sources = [ "mul.c" ]; headers = [ "mul.h" ]; deps = [ libadd ]; };
          uselib2 = mkApp stdenv exeExt [ libmul libadd ];
        in
        { inherit libadd libmul uselib2; };

      linux32 = mkFor i686.stdenv "";
      win32 = mkFor mingw32.stdenv ".exe";

      sharun = pkgs.fetchurl {
        url = "https://github.com/pkgforge-dev/Anylinux-sharun/releases/download/3.5.1/sharun-x86_64";
        hash = "sha256-XbkqdJL4sb75wrplM0ZDaot8xBMSZxWlCZPKBdl0ZbQ=";
      };

      # =======================================================================
      # A 32-bit sharun bundle: everything goes in `lib32/`, not `lib/`.
      # =======================================================================
      portable32 = pkgs.stdenvNoCC.mkDerivation {
        pname = "uselib2-portable-32";
        version = "1";
        dontUnpack = true; dontConfigure = true; dontBuild = true; dontFixup = true;
        nativeBuildInputs = with pkgs; [ bash coreutils findutils gnused gnugrep patchelf ];
        installPhase = ''
          set -eu
          bin="${linux32.uselib2}/bin/uselib2"
          mkdir -p "$out/bin" "$out/shared/bin" "$out/lib32"

          cp -L "$bin" "$out/shared/bin/uselib2"
          cp -L ${sharun} "$out/sharun"; chmod +x "$out/sharun"
          ln "$out/sharun" "$out/AppRun"
          ln "$out/sharun" "$out/bin/uselib2"

          # 32-bit glibc + loader into lib32/
          cp -L ${i686.glibc}/lib/*.so* "$out/lib32/"
          chmod -R u+w "$out/lib32"

          ${i686.glibc.bin}/bin/ldd "$out/shared/bin/uselib2" 2>/dev/null \
            | grep -o '/nix/store/[^ ]*' | sort -u \
            | while IFS= read -r l; do
                cp -Lf --no-preserve=mode,ownership "$l" "$out/lib32/$(basename "$l")"
              done

          test -f "$out/lib32/ld-linux.so.2" || { echo "no 32-bit loader" >&2; exit 1; }

          chmod -R u+w "$out/lib32" "$out/shared/bin"
          for f in "$out"/lib32/*.so* "$out/shared/bin/uselib2"; do
            [ -f "$f" ] || continue; [ -L "$f" ] && continue
            case "$(basename "$f")" in ld-*) continue ;; esac
            if [ "$(dd if="$f" bs=1 count=4 2>/dev/null)" = "$(printf '\177ELF')" ]; then
              patchelf --remove-rpath "$f" || true
            fi
          done

          : > "$out/.env"
          echo "32-bit bundle: $(find "$out/lib32" -maxdepth 1 -type f | wc -l) libs"
        '';
        doInstallCheck = true;
        installCheckPhase = ''
          runHook preInstallCheck
          output="$(env -i "$out/bin/uselib2")"
          echo "$output"
          echo "$output" | grep -q 'mul(6, 7) = 42'
          runHook postInstallCheck
        '';
      };
    in
    {
      packages.${system} = {
        "linux32-libadd" = linux32.libadd;
        "linux32-libmul" = linux32.libmul;
        "linux32-uselib2" = linux32.uselib2;
        "windows32-libadd" = win32.libadd;
        "windows32-libmul" = win32.libmul;
        "windows32-uselib2" = win32.uselib2;
        portable32 = portable32;
        default = portable32;
      };
    };
}
