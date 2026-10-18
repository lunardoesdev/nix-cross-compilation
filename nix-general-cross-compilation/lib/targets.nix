# -----------------------------------------------------------------------------
# Target (platform) table.
#
# Every entry is a *full nixpkgs package set* whose `stdenv` targets that
# platform.  That is the whole cross-compilation story: packages are written
# once, exactly like normal nixpkgs packages, and instantiated through the
# package set of the platform we want.  Nix resolves the compiler, the C
# library, pkg-config, SDL3 and every other dependency from the target set.
#
#   target.stdenv              -> the cross compiler wrapper
#   target.hostPlatform        -> the platform the output runs on
#   target.callPackage fn args -> instantiate `fn` with target dependencies
# -----------------------------------------------------------------------------
{ pkgs }:
{
  # 1. Native Linux x86_64 (glibc).  Also the recipe used for the portable
  #    sharun bundle.
  linux = pkgs;

  # 2. Windows x86_64 via mingw-w64.
  windows = pkgs.pkgsCross.mingwW64;

  # 3. Android arm64-v8a (NDK clang + prebuilt bionic libc).
  android = pkgs.pkgsCross.aarch64-android-prebuilt;

  # 4. Emscripten / WebAssembly.
  #
  # `pkgs.emscriptenStdenv` (a gcc stdenv whose mkDerivation runs emconfigure)
  # is only useful for autoconf projects.  SDL3 and our tiny packages use
  # CMake / direct compiler calls, so we keep the normal package set and pass
  # `${pkgs.emscripten}/bin/emcc` explicitly.  This is still ordinary Nix
  # dependency management: `emscripten` is a buildInput.
  emscripten = pkgs;
}
