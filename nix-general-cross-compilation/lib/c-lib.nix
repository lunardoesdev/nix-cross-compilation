# -----------------------------------------------------------------------------
# Generic builder for the demo's small C libraries.
#
# It deliberately avoids a build system so the *same* recipe can be driven by
# gcc (Linux), mingw-w64 (Windows), the NDK clang (Android) and emcc
# (Emscripten).  Only a few things differ per platform:
#
#   * Windows produces `libfoo.dll` + an import library `libfoo.dll.a`.
#   * ELF platforms (Linux/Android) produce a *versioned* shared object
#     `libfoo.so.<version>`, with the usual `libfoo.so.<major>` and `libfoo.so`
#     symlinks and `DT_SONAME = libfoo.so.<major>` — i.e. a real, distro-shaped
#     shared library.
#   * Emscripten is static-only (`shared = false`).
#
# Every library also gets a relocatable pkg-config file, so the outputs can be
# installed into an FHS prefix (`/usr`, `/usr/local`, ...) or used from a plain
# unpacked directory.
#
# `deps` are ordinary derivations passed by the caller (Nix manages them);
# headers are taken from `$dep/include`, libraries from `$dep/lib`.
# -----------------------------------------------------------------------------
{ lib
, stdenv
, pname
, version ? "1.0.0"
, src
, sources            # e.g. [ "add.c" ]
, headers ? []       # e.g. [ "add.h" ]
, libName            # e.g. "add" -> libadd.a / libadd.so.1.0.0 / libadd.dll
, deps ? []
, linkLibs ? []      # e.g. [ "add" ]; deps are searched with -L, these with -l
, shared ? true
, cc ? null          # override the compiler (used to pass emcc)
, ar ? null          # override the archiver (used to pass emar)
}:
let
  isWindows = stdenv.hostPlatform.isWindows;

  includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
  depFlags = lib.concatMapStringsSep " " (d: "-L${d}/lib") deps
    + " " + lib.concatMapStringsSep " " (l: "-l${l}") linkLibs;

  # `$CC`/`$AR` come from stdenv for the native toolchains; Emscripten passes
  # explicit paths to emcc/emar.
  ccCmd = if cc != null then cc else "$CC";
  arCmd = if ar != null then ar else "$AR";

  # ELF shared-library naming.
  soMajor = lib.versions.major version;
  soReal = "lib${libName}.so.${version}";
  soMajorLink = "lib${libName}.so.${soMajor}";
  soDevLink = "lib${libName}.so";

  # pkg-config file content; `${...}` is escaped so the shell/pkg-config sees it.
  pcFile = ''
    prefix=''${pcfiledir}/../..
    exec_prefix=''${prefix}
    libdir=''${prefix}/lib
    includedir=''${prefix}/include

    Name: lib${libName}
    Description: cross-compilation demo library (${pname})
    Version: ${version}
    Libs: -L''${libdir} -l${libName}${lib.concatMapStringsSep "" (l: " -l${l}") linkLibs}
    Cflags: -I''${includedir}
  '';
in
stdenv.mkDerivation {
  inherit pname version src;

  # Dependency passing is done the nixpkgs way.
  buildInputs = deps;

  strictDeps = true;
  dontConfigure = true;
  doCheck = false;

  # Requirement: never build with more than one job.
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild

    mkdir -p obj
    for f in ${lib.concatStringsSep " " sources}; do
      ${ccCmd} -O2 -fPIC -Wall -Wextra ${includeFlags} \
        -c "$f" -o "obj/$(basename "$f" .c).o"
    done

    ${arCmd} rcs "lib${libName}.a" obj/*.o
  '' + lib.optionalString shared (
    if isWindows then ''

      # PE/COFF: no SONAME, but we need an import library for our consumers.
      ${ccCmd} -shared -o "lib${libName}.dll" obj/*.o ${depFlags} \
        -Wl,--out-implib,"lib${libName}.dll.a"'' else ''

      # ELF (Linux and Android): versioned shared object + dev symlinks.
      ${ccCmd} -shared -Wl,-soname,"${soMajorLink}" \
        -o "${soReal}" obj/*.o ${depFlags}
      ln -sf "${soReal}" "${soMajorLink}"
      ln -sf "${soReal}" "${soDevLink}"''
  ) + ''

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/pkgconfig" "$out/include"
  '' + lib.optionalString isWindows ''    mkdir -p "$out/bin"
  '' + lib.concatMapStringsSep "\n"
    (line: "    ${line}")
    ([ ''cp "lib${libName}.a" "$out/lib/"'' ]
      ++ lib.optional shared (
        if isWindows
        then ''cp "lib${libName}.dll" "$out/bin/" && cp "lib${libName}.dll.a" "$out/lib/"''
        else ''
          cp "${soReal}" "$out/lib/"
          ln -sf "${soReal}" "$out/lib/${soMajorLink}"
          ln -sf "${soReal}" "$out/lib/${soDevLink}"''
      )
      ++ map (h: ''cp "${h}" "$out/include/"'') headers)
  + ''

    cat > "$out/lib/pkgconfig/lib${libName}.pc" <<'EOF'
    ${pcFile}
    EOF

    runHook postInstall
  '';

  meta = {
    description = "${pname} - demo C library (${libName})";
    platforms = lib.platforms.all;
  };
}
