[« Previous: 38 — Canadian cross](../38-canadian-cross/README.md) · [Index](../README.md) · [Next: 40 — A realistic dependency chain »](../40-dependency-chain/README.md)

# 39 — 32-bit targets and `lib32` bundles

> **Goal.** Build our libraries and program for **i686-linux** and
> **i686-windows**, and package the 32-bit Linux build as a sharun bundle using
> the `lib32/` layout.

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. The two 32-bit targets

```nix
i686    = pkgs.pkgsi686Linux;      # i686-linux
mingw32 = pkgs.pkgsCross.mingw32;  # i686-windows (PE32)
```

| target | `file` | notes |
|---|---|---|
| `linux32-uselib2` | `ELF 32-bit LSB pie executable, Intel i386` | glibc, dynamic |
| `windows32-uselib2` | `PE32 executable for MS Windows (console), Intel i386` | mingw-w64 |

`pkgsi686Linux` is a complete 32-bit package set; on an x86-64 host its tools
run through 32-bit compatibility, so it builds natively.

Nothing else changes: the same `mkLib`/`mkApp` use `$CC`/`$AR` and `buildInputs`.
The cc-wrapper supplies the 32-bit include/library paths exactly as it does for
64-bit.

## 2. The bundle: `lib32/`, not `lib/`

`sharun` decides which directory to use from the target ELF:

* 64-bit ELF → `lib/` and `ld-linux-x86-64.so.2`
* **32-bit ELF → `lib32/` and `ld-linux.so.2`**

So the bundle looks like:

```
uselib2-portable-32/
├── bin/uselib2          -> sharun
├── shared/bin/uselib2   (ELF 32-bit)
├── lib32/
│   ├── ld-linux.so.2
│   ├── libc.so.6
│   └── … (35 libraries)
└── .env
```

There is **no `lib/`** at all. The flake copies the i686 glibc and the app's
`ldd` closure into `lib32/`, strips the store RPATHs, and lets sharun pick the
32-bit loader.

## 3. Run it

```sh
nix build .#portable32      --max-jobs 1 --cores 1
nix build .#linux32-uselib2 --max-jobs 1 --cores 1
nix build .#windows32-uselib2 --max-jobs 1 --cores 1
```

## 4. Verify

```sh
$ file …/linux32-uselib2/bin/uselib2
…: ELF 32-bit LSB pie executable, Intel i386 …
$ file …/windows32-uselib2/bin/uselib2.exe
…: PE32 executable for MS Windows (console), Intel i386
$ ls result/lib32/ld-linux.so.2 result/lib
result/lib32/ld-linux.so.2
ls: cannot access 'result/lib': No such file or directory
$ env -i result/bin/uselib2
uselib2: add(6, 7) = 13
uselib2: mul(6, 7) = 42
```

## 5. Why 32-bit still matters

* old hardware and old distros,
* Wine/Proton prefixes (often 32-bit or mixed),
* some proprietary SDKs ship 32-bit-only binaries,
* and a **mixed** bundle (both `lib/` and `lib32/`) is how launchers such as
  Steam ship 32- and 64-bit support together.

For a mixed bundle you would copy the 64-bit closure into `lib/` and the 32-bit
one into `lib32/`; sharun chooses per binary.

## 6. Caveats

* **The launcher is 64-bit.** The released `sharun-x86_64` is a static x86-64
  binary. It launches 32-bit apps on a 64-bit kernel with 32-bit compatibility,
  but it cannot run on a *pure* 32-bit system. There, use a 32-bit launcher (or a
  static musl 32-bit binary, [chapter 35](../35-musl-static-bundle/README.md)).
* **No 32-bit driver stack assumed.** The demo is a console app; a 32-bit GL app
  would need 32-bit Mesa/NVIDIA drivers on the host.
* **`pkgsi686Linux` is a full parallel set.** Do not mix its packages with the
  64-bit set; use `i686.callPackage` for everything in that target.

## 7. Pitfalls

* **Putting 32-bit libs in `lib/`.** sharun looks in `lib32/` for a 32-bit ELF;
  the app fails to start.
* **Wrong loader name.** 32-bit glibc uses `ld-linux.so.2`, not
  `ld-linux-x86-64.so.2`.
* **Running on a pure 32-bit kernel.** The x86-64 sharun will not start.
* **Mixing `-m32` into the 64-bit stdenv.** Use `pkgsi686Linux.stdenv` (or
  `pkgsCross.gnu32`) instead; `-m32` alone does not give you a 32-bit libc.
* **`file` says x86-64.** You accidentally used the normal `pkgs`.

## 8. What's next

[Chapter 40](../40-dependency-chain/README.md) stops using toy libraries and
cross-compiles a **real dependency chain**: zlib → libpng → an app.

---

[« Previous: 38 — Canadian cross](../38-canadian-cross/README.md) · [Index](../README.md) · [Next: 40 — A realistic dependency chain »](../40-dependency-chain/README.md)
