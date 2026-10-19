[« Previous: Appendix D — Target cheat sheet](../appendix-d-target-cheatsheet/README.md) · [Index](../README.md) · [Next: none](../README.md)

# Appendix E — Cost and size

Cross-compiling is as much about *cost* as about correctness. This appendix
collects the numbers measured while writing the guide.

## 1. Portable Linux bundles (CLI demo)

| approach | artifact | size | needs Nix? | musl? | GL? |
|---|---|---|---|---|---|
| glibc bundle (ch. 18) | `tar.zst` | 182 MB *(SDL3 game)* | no | yes | host |
| glibc + sharun (ch. 18, CLI) | AppDir | ~40 MB | no | yes | — |
| musl-static (ch. 35) | AppImage | **1.4 MB** | no | yes | no |
| host-driver GL (ch. 27) | AppImage | **14 MB** | no | no | **GPU** |
| bundled Mesa (ch. 24) | AppImage | 89 MB | no | yes | software |
| `SHARUN_MESA_PATH` (ch. 26) | AppImage | ~90 MB | no | yes | software |
| `nix bundle` (ch. 42) | one file | 26 MB | no | no | host |

The GL bundles are large almost entirely because of **`libLLVM`** (Mesa's
`llvmpipe`). Upstream builds a Mesa without LLVM (see the
[overview](../23-gl-portability-overview/README.md), §4) — that is the single
biggest size win available.

## 2. Build weight

| thing | cost | why |
|---|---|---|
| `pkgsCross.mingwW64`, `musl64`, `riscv64`, `avr` | **cache only** | prebuilt toolchains |
| `pkgsCross.aarch64-android-prebuilt` | cache only | prebuilt NDK |
| `pkgsCross.aarch64-android` | **builds LLVM/bionic** | avoid |
| `libc = null` on `arm-none-eabi` | **builds a nolibc gcc** | avoid (ch. 09, 33) |
| `pkgsCross.aarch64-multiplatform` | cache only | GNU toolchain |
| `pkgsStatic` (musl) | cache only | prebuilt musl |
| Rust cross (`pkgsCross.*.rustPlatform`) | ~350 MB download | rust std per target |
| Go (pure, `CGO_ENABLED=0`) | native Go only | no cross toolchain |
| QEMU, OVMF, Android SDK | ~100–250 MB download | test/packaging tools |
| devkitNix | Docker images, hundreds of MB | upstream packaging |
| Mesa (GL) | pulls `libLLVM` | ~130 MB in the bundle |

Rule: if `nix build --dry-run` lists hundreds of "will be built" derivations,
you are about to compile a toolchain the slow way.

## 3. What actually gets built from source

In this guide, only these custom pieces were compiled from source:

* TinyCC (ch. 04) — small, seconds;
* our own libraries/apps — trivial;
* `libpng`/`zlib` for Windows (ch. 40) — small;
* the GL app itself.

Everything else came from the binary cache.

## 4. Time-saving checklist

1. Pin nixpkgs once (all chapters do).
2. Prefer `pkgsCross.*` that exist over hand-written `crossSystem` (cached).
3. Avoid changing `crossSystem.libc` on embedded targets (rebuilds gcc).
4. Use `pkgsCross.*-prebuilt` for Android.
5. `--max-jobs 1 --cores 1` — it does not make a cached build slower, and it
   keeps a from-source build usable.
6. Check with `--dry-run` before committing to a target.

---

[« Previous: Appendix D — Target cheat sheet](../appendix-d-target-cheatsheet/README.md) · [Index](../README.md) · [Next: none](../README.md)
