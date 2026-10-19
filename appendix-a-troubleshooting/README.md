[« Previous: 42 — `nix bundle` vs sharun](../42-nix-bundle-vs-sharun/README.md) · [Index](../README.md) · [Next: Appendix B — Glossary »](../appendix-b-glossary/README.md)

# Appendix A — Troubleshooting & FAQ

Real failures, mostly ones we hit while writing this guide, with their causes and
fixes. Search this page first when something breaks.

## Toolchain / `$CC`

**`error: include file 'stddef.h' not found`** (custom compiler)
The cc-wrapper injects `-B<cc-package>/lib`. For gcc that is where libgcc/crt
live, but a compiler like TCC reads `-B` as "my private dir" and replaces its
include search with `dir/include`. Point the package's `lib/` at the compiler's
real private directory (see chapter 05), or bypass the wrapper (chapter 06).

**`CC=[]` / `cc: command not found`**
The `cc` package exports no `CC`. Either the driver has a name the wrapper does
not recognise and there is no `bin/cc`, or the package lacks a
`nix-support/setup-hook`. A hand-written `cc` package *must* ship a setup hook
(chapter 07).

**`a set of value … is not equal to a string of value ''`** when evaluating a
`wrapCCWith`
The cc-wrapper asserts `libc_bin == bintools.libc_bin`. Give `wrapCCWith` and
`wrapBintoolsWith` the **same** `libc` value (chapter 08).

**Builds succeed but the binary is `x86-64`, not the target**
You used the native stdenv. Use `pkgsCross.*` or override the stdenv's
`hostPlatform`/`targetPlatform` (chapter 01), and confirm with `file`.

**`$CXX` points at a compiler with no C++ frontend**
The wrapper exports `CXX` even for C-only compilers. Ignore it, or provide a C++
driver.

## Cross / dependencies

**`undefined reference to 'add'`** when linking `libmul`
`libadd` was not propagated. Add `propagatedBuildInputs = [ libadd ];` (chapter
02) or link it explicitly.

**Headers not found although the dependency is in `buildInputs`**
`-isystem <dep>/include` is only injected for dependencies that have an
`include/` directory. Check the package actually installs headers there, or pass
`-I` explicitly.

**`file` reports the wrong architecture for `as`/`ld`**
Mismatched binutils. They must match the compiler's target (chapter 08).

## Emscripten / Android / Windows

**Emscripten: link errors about `main` or duplicate symbols**
Emscripten is static-only here; make sure the library is built with
`shared = false` and linked as an archive.

**Android: `libandroid` / `jni.h` missing**
The reduced `aarch64-android-prebuilt` sysroot lacks them. Build with the full
NDK toolchain (chapter 16).

**Windows: `undefined reference` at runtime / missing DLL**
A PE executable needs its `*.dll` next to it. Nix links them beside the `.exe`;
ship the whole `bin/` directory (chapter 15).

## Portable (FHS) bundles

**`env -i ./bin/app` fails to start**
The bundle must contain the dynamic linker and every `DT_NEEDED` library. Check
`lib/ld-linux-*.so.2` exists and that you did not strip the `lib/` directory
(chapter 18).

**Game does not render on a machine without a GPU driver**
The bundle deliberately ships **no** GPU drivers and relies on the host's. A
machine with no driver cannot render; that is the accepted trade-off (chapter
18).

**AppImage does not start without FUSE**
Use `uruntime` (which extracts when FUSE is unavailable) and make sure its
`URUNTIME_EXTRACT` policy is `2` (chapter 18).

**`/nix/store` paths still visible in the bundle**
`patchelf --remove-rpath` the bundled ELFs, and grep the tree for
`/nix/store`; chapter 18's build does this.

## TCC (chapters 04–07)

**`tcc: error: file 'libtcc1.a' not found`**
`libtcc1.a` lives in TCC's private dir, which TCC searches on the **library**
path. Put `$out/lib/tcc` in `--libpaths` (chapter 04).

**`{R}` in `--crtprefix` expands to nothing**
TCC's configure substitutes `{B}` but not `{R}`. Use the literal `$out` path.

**`cannot execute: required file not found`**
TCC embedded its default interpreter `/lib64/ld-linux-x86-64.so.2`. Pass
`--elfinterp=<glibc>/lib/ld-linux-x86-64.so.2` (chapter 04).

## Nix / evaluation

**`attribute 'x' missing`** in a flake output
Run `nix flake show` to see the actual attributes; outputs are namespaced by
system (`packages.x86_64-linux.*`).

**`experimental Nix feature 'nix-command' is disabled`**
Enable `experimental-features = nix-command flakes` in `nix.conf`.

**Android / other unfree package refused**
Set `config.allowUnfree = true;` when importing nixpkgs (the NDK is unfree).

**A build seems to hang or the machine becomes unresponsive**
You forgot the rule: always pass `--max-jobs 1 --cores 1` (Appendix C).

## FAQ

**Do I need `nix-portable` or `nixGL` for the FHS bundles?**
No. Chapter 18's bundles carry their own loader and userspace and use the host's
GPU drivers. That is the point.

**Do I need a compiler installed on my machine?**
No. Every toolchain comes from Nix.

**Why is TCC used for a *cross*-compilation guide?**
Because it is a compiler that is not in nixpkgs, so the wiring is genuinely
yours. TCC itself only targets x86-64, so Part 2 builds natively; the wiring is
identical for a real cross target.

**Can I add a platform not covered here?**
Yes — usually one row in the target table (chapter 11). If nixpkgs has a
`pkgsCross.*` for it and a binary-cached toolchain, no LLVM or gcc is built from
source.

---

[« Previous: 42 — `nix bundle` vs sharun](../42-nix-bundle-vs-sharun/README.md) · [Index](../README.md) · [Next: Appendix B — Glossary »](../appendix-b-glossary/README.md)
