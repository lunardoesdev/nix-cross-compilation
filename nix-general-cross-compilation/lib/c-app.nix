# -----------------------------------------------------------------------------
# Generic builder for the demo's console program.
#
# The same source is compiled by gcc, mingw-w64, NDK clang or emcc depending on
# the package set it is instantiated from.  Libraries are ordinary `deps`.
# -----------------------------------------------------------------------------
{ lib
, stdenv
, pname
, version ? "1.0.0"
, src
, sources ? [ "main.c" ]
, deps ? []
, linkLibs ? []          # e.g. [ "mul" "add" ]
, binName ? pname
, extraCflags ? ""
, extraLdflags ? ""
, checkCommand ? ""      # e.g. "test \"$(./uselib2)\" = ..." (native only)
}:
let
  isWindows = stdenv.hostPlatform.isWindows;
  exeExt = if isWindows then ".exe" else "";

  includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
  libraryFlags = lib.concatMapStringsSep " " (d: "-L${d}/lib") deps;
  linkFlags = lib.concatMapStringsSep " " (l: "-l${l}") linkLibs;

  canRun = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  runCheck = canRun && checkCommand != "";
in
stdenv.mkDerivation {
  inherit pname version src;

  buildInputs = deps;
  strictDeps = true;
  dontConfigure = true;
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild

    $CC -O2 -Wall -Wextra ${extraCflags} ${includeFlags} \
      ${lib.concatStringsSep " " sources} \
      -o "${binName}${exeExt}" \
      ${libraryFlags} ${linkFlags} ${extraLdflags}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp "${binName}${exeExt}" "$out/bin/"
    runHook postInstall
  '';

  doCheck = runCheck;
  checkPhase = lib.optionalString runCheck ''
    runHook preCheck
    ${checkCommand}
    runHook postCheck
  '';

  meta = {
    description = "${pname} - cross-compilation demo program";
    inherit (if isWindows then { mainProgram = "${binName}.exe"; } else { mainProgram = binName; }) mainProgram;
    platforms = lib.platforms.all;
  };
}
