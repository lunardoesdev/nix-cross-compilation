[« Previous: Appendix C — The single-core rule & build script](../appendix-c-build-script/README.md) · [Index](../README.md) · [Next: Appendix E — Cost and size »](../appendix-e-cost-size/README.md)

# Appendix D — Target cheat sheet

One table for every target used in the guide: how to name it in nixpkgs, the
triple, the object format, and where the result runs.

## Linux / ELF

| target | nixpkgs expression | triple | output | runs on | chapter |
|---|---|---|---|---|---|
| x86-64 glibc | `pkgs` | `x86_64-linux-gnu` | ELF 64 | x86-64 Linux | 14 |
| i686 glibc | `pkgs.pkgsi686Linux` | `i686-linux-gnu` | ELF 32 | i386/x86-64 Linux | 39 |
| x86-64 musl | `pkgs.pkgsCross.musl64` | `x86_64-linux-musl` | ELF 64 | any x86-64 Linux | 21 |
| x86-64 musl static | `pkgs.pkgsStatic` | `x86_64-linux-musl` | ELF 64 static | any x86-64 Linux | 35 |
| aarch64 | `pkgs.pkgsCross.aarch64-multiplatform` | `aarch64-linux-gnu` | ELF 64 | arm64 Linux | 21 |
| riscv64 | `pkgs.pkgsCross.riscv64` | `riscv64-linux-gnu` | ELF 64 | rv64 Linux | 21 |
| armv7 | `pkgs.pkgsCross.armv7l-hf-multiplatform` | `armv7l-linux-gnueabihf` | ELF 32 | armhf Linux | — |
| FreeBSD | `pkgs.pkgsCross.x86_64-freebsd` | `x86_64-freebsd` | ELF 64 | FreeBSD | 21 |

## Bare metal

| target | nixpkgs expression | triple | output | runs on | chapter |
|---|---|---|---|---|---|
| ARM Cortex-M | `config = "arm-none-eabi"; libc = "newlib"` | `arm-none-eabi` | ELF 32 / `.bin` | MCU / QEMU | 02, 33 |
| AVR | `pkgs.pkgsCross.avr` | `avr-none` | ELF 32 | ATmega / QEMU | 21 |
| RISC-V bare | `pkgs.pkgsCross.riscv64-embedded` | `riscv64-none` | ELF 64 | RV MCU | 21 |

## Windows / PE

| target | nixpkgs expression | triple | output | runs on | chapter |
|---|---|---|---|---|---|
| x86-64 | `pkgs.pkgsCross.mingwW64` | `x86_64-w64-mingw32` | PE32+ | Windows | 15 |
| i686 | `pkgs.pkgsCross.mingw32` | `i686-w64-mingw32` | PE32 | Windows | 39 |
| UEFI x86-64 | `pkgs.gnu-efi` + all-target binutils | n/a | PE32+ EFI | firmware | 41 |

## Mobile / web

| target | nixpkgs expression | triple / ABI | output | runs on | chapter |
|---|---|---|---|---|---|
| Android arm64 | `pkgs.pkgsCross.aarch64-android-prebuilt` | `aarch64-linux-android` | ELF 64 + APK | Android | 16, 34 |
| Android armv7 | `pkgs.pkgsCross.armv7a-android-prebuilt` | `armv7a-linux-androideabi` | ELF 32 | Android | — |
| Emscripten | `pkgs.emscripten` (`emcc`/`emar`) | `wasm32-unknown-emscripten` | `.wasm`+`.js`+`.html` | browser | 17 |
| WASI | `pkgs.pkgsCross.wasi32` | `wasm32-wasip1` | `.wasm` | wasm runtimes | 21 |

## Toolchain-only / games

| target | expression | triple | output | chapter |
|---|---|---|---|---|
| GBA/NDS/3DS | `devkitNix.devkitARM` | `arm-none-eabi` | ELF 32 | 22 |
| Switch | `devkitNix.devkitA64` | `aarch64-none-elf` | ELF 64 | 22 |
| GC/Wii/WiiU | `devkitNix.devkitPPC` | `powerpc-eabi` | ELF 32 **big-endian** | 22 |
| Zig multi-target | `pkgs.zig`, `zig cc -target …` | many | ELF/COFF/Mach-O | 21 |

## Platform fields (the three roles)

| field | meaning | example |
|---|---|---|
| `buildPlatform` | where the build runs | `x86_64-linux` |
| `hostPlatform` | where the result runs | `aarch64-linux` |
| `targetPlatform` | what a produced compiler emits | `arm-none-eabi` |

For a normal cross `host == target`; see [chapter 38](../38-canadian-cross/README.md)
for `build ≠ host ≠ target`.

## Handy one-liners

```sh
# what does a package set target?
nix eval --raw --impure --expr \
  '(import <nixpkgs> { crossSystem = "aarch64-linux"; }).stdenv.hostPlatform.system'

# what is the target prefix (tool names + -B/-idirafter)?
nix eval --raw --impure --expr \
  '(import <nixpkgs> { crossSystem = "arm-none-eabi"; }).stdenv.cc.targetPrefix'

# what format did I actually build?
file result/lib/*.a result/bin/* 2>/dev/null
```

---

[« Previous: Appendix C — The single-core rule & build script](../appendix-c-build-script/README.md) · [Index](../README.md) · [Next: Appendix E — Cost and size »](../appendix-e-cost-size/README.md)
