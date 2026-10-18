[« Previous: Appendix A — Troubleshooting & FAQ](../appendix-a-troubleshooting/README.md) · [Index](../README.md) · [Next: Appendix C — The single-core rule »](../appendix-c-build-script/README.md)

# Appendix B — Glossary

Every term used in the guide, in one place.

## Platforms

| term | meaning |
|------|---------|
| **buildPlatform** | the machine a build *executes* on |
| **hostPlatform** | the machine the *result* runs on |
| **targetPlatform** | what a produced *compiler* emits code for (equals `hostPlatform` except for a Canadian cross) |
| **native build** | `build == host`: compiler and result for the same machine |
| **cross build** | `build != host`: compiler on one machine, result for another |
| **Canadian cross** | a compiler that runs on machine A and emits code for machine C while being built on B |
| **GNU triple** | `<cpu>-<vendor>-<os><abi>`, e.g. `arm-none-eabi`, `x86_64-w64-mingw32` |
| **crossSystem** | the nixpkgs set describing the target (`config`, `libc`, `gcc.*`, ...) |
| **elaborate** | expand a name or `crossSystem` set into the full machine record |
| **targetPrefix** | the string nixpkgs puts before tool names, e.g. `arm-none-eabi-` (empty for native) |

## The toolchain

| term | meaning |
|------|---------|
| **toolchain** | `cc` + `binutils` + `libc` + the platform descriptions |
| **cc** | the compiler driver (`gcc`, `clang`, `arocc`, ...) |
| **binutils** | `as`, `ld`, `ar`, `nm`, `objcopy`, `ranlib`, `strip`, ... |
| **libc** | headers + start files + the C library (`glibc`, `musl`, `newlib`, ...) |
| **stdenv** | the build environment: bash, standard phases, and the toolchain |
| **cc-wrapper** | the package that wraps a compiler and injects flags; exports `CC` |
| **bintools wrapper** | the package that wraps binutils; exports `AR`/`AS`/`LD`/... |
| **setup hook** | `nix-support/setup-hook`, sourced by `setup.sh`, that sets env vars |
| **wrapCCWith** | build a `cc` package (driver + flags + setup hook) |
| **wrapBintoolsWith** | build a binutils package (tools + setup hook) |
| **`$CC` / `$AR` / `$LD`** | the variables build scripts use; supplied by setup hooks |
| **targetPrefix** | prefix deciding both tool names and the `-B`/`-idirafter` paths |
| **hardening** | security flags (`fortify`, `pic`, `relro`, `pie`, ...) |
| **`hardeningUnsupportedFlagsByTargetPlatform`** | compiler passthru listing flags the compiler rejects |
| **`nixSupport.cc-cflags`** | extra flags a compiler package contributes to the wrapper |
| **freestanding** | `libc = null`: no C library at all |
| **Canadian cross** | see above |

## Nix packaging

| term | meaning |
|------|---------|
| **derivation / `.drv`** | the build recipe Nix stores and realises |
| **fixed-output derivation (FOD)** | a derivation with a known hash (downloads, pinned blobs) |
| **closure** | a derivation plus everything it references |
| **`buildInputs`** | runtime-ish dependencies; their `include/`/`lib/` become `-isystem`/`-L` |
| **`nativeBuildInputs`** | build-time tools that run on the build machine |
| **`propagatedBuildInputs`** | dependencies forwarded to consumers |
| **`callPackage`** | instantiate a function with attributes from a package set |
| **overlay** | a function that customises a package set |
| **`pkgsCross.*`** | pre-defined cross package sets (e.g. `mingwW64`) |
| **`--max-jobs 1 --cores 1`** | build one derivation at a time, one core each |

## Binary formats & runtime

| term | meaning |
|------|---------|
| **ELF** | the executable format on Linux, Android, most Unixes |
| **PE/COFF** | the executable format on Windows |
| **WASM** | WebAssembly bytecode (Emscripten's output) |
| **SONAME** | the name a shared library records as its own identity (`libfoo.so.1`) |
| **RPATH / RUNPATH** | directories baked into an ELF for finding shared libraries |
| **`$ORIGIN`** | in an RPATH, "the directory of this file" — makes a tree relocatable |
| **interpreter / `elfinterp`** | the dynamic linker an ELF names (`ld-linux-*.so`) |
| **DT_NEEDED** | the list of libraries an ELF requires |
| **import library** | Windows `.dll.a` used to link against a DLL |
| **ABI** | the binary interface: calling convention, float handling, layout |

## Platforms & toolkits

| term | meaning |
|------|---------|
| **glibc** | GNU C Library (Linux default) |
| **musl** | a small, static-friendly C library (Alpine, `pkgsCross.musl64`) |
| **newlib** | a C library for bare-metal/embedded targets |
| **picolibc** | a small libc for embedded targets |
| **mingw-w64** | a Windows (PE) toolchain that runs on Linux |
| **NDK** | Android Native Development Kit (clang + bionic) |
| **bionic** | Android's libc |
| **Emscripten / `emcc`** | the compiler toolchain that targets WebAssembly |
| **devkitPro** | homebrew toolchains for Nintendo consoles (GBA/NDS/3DS/Switch/Wii) |
| **devkitNix** | a Nix flake providing devkitPro toolchains |
| **WASI** | WebAssembly System Interface; `wasm32-wasi` |
| **Zig** | a compiler whose `zig cc` can target many platforms from one binary |
| **FHS** | the Filesystem Hierarchy Standard (`/usr`, `/lib`, ...); "FHS distro" = a normal Linux |

## Portable Linux bundles

| term | meaning |
|------|---------|
| **sharun** | a static launcher that runs an AppDir with its own loader + libraries |
| **AppDir** | a directory layout sharun runs (`bin/`, `shared/bin/`, `lib/`, `.env`) |
| **quick-sharun** | an upstream shell wrapper around sharun (needs an Arch/FHS host) |
| **uruntime** | an AppImage runtime that falls back to extraction when FUSE is unavailable |
| **AppImage** | a single-file, self-mounting Linux application image |
| **`nixGL`** | a wrapper people use so Nix-built GL apps find the host GPU driver |
| **`nix-portable`** | a single-file Nix for machines without Nix |

---

[« Previous: Appendix A — Troubleshooting & FAQ](../appendix-a-troubleshooting/README.md) · [Index](../README.md) · [Next: Appendix C — The single-core rule »](../appendix-c-build-script/README.md)
