[« Previous: 01 — What is cross-compilation?](../01-what-is-cross-compilation/README.md) · [Index](../README.md) · [Next: 03 — The invisible chain »](../03-the-invisible-chain/README.md)

# 02 — Your first cross flake

> **Goal.** Build **two** C libraries for bare-metal ARM, where the second
> library depends on the first, and understand exactly how that dependency is
> passed. This is the smallest complete example of "cross-compile real code with
> Nix", and the pattern the rest of the guide reuses everywhere.

The complete, runnable flake is in [`flake.nix`](flake.nix); the C sources are in
[`src/`](src).

---

## 1. The two libraries

| library | source | depends on | provides |
|---------|--------|------------|----------|
| `libadd` | `src/add.c` | — | `int add(int, int)` |
| `libmul` | `src/mul.c` | **libadd** | `int mul(int, int)` |

`mul` is implemented with `add`, on purpose:

```c
int mul(int a, int b)
{
    int result = 0;
    for (int i = 0; i < b; i++)
        result = add(result, a);   /* <- real dependency on libadd */
    return result;
}
```

Because of that call, `libmul.a` contains an **undefined reference** to `add`,
and anything that finally links `libmul` must also link `libadd`. Making that
work is the whole point of the chapter.

## 2. The toolchain (recap from chapter 01)

```nix
crossSystem = {
  config = "arm-none-eabi";
  libc   = "newlib";
};

targetPkgs = import nixpkgs { inherit localSystem crossSystem; };

stdenv = nativePkgs.stdenv.override {
  inherit buildPlatform;
  hostPlatform   = targetPlatform;
  targetPlatform = targetPlatform;
  cc = targetPkgs.buildPackages.gcc;
  hasCC = true;
  extraBuildInputs = [ ];
  overrides = _: _: { };
  allowedRequisites = null;
};
```

Everything after this looks like an ordinary Nix package. That is the point.

## 3. `libadd`: the leaf package

```nix
libadd = stdenv.mkDerivation {
  pname = "libadd";
  version = "1.0.0";
  src = ./src;

  dontConfigure = true;
  enableParallelBuilding = false;     # one core, one job

  buildPhase = ''
    $CC -Os -c add.c -o add.o
    $AR rcs libadd.a add.o
  '';
  installPhase = ''
    mkdir -p $out/lib $out/include
    cp libadd.a $out/lib/
    cp add.h    $out/include/
  '';
};
```

Two variables, no paths:

* `$CC` is `arm-none-eabi-gcc` (through a wrapper; chapter 03 explains it).
* `$AR` is `arm-none-eabi-ar`.

Both are supplied by the stdenv's setup hooks.

## 4. `libmul`: the dependent package

```nix
libmul = stdenv.mkDerivation {
  pname = "libmul";
  version = "1.0.0";
  src = ./src;

  buildInputs = [ libadd ];
  propagatedBuildInputs = [ libadd ];

  dontConfigure = true;
  enableParallelBuilding = false;

  buildPhase = ''
    $CC -Os -c mul.c -o mul.o     # note: no -I anywhere
    $AR rcs libmul.a mul.o
  '';
  installPhase = ''
    mkdir -p $out/lib $out/include
    cp libmul.a $out/lib/
    cp mul.h    $out/include/
  '';
};
```

### Why is there no `-I`?

`mul.c` includes `add.h`, yet the build script never tells the compiler where
`add.h` lives. Nix does it for you:

1. `buildInputs = [ libadd ]` puts libadd's store path into the build
   environment.
2. The **cc-wrapper's setup hook** walks the dependencies and, for every one
   that has an `include/` directory, adds `-isystem <dep>/include` to
   `NIX_CFLAGS_COMPILE`.
3. `$CC` is a wrapper script that always prepends `NIX_CFLAGS_COMPILE`, so the
   flag reaches the real compiler.

You can see this happen with `NIX_DEBUG=1` (chapter 03 shows how). The relevant
line in the build log is:

```
-isystem /nix/store/…-libadd-arm-none-eabi-1.0.0/include
```

`buildInputs` is exactly how dependencies are passed in any nixpkgs package —
there is nothing cross-specific about it.

### Why `propagatedBuildInputs` as well?

`buildInputs` makes libadd available **while libmul is being built**.
`propagatedBuildInputs` forwards it to **anything that later depends on
libmul**. That matters because:

* linking against `libmul.a` leaves `add` unresolved, so the consumer needs
  `libadd.a` too;
* a consumer including `mul.h` very likely includes `add.h` as well.

Propagation means the consumer only has to name one dependency:

```nix
buildInputs = [ libmul ];   # brings libadd along for the ride
```

This is the same mechanism normal nixpkgs packages use to expose their own
dependencies.

## 5. Run it

```sh
nix build .#libadd --max-jobs 1 --cores 1
nix build .#libmul --max-jobs 1 --cores 1      # builds libadd first
```

Or inspect the environment the flake derived:

```sh
nix eval --raw .#env.stdenv.cc.name        # arm-none-eabi-gcc-wrapper-16.2.0
nix eval --raw .#env.binutils.name         # arm-none-eabi-binutils-wrapper-…
nix eval --raw .#env.libc.name             # newlib-arm-none-eabi-…
nix eval --raw .#env.targetPlatform.config # arm-none-eabi
```

## 6. Verify

Both archives must be ARM code, and `libmul` must reference `add`:

```sh
$ file result/lib/libmul.a
result/lib/libmul.a: current ar archive

$ mkdir /tmp/x && cd /tmp/x && ar x "$(nix build --no-link --print-out-paths \
       /home/you/02-first-cross-flake#libmul)/lib/libmul.a"
$ file mul.o
mul.o: ELF 32-bit LSB relocatable, ARM, EABI5 version 1 (SYSV), not stripped
$ nm mul.o | grep -E 'T mul|U add'
00000000 T mul
         U add        # <- resolved by libadd
```

The `U add` line is the visible proof that the dependency is real. `T mul` shows
the function was defined.

## 7. Pitfalls

* **Adding `-I${libadd}/include` by hand.** It works, but it defeats the point:
  dependencies should be declared in `buildInputs`, not hard-coded as paths.
  Let Nix inject the flag.
* **Forgetting `propagatedBuildInputs`.** The library still builds, but a
  consumer linking `libmul.a` fails with `undefined reference to 'add'`.
* **Using `pkgs.stdenv.mkDerivation` instead of the overridden stdenv.** You get
  x86_64 objects from an x86_64 compiler; `file` will say `x86-64`.
* **A `Makefile` that hard-codes `gcc`/`ar`.** Your recipe must use `$CC`/`$AR`
  (or `make` variables wired to them) so the toolchain can be replaced.

## 8. What's next

You have seen `$CC` used as if by magic. [Chapter 03](../03-the-invisible-chain/README.md)
opens the wrapper and shows the exact chain from the `cc` attribute to the
finished command line — the knowledge you need to plug in *your own* compiler later.

---

[« Previous: 01 — What is cross-compilation?](../01-what-is-cross-compilation/README.md) · [Index](../README.md) · [Next: 03 — The invisible chain »](../03-the-invisible-chain/README.md)
