[« Previous: 21 — Extra platforms that need no LLVM build](../21-extra-platforms-no-llvm/README.md) · [Index](../README.md) · [Next: 23 — A C++ SDL3 + OpenGL app »](../23-cpp-opengl-portable/README.md)

# 22 — devkitPro with devkitNix

> **Goal.** Build the same two libraries with the **devkitPro** console
> toolchains — for the Game Boy Advance / DS / 3DS, the Nintendo Switch, and the
> GameCube / Wii / WiiU — using the external [`devkitNix`](https://github.com/bandithedoge/devkitNix)
> flake.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. What devkitPro and devkitNix are

**devkitPro** is the standard homebrew toolchain collection for Nintendo
consoles. It ships, per platform family, a full `gcc` + binutils + libc plus all
the console libraries (libnds, libctru, libnx, libogc, wut, ...) and portlibs.

**devkitNix** turns devkitPro's official **Docker images** into Nix derivations:
it pulls the image, unpacks `opt/devkitpro`, and runs `autoPatchelfHook` so the
binaries work on NixOS. It exposes:

| attribute | toolchain | targets |
|-----------|-----------|---------|
| `devkitARM` / `stdenvARM` | `arm-none-eabi-gcc` | GBA, NDS, 3DS |
| `devkitA64` / `stdenvA64` | `aarch64-none-elf-gcc` | Nintendo Switch |
| `devkitPPC` / `stdenvPPC` | `powerpc-eabi-gcc` | GameCube, Wii, WiiU |

## 2. Wiring it in

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";
  devkitNix.url = "github:bandithedoge/devkitNix";
  devkitNix.inputs.nixpkgs.follows = "nixpkgs";   # one universe
};

pkgs = import nixpkgs {
  inherit system;
  overlays = [ devkitNix.overlays.default ];        # adds pkgs.devkitNix.*
};
```

`devkitNix.inputs.nixpkgs.follows = "nixpkgs"` is worth doing: without it,
devkitNix uses its own (unstable) nixpkgs and you end up with two package sets.

## 3. The stdenvs do **not** set `$CC`

devkitNix's stdenvs add the toolchain to `nativeBuildInputs` and set `DEVKITPRO`
(and `DEVKITARM`/`DEVKITPPC`), but they are `stdenvNoCC`-based and do **not**
export `CC`. So we call the compiler and archiver by their store paths:

```nix
armGcc = "${arm}/opt/devkitpro/devkitARM/bin/arm-none-eabi-gcc";
armAr  = "${arm}/opt/devkitpro/devkitARM/bin/arm-none-eabi-ar";
a64Gcc = "${a64}/opt/devkitpro/devkitA64/bin/aarch64-none-elf-gcc";
ppcGcc = "${ppc}/opt/devkitpro/devkitPPC/bin/powerpc-eabi-gcc";
```

The builder is the same static-archive builder as elsewhere, only the tool paths
are explicit:

```nix
buildPhase = ''
  for f in add.c; do
    ${gcc} -O2 -Wall -Wextra -c "$f" -o "obj/…o"
  done
  ${ar} rcs "libadd.a" obj/*.o
'';
```

## 4. Run it

```sh
nix build .#devkitarm-libmul --max-jobs 1 --cores 1   # GBA / NDS / 3DS
nix build .#devkita64-libmul --max-jobs 1 --cores 1   # Switch
nix build .#devkitppc-libmul --max-jobs 1 --cores 1   # GameCube / Wii / WiiU
```

> The first build **pulls the devkitPro Docker images**, so it needs network
> access and downloads a few hundred megabytes per toolchain. That is inherent
> to how devkitNix works.

## 5. Verify

Three console architectures, one source file:

```sh
devkitarm:  ELF 32-bit LSB relocatable, ARM, EABI5 version 1 (SYSV)
devkita64:  ELF 64-bit LSB relocatable, ARM aarch64, version 1 (SYSV)
devkitppc:  ELF 32-bit MSB relocatable, PowerPC or cisco 4500, version 1 (SYSV)
```

Note the PowerPC object is **big-endian** (`MSB`) — a reminder that "cross" is
about much more than CPU family.

## 6. Using the libraries in a real homebrew project

devkitPro projects use a `Makefile` that reads `$DEVKITARM` / `$DEVKITPRO`. To
build an actual `.nds`, `.3ds`, `.nro` or `.dol`:

```nix
devShells.default = pkgs.mkShell.override { stdenv = pkgs.devkitNix.stdenvARM; } { };
```

Then `make` inside that shell finds the toolchain through the environment. The
libraries built here are ordinary static archives you can add to such a project's
link line.

## 7. Pitfalls

* **Expecting `$CC`.** devkitNix's stdenvs are `stdenvNoCC`-based; set the
  compiler path yourself (section 3).
* **Forgetting `devkitNix.inputs.nixpkgs.follows`.** You get two nixpkgs sets and
  confusing version mismatches.
* **No network.** `dockerTools.pullImage` is a fixed-output derivation: it must
  fetch the image the first time.
* **Shared libraries.** Console targets are bare metal; build static archives.
* **Architecture is not the whole story.** devkitPPC is big-endian; do not assume
  "ELF 32-bit" means the same layout as devkitARM.

## 8. The end of the guide

You have now built the same two libraries for:

bare-metal ARM (ch. 02), TCC/native (ch. 05–07), Linux (ch. 14), Windows (ch. 15),
Android (ch. 16), WebAssembly via Emscripten (ch. 17), musl / RISC-V / AVR / WASI
/ FreeBSD / Zig (ch. 21), and the three Nintendo toolchains (this chapter) —
plus a portable Linux bundle that runs without Nix (ch. 18) and FHS library
packages, dynamic and static (ch. 19–20).

The patterns repeat: **a target package set or an explicit toolchain**, **`$CC` or
a compiler path**, **ordinary Nix dependencies**, and **one core, one job**.

Next: [Appendix A — Troubleshooting & FAQ](../appendix-a-troubleshooting/README.md).

---

[« Previous: 21 — Extra platforms that need no LLVM build](../21-extra-platforms-no-llvm/README.md) · [Index](../README.md) · [Next: 23 — A C++ SDL3 + OpenGL app »](../23-cpp-opengl-portable/README.md)
