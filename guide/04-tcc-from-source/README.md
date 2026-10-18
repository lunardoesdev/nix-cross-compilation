[« Previous: 03 — The invisible chain](../03-the-invisible-chain/README.md) · [Index](../README.md) · [Next: 05 — Variant 1: name the driver `gcc` »](../05-tcc-driver-named-gcc/README.md)

# 04 — Building TCC from source

> **Goal.** Build a compiler that is **not** in nixpkgs — TinyCC — from source,
> and prove it can compile and link a real program. This prepares the ground for
> chapters 05–07, where we make it the `cc` of a stdenv in three different ways.

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. Why TCC?

Part 2 is about **replacing the `cc` part of a toolchain**. We need a compiler
that nixpkgs does not already package, so that the wiring is genuinely *ours* and
not hidden behind `pkgsCross.*` magic.

[TinyCC](https://bellard.org/tcc/) is perfect for the demonstration:

* it is tiny and builds in seconds;
* it has a GCC-compatible command line;
* it is *not* in nixpkgs, so we build it ourselves;
* it only emits **x86-64**, which forces us to be honest: this part of the guide
  is a **native** build (`build` = `host` = `x86_64-linux`). For a real cross
  target you would need a compiler with that target's backend, but the wiring you
  will learn is identical.

## 2. Building it

TCC is an ordinary C program, so it is built by the ordinary (native) stdenv:

```nix
tccSrc = pkgs.fetchurl {
  url = "https://github.com/TinyCC/tinycc/archive/refs/heads/mob.tar.gz";
  sha256 = "sha256-ljez32vc4VpWxEQYOxZLBx4VL27gkMcM8/eiKmGEt7c=";
};

tcc = pkgs.stdenv.mkDerivation {
  pname = "tcc";
  version = "mob";
  src = tccSrc;
  # ...
};
```

> `mob` is TCC's rolling development branch. We pin it by hash, so if upstream
> moves the branch the download fails loudly instead of changing silently. Swap
> the URL for a release tarball if you prefer.

The interesting part is `configure`. On a normal distro TCC finds `/usr/include`
and `/lib`; on NixOS there is no such thing, so every search path must be given
explicitly:

```sh
prefix="$out"
./configure --prefix="$prefix" --cc=$CC \
  --sysincludepaths="{B}/include:$prefix/include:${pkgs.glibc.dev}/include" \
  --crtprefix="$prefix/lib/tcc:${pkgs.glibc}/lib" \
  --libpaths="$prefix/lib/tcc:${pkgs.glibc}/lib" \
  --elfinterp="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
```

| flag | why it is needed |
|------|------------------|
| `--sysincludepaths` | where `stdio.h` etc. come from (`glibc.dev`); `{B}` is TCC's own build dir |
| `--crtprefix` | where `crt1.o`/`crti.o` live (needed to link an executable), plus TCC's private dir |
| `--libpaths` | where `libc.so` **and TCC's own `libtcc1.a`** are found |
| `--elfinterp` | the dynamic linker to embed in produced executables |

Every one of those four is a real bug we hit while writing this chapter — see
section 5.

## 3. The demo: compile with TCC directly

Before wiring TCC into a stdenv, use it by absolute path:

```nix
buildPhase = ''
  ${tcc}/bin/tcc -c add.c -o add.o
  $AR rcs libadd.a add.o
  ${tcc}/bin/tcc main.c libadd.a -o hello
'';
```

At this point `$CC` is still the native gcc; only the direct `${tcc}/bin/tcc`
calls use TCC. Chapter 05 changes that.

## 4. Run it

```sh
nix build .#tccDemo --max-jobs 1 --cores 1
./result/bin/hello
# add(6, 7) = 13
```

The flake also has a `checkPhase` that runs the program during the build, so a
broken toolchain fails the build instead of silently producing a bad binary:

```nix
doCheck = true;
checkPhase = ''
  output="$(./hello)"
  echo "$output"
  echo "$output" | grep -q 'add(6, 7) = 13'
'';
```

## 5. Verify, and the four traps we fell into

A working binary looks like this — note the Nix interpreter:

```sh
$ file result/bin/hello
result/bin/hello: ELF 64-bit LSB executable, x86-64, dynamically linked,
  interpreter /nix/store/…-glibc-2.44-25/lib/ld-linux-x86-64.so.2, …

$ $(nix eval --raw .#tcc)/bin/tcc -v
tcc version 0.9.28rc (x86_64 Linux)
```

Here are the traps, in the order we hit them. They are instructive because they
are *not* about Nix at all — they are about making a compiler work without
`/usr`:

1. **`tcc: error: file 'libtcc1.a' not found`.**
   TCC's own runtime library `libtcc1.a` is installed to `$out/lib/tcc`, but
   `tcc_add_support()` searches for it on the **library** path. It must appear in
   `--libpaths`, not (only) in `--crtprefix`.
2. **`{R}` expands to nothing.**
   TCC's `configure` substitutes `{B}` (build dir) but not `{R}` (install root),
   so `--crtprefix='{R}/lib/tcc:…'` silently became the useless `/lib/tcc`. Use
   the literal `$out` path, which is fixed at build time.
3. **Quoting in the Nix phase.** Nesting `'` and `"` inside a Nix `''` string is
   error-prone. Assign `prefix="$out"` in bash and use double quotes around the
   flags.
4. **`./hello: cannot execute: required file not found`.**
   The build *succeeded*, but the program could not start: TCC had embedded its
   default interpreter `/lib64/ld-linux-x86-64.so.2`, which does not exist on
   NixOS. `--elfinterp` fixes it.

Moral: on NixOS a "no-`/usr`" compiler is not just about `-I` and `-L`; the
**crt files** (`--crtprefix`), its **private runtime**
(`--libpaths` → `libtcc1.a`) and the **ELF interpreter** (`--elfinterp`) all have
to be pointed somewhere real.

## 6. What's next

TCC works, but we still call it by hand. The next three chapters make it the
stdenv's own compiler, in three increasingly low-level ways:

* [05 — name the driver `gcc`](../05-tcc-driver-named-gcc/README.md): reuse the
  nixpkgs cc-wrapper.
* [06 — ship your own `bin/cc`](../06-tcc-own-bin-cc/README.md): bypass the
  wrapper.
* [07 — write the `cc` package](../07-tcc-hand-written-cc/README.md): no
  `wrapCCWith` at all.

---

[« Previous: 03 — The invisible chain](../03-the-invisible-chain/README.md) · [Index](../README.md) · [Next: 05 — Variant 1: name the driver `gcc` »](../05-tcc-driver-named-gcc/README.md)
