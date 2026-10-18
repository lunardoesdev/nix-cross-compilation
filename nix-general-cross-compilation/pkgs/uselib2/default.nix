# uselib2 - console program that uses libmul (which itself uses libadd).
{ callPackage, libadd, libmul }:
callPackage ../../lib/c-app.nix {
  pname = "uselib2";
  version = "1.0.0";
  src = ./.;
  sources = [ "main.c" ];
  deps = [ libmul libadd ];
  linkLibs = [ "mul" "add" ];
  checkCommand = ''
    output="$(./uselib2)"
    echo "$output"
    echo "$output" | grep -q 'mul(6, 7) = 42'
  '';
}
