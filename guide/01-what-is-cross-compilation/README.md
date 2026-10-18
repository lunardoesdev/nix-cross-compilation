[« Previous: none](../README.md) · [Index](../README.md) · [Next: 02 — Your first cross flake »](../02-first-cross-flake/README.md)

# 01 — What is cross-compilation?

> **Goal.** After this chapter you will know exactly what "cross-compile" means,
> what the three machine names (`build`, `host`, `target`) refer to, and what a
> toolchain is actually made of. You will also build your first
> cross-compiled artifact: a tiny `libadd` for bare-metal ARM.

The complete, runnable flake for this chapter is in
[`flake.nix`](flake.nix) next to this file.

---

## 1. Native builds and cross builds

Normally you compile code *for the machine you are sitting at*:

```
x86_64 Linux ──[ gcc ]──▶ x86_64 Linux program
```

The compiler runs on x86_64 Linux, and the program it produces also runs on
x86_64 Linux. That is a **native build**.

A **cross build** is the same idea with the two sides pulled apart:

```
x86_64 Linux ──[ arm-none-eabi-gcc ]──▶ ARM microcontroller program
```

The compiler still runs on your laptop, but the program it produces runs on a
completely different machine — here, a bare-metal ARM chip with no operating
system at all.

You cross-compile whenever the target cannot easily run a compiler itself:

* a microcontroller with kilobytes of RAM (this chapter),
* a phone (chapter 16),
* a web browser (chapter 17),
* a game console (chapter 22),
* or just a machine you do not have, to save time.

## 2. The three machines

Autotools gave us three names, and nixpkgs uses exactly the same ones:

| name | meaning | asked as | here |
|------|---------|----------|------|
| `buildPlatform` | where the *build* runs | "on what machine does `nix build` execute?" | `x86_64-linux` |
| `hostPlatform` | where the *result* runs | "on what machine will `libadd.a` be used?" | `arm-none-eabi` |
| `targetPlatform` | what a produced *compiler* emits code for | "if this package is a compiler, what does it compile for?" | `arm-none-eabi` |

For an ordinary cross build, **`hostPlatform == targetPlatform`**. We build one
compiler, which runs on `buildPlatform` and generates code for `hostPlatform`:

```
buildPlatform                hostPlatform
x86_64-linux        ┌──────────────┐        arm-none-eabi
   (compiler)  ─────┤ arm-none-eabi├─────▶  (object code runs here)
                    │    -gcc      │
                    └──────────────┘
```

The two only differ for a **Canadian cross**: a compiler that runs on one
machine *and* generates code for a third. That is a real technique but this
guide never needs it.

> **Why `hostPlatform` and not just "target"?** Because "target" already means
> something else: *what a compiler emits code for*. A cross-compiler's own
> `hostPlatform` is "where the compiler runs", while its `targetPlatform` is
> "what it compiles". Keeping both names avoids ambiguity.

## 3. GNU triples

Every platform has a short name, the **GNU target triple**:

```
< cpu > - < vendor > - < os > < abi >
   arm   -   none    - (none)  eabi
```

* **cpu** — the processor family: `x86_64`, `aarch64`, `arm`, `riscv64`, ...
* **vendor** — almost always `none`, `unknown` or `pc`. It carries no meaning
  for us; `none` is the conventional value for bare metal.
* **os** — the operating system: `linux`, `windows`, `android` — or *nothing*
  for bare metal.
* **abi** — `gnu`, `musl`, `eabi`, `eabihf`, ... This is the binary interface:
  calling convention, float handling, object format.

So `arm-none-eabi` reads as "ARM CPU, no vendor, no operating system, EABI ABI".

In nixpkgs you rarely write the triple as a string. You write a set and let
`lib.systems.elaborate` fill in the rest:

```nix
crossSystem = {
  config = "arm-none-eabi";  # the triple
  libc   = "newlib";         # which C library to link
};
```

## 4. What a toolchain is actually made of

People say "the toolchain" as if it were one thing. It is really **four
independent pieces**, and knowing them is the key to everything else in this
guide:

| piece | what it is | nixpkgs interface |
|-------|-----------|-------------------|
| **cc** | the compiler driver (`gcc`, `clang`, ...) | a package with a driver in `$out/bin` |
| **binutils** | `as`, `ld`, `ar`, `nm`, `objcopy`, `strip`, ... | `$out/bin/<prefix>{ar,as,ld,...}` + a `targetPrefix` |
| **libc** | headers, start files (`crt1.o`), the C library | `$out/include` + `$out/lib` |
| **platforms** | *which* machines, in the three roles above | `elaborate`d system descriptors |

A native toolchain is just those same four parts with an empty prefix and no
`crossSystem`. A cross toolchain is the same four parts with
`arm-none-eabi-` in front of every tool name.

nixpkgs already knows how to assemble a toolchain for a given `crossSystem`:

```nix
targetPkgs = import nixpkgs { inherit localSystem crossSystem; };
# targetPkgs.buildPackages.gcc       -> arm-none-eabi-gcc
# targetPkgs.buildPackages.binutils  -> arm-none-eabi-{as,ld,ar,...}
# targetPkgs.newlib                  -> the ARM newlib
```

## 5. Why Nix makes this pleasant

On a normal distro, cross-compiling means installing a *second*, parallel set of
packages (`gcc-arm-none-eabi`, `libnewlib-arm-none-eabi`, ...), keeping versions
in sync by hand, and hoping your build system picks the right ones.

Nix instead treats "a package set for platform P" as a value. You ask for
`import nixpkgs { crossSystem = ...; }` and you get a whole parallel universe of
packages — compiler, binutils, libc, SDL3, everything — already wired to that
platform. The next section uses it.

## 6. Walking through this chapter's flake

The flake is short; here are its important parts. All of it is heavily commented
in [`flake.nix`](flake.nix).

**Say which machines you care about.** This is the *only* place the target is
named:

```nix
localSystem = "x86_64-linux";
crossSystem = {
  config = "arm-none-eabi";
  libc   = "newlib";
};
```

**Turn names into full machine descriptions:**

```nix
buildPlatform  = nixpkgs.lib.systems.elaborate localSystem;
targetPlatform = nixpkgs.lib.systems.elaborate crossSystem;
```

**Get a package set for the target, and pick the toolchain parts out of it:**

```nix
targetPkgs = import nixpkgs { inherit localSystem crossSystem; };

cc       = targetPkgs.buildPackages.gcc;
binutils = targetPkgs.buildPackages.binutils;
libc     = targetPkgs.newlib;
```

**Assemble a stdenv from those parts.** This is the same thing
`pkgs.pkgsCross.arm-embedded` does internally:

```nix
stdenv = nativePkgs.stdenv.override {
  inherit buildPlatform;
  hostPlatform   = targetPlatform;
  targetPlatform = targetPlatform;
  inherit cc;
  hasCC = true;
  extraBuildInputs = [ ];
  overrides = _: _: { };
  allowedRequisites = null;
};
```

**Build a package with it — and notice what is *not* written:**

```nix
libadd = stdenv.mkDerivation {
  pname = "libadd";
  version = "1.0.0";
  src = ./src;

  dontConfigure = true;
  enableParallelBuilding = false;   # the single-core rule

  buildPhase = ''
    $CC -Os -c add.c -o add.o
    $AR rcs libadd.a add.o
  '';
  # ... install into $out/lib + $out/include
};
```

There is no `-I` for newlib, no `--target=arm-none-eabi`, no path to the
compiler. `$CC` and `$AR` are **already** the ARM tools, and the wrapper adds
newlib's include paths by itself. Chapter 03 dissects exactly how.

## 7. Run it

Always with a single core and a single job (see
[Appendix C](../appendix-c-build-script/README.md)):

```sh
nix build .#libadd --max-jobs 1 --cores 1
```

You can also inspect the decisions the flake made without building anything:

```sh
nix eval --raw .#platforms.build     # x86_64-linux
nix eval --raw .#platforms.host      # arm-none-eabi
nix eval --raw .#platforms.target    # arm-none-eabi
nix eval --raw .#crossSystem.libc    # newlib
nix eval --raw .#stdenv.cc.name      # arm-none-eabi-gcc-wrapper-16.2.0
```

## 8. Verify

`file(1)` on the produced archive proves it is ARM code, not x86:

```sh
$ file result/lib/libadd.a
result/lib/libadd.a: current ar archive

$ ar x result/lib/libadd.a && file add.o
add.o: ELF 32-bit LSB relocatable, ARM, EABI5 version 1 (SYSV), not stripped
```

`ELF 32-bit ... ARM` is the whole point. If you instead see `x86-64`, the
stdenv was not actually re-targeted.

## 9. Pitfalls

* **Using `pkgs.stdenv` directly.** `nativePkgs.stdenv` builds *native*
  packages. You must `override` it with the target platform, or use a
  `pkgsCross.*` set, as above.
* **Forgetting `allowedRequisites = null`.** The overridden stdenv mixes native
  and target packages, so the closure check must be disabled, otherwise
  evaluation fails.
* **Confusing `host` and `target`.** Read section 2 again; they are equal for
  everything in this guide, but naming them correctly now saves confusion later.
* **`libc = null`.** That means *freestanding* — no C library at all. It is
  correct for some bare-metal work but wrong if you call `printf` (chapter 09).

## 10. What's next

This chapter built **one** library. [Chapter 02](../02-first-cross-flake/README.md)
builds **two**, where the second depends on the first, and explains how Nix
passes that dependency — the pattern the rest of the guide reuses for every
platform.

---

[« Previous: none](../README.md) · [Index](../README.md) · [Next: 02 — Your first cross flake »](../02-first-cross-flake/README.md)
