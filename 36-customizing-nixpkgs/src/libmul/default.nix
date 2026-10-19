{ stdenv, libadd }:

stdenv.mkDerivation {
  pname = "libmul";
  version = "1.0.0";
  src = ./.;

  buildInputs = [ libadd ];
  propagatedBuildInputs = [ libadd ];

  dontConfigure = true;
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -c mul.c -o mul.o
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
}
