[« Previous: 37 — CI with GitHub Actions](../37-ci-github-actions/README.md) · [Index](../README.md) · [Next: 39 — 32-bit targets and lib32 »](../39-32bit-and-lib32/README.md)

# 38 — The Canadian cross (and why `pkgsCross` does not nest)

> **Goal.** Understand the third platform role, see exactly which package sets
> nixpkgs provides for a cross toolchain, and learn why "a compiler that runs on
> ARM and targets RISC-V" is not a `pkgsCross` one-liner.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. Three platforms, four package sets

| role | meaning |
|---|---|
| **build** | where the *build* executes |
| **host** | where the produced *packages* run |
| **target** | what a produced *compiler* emits code for |

For an ordinary cross build `host == target` (chapter 01). A **Canadian cross**
is `build ≠ host ≠ target`: e.g. a compiler that *runs on ARM* and *targets
RISC-V*, built on x86-64.

nixpkgs names the package sets by `<theirHost><theirTarget>`:

| attribute | alias | triples for our cross set |
|---|---|---|
| `pkgsBuildBuild` | — | (x86_64, x86_64, x86_64) |
| `pkgsBuildHost` | **`buildPackages`** | **(x86_64, x86_64, arm)** |
| `pkgsHostTarget` | **`pkgs`** | **(x86_64, arm, arm)** |
| `pkgsTargetTarget` | `targetPackages` | (arm, arm, arm) — partial |

Read `buildPackages` as: *built on x86-64, runs on x86-64, targets ARM* — that is
where the cross compiler (`arm-none-eabi-gcc`) lives. `pkgs` is *built on x86-64,
**runs on ARM**, targets ARM* — the libraries and programs for the device.

## 2. See it

```sh
$ nix eval .#platformTriples --json
{"native":{"build":"x86_64-linux","host":"x86_64-linux","target":"x86_64-linux"},
 "cross":{"build":"x86_64-linux","host":"arm-none","target":"arm-none"},
 "buildPackages":{"build":"x86_64-linux","host":"x86_64-linux","target":"arm-none"}}
```

and the cross compiler itself:

```sh
$ nix eval --raw .#crossCompiler.name
arm-none-eabi-gcc-wrapper-…
```

The flake also builds `libadd` for the device (`file` → `ELF 32-bit … ARM,
EABI5`), which is just chapter 02 again.

## 3. Why `pkgsCross` does not nest

`pkgsCross` is defined as

```nix
# pkgs/top-level/stage.nix
pkgsCross = lib.mapAttrs (n: crossSystem: nixpkgsFun { inherit crossSystem; })
                         lib.systems.examples;
```

It **re-imports nixpkgs with the original `localSystem`** and a new
`crossSystem`. So

```nix
pkgs.pkgsCross.aarch64-multiplatform.pkgsCross.arm-embedded
```

does *not* mean "built on x86, runs on aarch64, targets arm". The second
`pkgsCross` resets the build platform, and you get (x86_64, arm, arm) again.
This is the trap the chapter exists to warn about.

## 4. What nixpkgs actually bootstraps

The current cross bootstrapping produces these stages:

```
(native, native, native)
(native, native, foreign)
(native, foreign, foreign)
```

`buildPackages` is the middle one; `pkgs` is the last one. There is **no
`(native, foreign, foreign₂)` stage**, and the missing splice is literally
`pkgsBuildTarget` — a compiler built on native, running on foreign, targeting a
third platform. That is why a true Canadian cross needs *more bootstrapping
stages* (see `doc/stdenv/cross-compilation.chapter.md`, "Bootstrapping").

## 5. What to do instead

* **A compiler that runs on the build machine and targets the device** — that is
  `cross.buildPackages.gcc`. This is the normal cross compiler, already built.
* **A compiler that runs on another machine** — cross-compile the compiler
  itself (a Canadian cross proper) or use a compiler that is inherently
  multi-target (clang/zig) and ship the target's sysroot.
* **A multi-target binary** — e.g. `zig cc -target …` (chapter 21) or clang with
  `--target=`, which sidesteps the whole bootstrap problem.

## 6. Verify

```sh
nix build .#libadd --max-jobs 1 --cores 1
ar x "$(nix build --no-link --print-out-paths .#libadd)/lib/libadd.a" && file add.o
# add.o: ELF 32-bit LSB relocatable, ARM, EABI5
nix eval .#platformTriples --json
```

## 7. Pitfalls

* **Nesting `pkgsCross`.** It resets the build platform (section 3).
* **Assuming `targetPackages.stdenv` exists.** `targetPackages` is a partial set
  (`pkgsTargetTarget`); many attributes are missing or special-cased.
* **Confusing `buildPackages` with "packages for the build machine".** It means
  *built on, running on* the build machine **and targeting** the target — it is
  the cross-compiler set.
* **Trying to get (x86, arm, riscv) from `import nixpkgs`.** The current
  bootstrap chain does not provide it.
* **Forgetting that host ≠ target is rare.** Most of the guide is the
  `build ≠ host == target` case; Canadian crosses are a compiler-building concern.

## 8. What's next

[Chapter 39](../39-32bit-and-lib32/README.md) adds **32-bit targets** and the
`lib/lib32` layout used by sharun bundles.

---

[« Previous: 37 — CI with GitHub Actions](../37-ci-github-actions/README.md) · [Index](../README.md) · [Next: 39 — 32-bit targets and lib32 »](../39-32bit-and-lib32/README.md)
