[« Previous: 07 — Variant 3: write the `cc` package](../07-tcc-hand-written-cc/README.md) · [Index](../README.md) · [Next: 09 — Replacing libc »](../09-replacing-libc/README.md)

# 08 — Replacing binutils

> **Goal.** Replace the **binutils** half of a toolchain, and understand the one
> rule that decides whether a given binutils is suitable at all. You will also
> watch a mismatched pair fail on purpose.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. What binutils are, and what nixpkgs expects

`binutils` is the package of machine-level tools:

| tool | job |
|------|-----|
| `as` | assembler — turns assembly into object code |
| `ld` | linker — combines objects into an executable/shared library |
| `ar` | archiver — makes `.a` static libraries |
| `nm`, `objcopy`, `objdump`, `ranlib`, `readelf`, `strip`, ... | inspection and editing of objects |

The interface nixpkgs expects is small and precise:

```
$out/bin/<targetPrefix>{ar,as,ld,nm,objcopy,objdump,ranlib,strip,...}
```

plus a `targetPrefix` attribute (`""` native, `"arm-none-eabi-"` cross). The
bintools wrapper's setup hook turns those into `$AR`, `$AS`, `$LD`, `$NM`, ...

## 2. The one rule

> **Binutils must target the same architecture and object format as the code your
> compiler emits.**

That is the entire suitability rule.

* **gcc** → GNU binutils for the same triple (`arm-none-eabi-binutils` for the
  ARM target, plain x86-64 binutils for a native build).
* **TCC** → it has its own code generator *and assembler*, so it never calls
  `as`; it only needs `ar` (to archive) and `ld` (if it delegates linking).
* **A mismatch** → the assembler cannot parse the emitted assembly, and the
  linker rejects the object format.

## 3. Replacing them

`wrapBintoolsWith` is to binutils what `wrapCCWith` is to a compiler:

```nix
myBintools = nativePkgs.wrapBintoolsWith {
  bintools = nativePkgs.binutils-unwrapped;
  libc = nativePkgs.glibc;         # see the pitfall in section 6
};

myCC = nativePkgs.wrapCCWith {
  cc = nativePkgs.gcc-unwrapped;   # the RAW compiler
  bintools = myBintools;
  libc = nativePkgs.glibc;
};

stdenv = nativePkgs.stdenv.override {
  buildPlatform  = nativePkgs.stdenv.buildPlatform;
  hostPlatform   = nativePkgs.stdenv.hostPlatform;
  targetPlatform = nativePkgs.stdenv.targetPlatform;
  cc = myCC;
  hasCC = true;
  extraBuildInputs = [ ];
  overrides = _: _: { };
  allowedRequisites = null;
};
```

This chapter does it **natively**, because that is the case short enough to read
end-to-end. For a cross target the very same `wrapBintoolsWith`/`wrapCCWith`
calls are made by nixpkgs internally with the target's platform descriptions
filled in — see `pkgs/stdenv/cross/default.nix`.

> `cc = nativePkgs.gcc-unwrapped` — not `nativePkgs.gcc`. `wrapCCWith` looks for a
> driver named `gcc` in the package it is given. `pkgs.gcc` is *already a
> wrapper*, so it has no raw `gcc`; the unwrapped package does.

## 4. Build something with it

```nix
hello = stdenv.mkDerivation {
  pname = "hello-with-my-binutils";
  src = ./src;
  dontConfigure = true;
  enableParallelBuilding = false;
  buildPhase = ''
    echo "AR=$AR  -> $(command -v "$AR")"
    echo "LD=$LD  -> $(command -v "$LD")"
    $CC add.c main.c -o hello
  '';
  doCheck = true;
  checkPhase = '' … grep -q 'add(6, 7) = 13' … '';
};
```

```sh
nix build .#hello --max-jobs 1 --cores 1
./result/bin/hello
# add(6, 7) = 13
```

## 5. The negative test

A rule you never test is a rule you will get wrong. The flake ships a `mismatch`
output that emits ARM assembly and feeds it to the **x86-64** assembler, then
asserts that the assembler refuses:

```nix
mismatch = nativePkgs.runCommand "binutils-mismatch" {
  nativeBuildInputs = [ targetPkgs.buildPackages.gcc nativePkgs.binutils ];
} ''
  arm-none-eabi-gcc -S add.c -o add.s        # ARM assembly
  if as add.s -o add.o 2> err; then          # x86-64 assembler
    echo "ERROR: the x86-64 assembler accepted ARM assembly" >&2
    exit 1
  fi
  echo "as expected: the x86-64 assembler rejected ARM assembly:" > "$out"
  head -5 err >> "$out"
'';
```

```sh
$ nix build .#mismatch --max-jobs 1 --cores 1
$ cat result
as expected: the x86-64 assembler rejected ARM assembly:
---- assembler output ----
add.s:1: Error: unknown pseudo-op: `.cpu'
add.s:2: Error: no such architecture: `armv4t'
add.s:3: Error: unknown pseudo-op: `.fpu'
add.s:4: Error: unknown pseudo-op: `.eabi_attribute'
```

That is exactly what "unsuitable binutils" looks like: not a subtle
miscompilation, but an immediate, loud rejection.

## 6. Pitfalls

* **Mixing `libc` values.** The cc-wrapper asserts
  `libc_bin == bintools.libc_bin` (`pkgs/build-support/cc-wrapper/default.nix`).
  If you give the binutils `libc = null` but the compiler a real `libc`, evaluation
  fails with a confusing "a set of value … is not equal to a string of value ''".
  Give both the **same** libc.
* **Passing a wrapped compiler.** `wrapCCWith { cc = pkgs.gcc; }` finds no raw
  driver and installs nothing. Use `gcc-unwrapped`.
* **Forgetting the stdenv fields.** When overriding a *native* stdenv's `cc`, set
  the platform fields and `extraBuildInputs`/`overrides` too (as above), or
  evaluation can fail.
* **Assuming `ar`/`ld` are the only tools used.** A C++ toolchain may also need
  `nm`, `objcopy`, `strip`, `ranlib`. Wrap a complete binutils package, not a
  hand-picked binary.

## 7. What's next

Compiler ✔, binutils ✔. The last replaceable piece is the **C library**.
[Chapter 09](../09-replacing-libc/README.md) covers newlib, newlib-nano,
picolibc, `null` (freestanding) and your own libc package.

---

[« Previous: 07 — Variant 3: write the `cc` package](../07-tcc-hand-written-cc/README.md) · [Index](../README.md) · [Next: 09 — Replacing libc »](../09-replacing-libc/README.md)
