[« Previous: 15 — Target: Windows x86_64](../15-target-windows/README.md) · [Index](../README.md) · [Next: 17 — Target: Emscripten »](../17-target-emscripten/README.md)

# 16 — Target: Android arm64-v8a (NDK)

> **Goal.** Build the two libraries and the console program for Android arm64,
> using the **prebuilt NDK** stdenv, and understand why that variant is the one
> to use.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The target, and why `-prebuilt`

```nix
pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
target = pkgs.pkgsCross.aarch64-android-prebuilt;
```

The Android NDK is **unfree**, so `config.allowUnfree = true` is required.

There are two Android cross sets in nixpkgs:

| set | what it does |
|-----|--------------|
| `aarch64-android-prebuilt` | downloads the ready-made NDK (clang + bionic) — **use this** |
| `aarch64-android` | builds the whole LLVM/bionic toolchain **from source** — avoid |

Building an Android toolchain from source means building LLVM, which is exactly
the "too complex toolchain" this guide avoids
([chapter 21](../21-extra-platforms-no-llvm/README.md)).

| part | value |
|------|-------|
| compiler | NDK clang (`aarch64-unknown-linux-android…-clang`) |
| object format | ELF (arm64) |
| libc | bionic |
| ABI | `arm64-v8a` |
| interpreter | `/system/bin/linker64` |
| runs on the build machine? | no |

## 2. Output shape: unversioned `.so`

Android convention is a plain `libfoo.so` (no versioned SONAME):

```sh
$CC -shared -o "libmul.so" obj/*.o -L… -ladd
```

The result is a normal arm64 ELF shared object:

```
libmul/lib/libmul.so   NEEDED libadd.so   (plus libc.so, libdl.so)
libmul/lib/libmul.a
```

## 3. Run it

```sh
nix build .#uselib2 --max-jobs 1 --cores 1
```

## 4. Verify

```sh
$ file …/bin/uselib2
…/bin/uselib2: ELF 64-bit LSB pie executable, ARM aarch64, dynamically linked,
  interpreter /system/bin/linker64, for Android 35, built by NDK r27 …

$ file …/libmul/lib/libmul.so
…/libmul.so: ELF 64-bit LSB shared object, ARM aarch64, for Android 35, NDK r27

$ readelf -d …/libmul/lib/libmul.so | grep NEEDED
 (NEEDED)  Shared library: [libadd.so]
 (NEEDED)  Shared library: [libdl.so]
 (NEEDED)  Shared library: [libc.so]
```

`NEEDED libadd.so` is the visible dependency; `linker64` is Android's dynamic
loader.

## 5. This is not an APK

The outputs are native arm64 ELF files, **not** a packaged Android app. To use
them:

* push the executable **and** `libadd.so` / `libmul.so` next to each other and
  run it on a device (e.g. via `adb push` and a shell), or
* drop the `.so` files into an APK's `jniLibs/arm64-v8a/`.

Packaging an APK is out of scope for this guide.

## 6. Pitfalls

* **Forgetting `allowUnfree`.** The build refuses with an "unfree package"
  error.
* **Choosing `aarch64-android`.** It tries to build the toolchain from source.
* **Expecting to run it.** You cannot execute arm64 Android binaries on an
  x86_64 build host, so there is no `checkPhase`.
* **Versioned `.so` names.** Android tooling expects `libfoo.so`; do not add
  SONAME symlinks here.
* **Missing sibling libraries.** `libmul.so` needs `libadd.so` at runtime; ship
  them together (or list them in the APK's `jniLibs`).

## 7. What's next

[Chapter 17](../17-target-emscripten/README.md) leaves ELF behind entirely and
compiles the same libraries to **WebAssembly** with Emscripten — where the
"executable" is an `.html` + `.js` + `.wasm` trio.

---

[« Previous: 15 — Target: Windows x86_64](../15-target-windows/README.md) · [Index](../README.md) · [Next: 17 — Target: Emscripten »](../17-target-emscripten/README.md)
