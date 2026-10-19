# A normal callPackage-able package, so it supports `.override { ... }`.
{ stdenv, optLevel ? "-O2" }:

stdenv.mkDerivation {
  pname = "libadd";
  version = "1.0.0";
  src = ./.;

  dontConfigure = true;
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild
    $CC ${optLevel} -c add.c -o add.o
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
}
