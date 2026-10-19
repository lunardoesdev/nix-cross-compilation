[« Previous: 08 — Replacing binutils](../08-replacing-binutils/README.md) · [Index](../README.md) · [Next: 10 — Compiler metadata that changes flags »](../10-compiler-metadata-and-flags/README.md)

# 09 — Replacing libc

> **Goal.** Replace the **C library** half of a toolchain, understand the
> difference between a *hosted* and a *freestanding* target, and know the
> embedded libc family and what it costs to switch between them.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. What `libc` is

A `libc` package is just a package with a fixed layout:

```
$out/include/   headers
$out/lib/       crt1.o, libc.a (and/or libc.so)
```

The compiler wrapper turns it into its flag files (chapter 03):

| file | from the libc |
|------|----------------|
| `libc-cflags` | `-idirafter <libc>/<target>/include` |
| `libc-crt1-cflags` | `-B <libc>/<target>/lib` |
| `libc-ldflags` | linker flags for the C library |

`libc = null` means **freestanding**: none of those flags are added, and nothing
is linked in.

## 2. Hosted vs freestanding

| | hosted | freestanding |
|---|---|---|
| libc | `glibc`, `musl`, `newlib`, ... | `null` |
| can call | `printf`, `malloc`, files, sockets, ... | only pure computation |
| typical use | Linux, Android, Windows | microcontrollers, kernels, bootloaders |

## 3. The embedded libc family

For bare-metal targets, `crossSystem.libc` picks which C library the compiler is
built against:

| value | what it is |
|-------|-----------|
| `"newlib"` | the classic embedded libc (default for `arm-none-eabi`) |
| `"newlib-nano"` | a size-optimised newlib |
| `"picolibc"` | a small libc for embedded targets |
| `null` | freestanding — no C library at all |

> **Cost warning.** On a *cross* target, changing `crossSystem.libc` changes the
> libc **the gcc cross compiler is built against**, so Nix builds a matching gcc
> *and* the libc from source the first time. That is slow (a from-source gcc is
> one of the heaviest builds there is). Prefer a target whose default libc is in
> the binary cache, or use a prebuilt toolchain. This is exactly the "don't build
> a complex toolchain" rule from [chapter 21](../21-extra-platforms-no-llvm/README.md).
>
> This chapter therefore demonstrates the substitution on the **native**
> toolchain, where it is cheap, and only tabulates the embedded options.

## 4. The substitution

```nix
mkToolchain = libc:
  let
    # binutils and cc MUST agree on libc (the cc-wrapper asserts it).
    bintools = pkgs.wrapBintoolsWith {
      bintools = pkgs.binutils-unwrapped;
      inherit libc;
    };
    cc = pkgs.wrapCCWith {
      cc = pkgs.gcc-unwrapped;
      bintools = bintools;
      inherit libc;
    };
    stdenv = pkgs.stdenv.override { … inherit cc; … };
  in
  { inherit stdenv cc bintools libc; };

hosted       = mkToolchain pkgs.glibc;   # normal Linux target
freestanding = mkToolchain null;         # no C library
```

## 5. Run it

```sh
nix build .#hello  --max-jobs 1 --cores 1   # hosted: calls printf
./result/bin/hello
# add(6, 7) = 13

nix build .#libadd --max-jobs 1 --cores 1   # freestanding: pure computation only
```

The `hello` output has a `checkPhase` that runs the program, so a broken libc
wiring fails the build.

## 6. Verify the difference

```sh
$ cat "$(nix eval --raw .#toolchains.hosted.cc)/nix-support/libc-cflags"
-idirafter /nix/store/…-glibc-2.44-25-dev/include -idirafter /nix/store/…/include-fixed

$ cat "$(nix eval --raw .#toolchains.freestanding.cc)/nix-support/libc-cflags"
cat: …/nix-support/libc-cflags: No such file or directory
```

The hosted wrapper injects the glibc include path; the freestanding one has **no
`libc-cflags` file at all**. That absence is what "freestanding" means in
practice.

## 7. Pitfalls

* **Freestanding code cannot call libc.** With `libc = null` there is no
  `printf`, no `malloc`, no start files. The link fails with undefined symbols
  (or the compiler cannot even find `<stdio.h>`).
* **`libc` must match between cc and binutils.** `wrapCCWith` and
  `wrapBintoolsWith` are asserted to agree, or evaluation fails (chapter 08).
* **Switching `crossSystem.libc` is expensive.** It rebuilds the cross gcc. See
  section 3.
* **A libc package needs the exact layout.** `$out/include` + `$out/lib`. If your
  own libc installs elsewhere, set `incdir`/`libdir` (see
  `pkgs/build-support/cc-wrapper`) or symlink.
* **`libc-ldflags` is often empty** (as it is for bare-metal newlib). An empty
  file is not a bug.

## 8. What's next

You can now replace all three toolchain parts. [Chapter 10](../10-compiler-metadata-and-flags/README.md)
closes Part 2 by showing the *metadata* a compiler package can carry to change
which flags the wrapper passes — both removing flags it cannot handle and adding
its own.

---

[« Previous: 08 — Replacing binutils](../08-replacing-binutils/README.md) · [Index](../README.md) · [Next: 10 — Compiler metadata that changes flags »](../10-compiler-metadata-and-flags/README.md)
