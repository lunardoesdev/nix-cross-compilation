# -----------------------------------------------------------------------------
# FHS-usable library bundle.
#
# `linux-libadd` / `linux-libmul` are normal Nix packages: they work fine inside
# Nix, but their shared objects carry a /nix/store RUNPATH.  This file turns a
# set of such libraries into a plain, distro-shaped tree
#
#     include/*.h
#     lib/*.a                 (static)
#     lib/*.so.<version>      (dynamic) + lib*.so.<major> and lib*.so symlinks
#     lib/pkgconfig/*.pc      (relocatable pkg-config files)
#
# with the shared objects' RUNPATH rewritten to `$ORIGIN`, so the tree can be
# dropped into `/usr`, `/usr/local`, an extracted tarball, a buildroot, etc.
# -----------------------------------------------------------------------------
{ pkgs }:
let
  mkFhsLibs =
    { name
    , version ? "1.0.0"
    , libs
    , testProgram ? ''
        #include <stdio.h>
        #include <add.h>
        #include <mul.h>
        int main(void)
        {
            printf("mul(6, 7) = %d\n", mul(6, 7));
            return mul(6, 7) == 42 ? 0 : 1;
        }
      ''
    }:
    pkgs.stdenv.mkDerivation {
      pname = "${name}-fhs-libs";
      inherit version;

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      # Keep the `$ORIGIN` RUNPATH we set below; do not add store RPATHs.
      dontFixup = true;

      nativeBuildInputs = [ pkgs.patchelf pkgs.pkg-config ];
      buildInputs = libs;

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/lib" "$out/include"

        for dep in ${pkgs.lib.concatMapStringsSep " " (l: "${l}") libs}; do
          # --no-preserve=mode: the source dirs are read-only store paths, and
          # we must keep merging into the same $out/lib across iterations.
          [ -d "$dep/lib" ]     && cp -a --no-preserve=mode,ownership "$dep"/lib/.     "$out/lib/"
          [ -d "$dep/include" ] && cp -a --no-preserve=mode,ownership "$dep"/include/. "$out/include/"
        done

        # store files are read-only
        chmod -R u+w "$out"

        # A relocatable RUNPATH: libmul.so finds libadd.so right next to it.
        find "$out/lib" -type f -name '*.so*' \
          -exec patchelf --set-rpath '$ORIGIN' {} \;

        echo "FHS library bundle contents:"
        find "$out" \( -type f -o -type l \) | sort
        runHook postInstall
      '';

      # Prove the tree is usable the way a distro would use it: once
      # dynamically and once statically.
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck

        cat > test.c <<'TEST_EOF'
        ${testProgram}
        TEST_EOF

        echo "== dynamic link =="
        $CC test.c -I"$out/include" -L"$out/lib" -lmul -ladd -o test_dynamic
        ./test_dynamic

        echo "== static link =="
        $CC test.c -I"$out/include" -L"$out/lib" \
          -Wl,-Bstatic -lmul -ladd -Wl,-Bdynamic -o test_static
        ./test_static

        echo "== pkg-config =="
        PKG_CONFIG_PATH="$out/lib/pkgconfig" pkg-config --cflags --libs libmul

        runHook postInstallCheck
      '';

      meta = {
        description = "${name} - static and shared C libraries for FHS distros";
        platforms = [ "x86_64-linux" ];
      };
    };

  mkLibsTarball = { name, dir }:
    pkgs.stdenv.mkDerivation {
      pname = "${name}-tar";
      version = "1";
      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      dontFixup = true;
      nativeBuildInputs = [ pkgs.zstd pkgs.coreutils ];

      installPhase = ''
        set -eu
        mkdir -p "$out"
        cp -r ${dir} "./${name}-x86_64"
        chmod -R u+w "./${name}-x86_64"
        tar --zstd -cf "$out/${name}-x86_64.tar.zst" "${name}-x86_64"
        echo "created $out/${name}-x86_64.tar.zst"
      '';

      meta = {
        description = "${name} libraries as a tar.zst for FHS distros";
        platforms = [ "x86_64-linux" ];
      };
    };
in
{
  inherit mkFhsLibs mkLibsTarball;
}
