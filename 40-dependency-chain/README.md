[« Previous: 39 — 32-bit targets and lib32](../39-32bit-and-lib32/README.md) · [Index](../README.md) · [Next: 41 — Exotic targets »](../41-exotic-targets/README.md)

# 40 — A realistic dependency chain: zlib → libpng → app

> **Goal.** Cross-compile a program that uses a **real** library stack —
> `libpng`, which depends on `zlib` — for Linux and Windows, using only
> `buildInputs` and pkg-config.

The complete flake is in [`flake.nix`](flake.nix); source in [`src/app.c`](src/app.c).

---

## 1. The chain

```
app  →  libpng  →  zlib
```

In nixpkgs, `libpng` has `propagatedBuildInputs = [ zlib ]`, so naming **one**
dependency gives you the whole chain:

```nix
buildInputs = [ target.libpng ];   # brings zlib too
```

That is the same propagation rule as chapter 02, but on real packages.

## 2. The app

[`src/app.c`](src/app.c) encodes a 2×2 RGB image to PNG **in memory** and reads
it back with libpng's simplified API, then prints the library versions:

```
png-demo: libpng 1.6.58 / zlib 1.3.2
png-demo: round-trip 2x2 ok (91 bytes)
```

No files, no GUI — just a real use of the API.

## 3. The build

```nix
mkApp = target: exeExt: target.stdenv.mkDerivation {
  src = ./src;
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ target.libpng ];
  buildPhase = ''
    $CC app.c -o png-demo${exeExt} $(pkg-config --cflags --libs libpng zlib)
  '';
};
```

Note the `zlib` in the `pkg-config` call — see the pitfall below.

## 4. Run it

```sh
nix build .#linux-png-demo   --max-jobs 1 --cores 1
nix build .#windows-png-demo --max-jobs 1 --cores 1
./result/bin/png-demo
```

## 5. Verify

```sh
$ ./result/bin/png-demo
png-demo: libpng 1.6.58 / zlib 1.3.2
png-demo: round-trip 2x2 ok (91 bytes)

$ file …/windows-png-demo/bin/png-demo.exe
…: PE32+ executable for MS Windows (console), x86-64
```

The Windows build also pulls `libpng.dll` and `zlib1.dll` next to the `.exe`
(because they are `DT_NEEDED`/import-library dependencies), so the `bin/`
directory is self-contained.

## 6. The pkg-config pitfall (this bit us)

`libpng.pc` lists zlib as:

```
Requires.private: zlib
```

`Requires.private` means "needed for a **static** link of libpng", not
"automatically on the command line for dynamic linking". Because our program
calls `zlibVersion()` **directly**, linking only `-lpng` fails:

```
undefined reference to symbol 'zlibVersion'
libz.so.1: error adding symbols: DSO missing from command line
```

The fix is to name zlib explicitly:

```sh
pkg-config --cflags --libs libpng zlib
```

Rule: **your `pkg-config` call must name every library your code calls
directly**, even if it is also a dependency of another one.

## 7. Pitfalls

* **Relying on `Requires.private`.** It does not put the library on the link
  line (section 6).
* **Forgetting the runtime closure.** For a shared build the `.dll`/`.so` must
  travel with the program; Nix links them into `bin/` for Windows, and the FHS
  chapters show how to bundle them on Linux.
* **Mixing target sets.** `buildInputs = [ pkgs.libpng ]` in a `mingwW64`
  derivation links a *native* library — always use `target.libpng`.
* **pkg-config and cross.** nixpkgs' pkg-config wrapper points at the **target**
  `.pc` files; do not set `PKG_CONFIG_PATH` by hand.
* **Assuming one dependency is enough for a *static* link.** Static linking needs
  the whole chain (`-lpng -lz -lm …`); pkg-config `--static` emits it.

## 8. What's next

[Chapter 41](../41-exotic-targets/README.md) leaves user space entirely: a
**UEFI** application and an out-of-tree **Linux kernel module**.

---

[« Previous: 39 — 32-bit targets and lib32](../39-32bit-and-lib32/README.md) · [Index](../README.md) · [Next: 41 — Exotic targets »](../41-exotic-targets/README.md)
