# The Nix cross-compilation guide

A hands-on, chapter-by-chapter guide to **cross-compiling C with Nix**: from the
core concepts, through defining your own toolchain, up to building real
libraries and applications for Linux, Windows, Android, the web, embedded
targets, game consoles — and packaging the result so it runs on a normal
(non-Nix) Linux distribution.

Every chapter is **self-contained**. It ships its own complete `flake.nix` plus
the tiny C sources it needs, so you can `cd` into a chapter and build it without
reading any other chapter first.

```sh
cd 02-first-cross-flake
nix build .#libmul --max-jobs 1 --cores 1
```

## How to read this guide

Each chapter has the same shape:

1. **Goal** — what you will be able to do at the end.
2. **Why** — the reasoning, before any code.
3. **The flake** — a complete, heavily commented `flake.nix`.
4. **Run it** — the exact commands.
5. **Verify** — how to prove it actually worked.
6. **Pitfalls** — the mistakes that are easy to make.

Navigate with the links at the top and bottom of every chapter:

```
[« Previous: 02 — …](../02-first-cross-flake/README.md) · [Index](../README.md) · [Next: 04 — … »](../04-tcc-from-source/README.md)
```

## The single-core rule

**Every Nix command in this guide uses one core and one job.** Cross-compilation
toolchains are some of the heaviest things you can build, and a stray
`nix build` that fans out to all your cores can make a machine unusable. So:

* Every command is written `nix build … --max-jobs 1 --cores 1`.
* Every derivation sets `enableParallelBuilding = false;`.
* `scripts/build.sh` wraps the flags so you cannot forget them:

  ```sh
  ./scripts/build.sh .#libmul     # == nix build .#libmul --max-jobs 1 --cores 1
  ```

Appendix C collects the full rule and the script.

## Table of contents

### Part 1 — Fundamentals

| # | Chapter | What it covers |
|---|---------|----------------|
| 01 | [What is cross-compilation?](01-what-is-cross-compilation/README.md) | `build`/`host`/`target` platforms, GNU triples, the four parts of a toolchain, `stdenv.override`. |
| 02 | [Your first cross flake](02-first-cross-flake/README.md) | Two C libraries for bare-metal ARM (`arm-none-eabi` + newlib). |
| 03 | [The invisible chain](03-the-invisible-chain/README.md) | How Nix turns `cc` + `binutils` into `$CC`/`$AR`/`$LD` and where the flags come from. |

### Part 2 — Bring your own toolchain (worked example: TCC)

| # | Chapter | What it covers |
|---|---------|----------------|
| 04 | [Building TCC from source](04-tcc-from-source/README.md) | Why a compiler is just a package, and the three ways to plug one in. |
| 05 | [Variant 1 — name the driver `gcc`](05-tcc-driver-named-gcc/README.md) | Reuse the nixpkgs cc-wrapper. |
| 06 | [Variant 2 — ship your own `bin/cc`](06-tcc-own-bin-cc/README.md) | Bypass the wrapper with your own script. |
| 07 | [Variant 3 — write the `cc` package](07-tcc-hand-written-cc/README.md) | A driver plus `nix-support/setup-hook`, no `wrapCCWith`. |
| 08 | [Replacing binutils](08-replacing-binutils/README.md) | What makes a binutils "suitable". |
| 09 | [Replacing libc](09-replacing-libc/README.md) | newlib, newlib-nano, picolibc, freestanding, your own. |
| 10 | [Compiler metadata that changes flags](10-compiler-metadata-and-flags/README.md) | `hardeningUnsupportedFlags*`, `nixSupport.cc-cflags`. |

### Part 3 — Two libraries, many platforms

| # | Chapter | What it covers |
|---|---------|----------------|
| 11 | [One recipe, many targets](11-one-recipe-many-targets/README.md) | The target table and a generic C library builder. |
| 12 | [Two libraries that depend on each other](12-two-libraries-depending-on-each-other/README.md) | `libadd` → `libmul` with ordinary Nix dependencies. |
| 13 | [An application with dependencies](13-application-with-dependencies/README.md) | A console program and an SDL3 game. |

### Part 4 — The four headline targets

| # | Chapter | What it covers |
|---|---------|----------------|
| 14 | [Linux x86_64](14-target-linux/README.md) | The native build, as a baseline. |
| 15 | [Windows x86_64 (mingw-w64)](15-target-windows/README.md) | PE/COFF, import libraries, shipping the DLLs. |
| 16 | [Android arm64-v8a (NDK)](16-target-android/README.md) | The prebuilt NDK toolchain and a local SDL3. |
| 17 | [Emscripten (WebAssembly)](17-target-emscripten/README.md) | `emcc`, a local SDL3, and how to run the `.html`. |

### Part 5 — FHS Linux: run without Nix

| # | Chapter | What it covers |
|---|---------|----------------|
| 18 | [Portable bundles with sharun + uruntime](18-fhs-portable-sharun-uruntime/README.md) | A self-contained AppDir that needs neither `nix-portable` nor `nixGL`. |
| 19 | [FHS libraries — the dynamic way](19-fhs-libraries-dynamic/README.md) | `lib*.so.<version>`, SONAME, `$ORIGIN`. |
| 20 | [FHS libraries — the static way](20-fhs-libraries-static/README.md) | `lib*.a`, pkg-config, no runtime dependency. |

### Part 6 — More platforms at low cost

| # | Chapter | What it covers |
|---|---------|----------------|
| 21 | [Extra platforms that need no LLVM build](21-extra-platforms-no-llvm/README.md) | musl-static, riscv64 Linux, bare-metal AVR/riscv, WASI, Zig multi-target, FreeBSD. |
| 22 | [devkitPro with devkitNix](22-devkitpro-devkitnix/README.md) | The same two libraries for GBA/NDS/3DS, Switch and GameCube/Wii/WiiU. |

### Part 7 — Case study: a C++ OpenGL app that runs anywhere

| # | Chapter | What it covers |
|---|---------|----------------|
| 23 | [A C++ SDL3 + OpenGL app, portable to musl](23-cpp-opengl-portable/README.md) | A C++ SDL3 app drawing an OpenGL triangle, bundled with sharun + uruntime and a **bundled Mesa**, so it runs even on musl systems. |

### Appendices

| | Appendix | What it covers |
|---|----------|----------------|
| A | [Troubleshooting & FAQ](appendix-a-troubleshooting/README.md) | Common failures and what they mean. |
| B | [Glossary](appendix-b-glossary/README.md) | Every term used in the guide. |
| C | [The single-core rule & build script](appendix-c-build-script/README.md) | The exact flags and the wrapper script. |

## Repository layout

```
.
├── README.md                 # this index
├── scripts/
│   └── build.sh              # enforces --max-jobs 1 --cores 1
├── 01-what-is-cross-compilation/
│   ├── README.md
│   ├── flake.nix
│   └── src/
└── ...
```

This repository *is* the guide: every chapter sits at the top level as its own
directory.

## Requirements

* Nix with flakes: `experimental-features = nix-command flakes`.
* A network connection the first time you build a target (Nix downloads the
  cross toolchain from the binary cache).
* Nothing else. No compiler, no SDK, no Docker — except where a chapter says so
  explicitly (chapter 22 uses devkitNix, which pulls devkitPro images).
