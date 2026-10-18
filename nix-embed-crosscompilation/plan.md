make a simple c library with function like int add
make second c library that uses first library and defines lets say int multiply using int add from previous library

using nix, describe building of those libraries for 5 embedded targets of your choice.
You must define those targets including their stdenv.

nix standard dependency system must be used to manage first c library being depndency of second one,
like dependencies work in any nix package.

I expect simple and well documented nix code.

ALWAYS USE SINGLE CORE AND SINGLE JOB FOR NIX! PASS NEEDED ARGUMENTS FOR THAT.
