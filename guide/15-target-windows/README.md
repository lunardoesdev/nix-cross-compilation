[« Previous: 14 — Target: Linux x86_64](../14-target-linux/README.md) · [Index](../README.md) · [Next: 16 — Target: Android arm64-v8a »](../16-target-android/README.md)

# 15 — Target: Windows x86_64 (mingw-w64)

> **Goal.** Build the two libraries and the console program for Windows, and
> learn what changes when the object format is PE/COFF instead of ELF: import
> libraries, DLLs, and no SONAME.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The target

```nix
target = pkgs.pkgsCross.mingwW64;
```

`mingwW64` is a complete nixpkgs set whose stdenv is **mingw-w64**: a toolchain
that runs on Linux and produces Windows executables. The compiler is
`x86_64-w64-mingw32-gcc`.

| part | value |
|------|-------|
| compiler | `x86_64-w64-mingw32-gcc` |
| object format | PE/COFF |
| libc | mingw's C runtime (part of the toolchain) |
| program extension | `.exe` |
| runs on the build machine? | **no** |

## 2. What changes: shared libraries

ELF and PE disagree about how a shared library is named and linked:

| | Linux (ELF) | Windows (PE) |
|---|---|---|
| shared library | `libmul.so.1.0.0` | `libmul.dll` |
| version identity | `SONAME libmul.so.1` | none |
| link against it with | `-lmul` (via `libmul.so`) | `libmul.dll.a` (import library) |
| executable suffix | — | `.exe` |

So the builder's shared step differs:

```sh
# Windows: build the DLL and an import library
$CC -shared -o "libmul.dll" obj/*.o -L… -ladd -Wl,--out-implib,"libmul.dll.a"
```

The **import library** (`libmul.dll.a`) is the piece consumers link against; the
`.dll` itself is only needed at *runtime*.

## 3. Run it

```sh
nix build .#uselib2 --max-jobs 1 --cores 1
ls "$(nix build --no-link --print-out-paths .#uselib2)/bin"
# libadd.dll  libmul.dll  uselib2.exe
```

## 4. Verify

The executable is a PE image:

```sh
$ file …/bin/uselib2.exe
…/bin/uselib2.exe: PE32+ executable for MS Windows 5.02 (console), x86-64 …
```

`libmul` produces both a DLL and an import library:

```sh
$ ls …/libmul-…/bin   →  libadd.dll  libmul.dll
$ ls …/libmul-…/lib   →  libmul.a    libmul.dll.a
```

Notice that `libadd.dll` is present **next to** `libmul.dll`: because `libmul`
depends on `libadd`, Nix linked the dependency's DLL into the same `bin/`
directory, so the `bin/` tree is self-contained.

You cannot run `uselib2.exe` here (no Windows), so the flake does not add a
`checkPhase`. To test it, copy the whole `bin/` directory to a Windows machine or
run it under Wine.

## 5. Pitfalls

* **Copying only the `.exe`.** A PE executable is not self-contained; every
  `*.dll` it imports must travel with it. Keep the whole `bin/` directory.
* **Linking against the `.dll`.** Link against the **import library**
  (`libmul.dll.a`), not the DLL. With `-L<dir> -lmul` the linker picks the
  import library automatically.
* **Expecting a SONAME.** PE has none; do not add `-Wl,-soname` on Windows.
* **Running the binary in `checkPhase`.** It cannot execute on the build
  machine. Guard checks with `buildPlatform.canExecute hostPlatform` (chapter 13)
  or omit them.
* **Forgetting `.exe`.** The file is still produced, but Windows will not run it
  as an executable without the suffix.

## 6. What's next

[Chapter 16](../16-target-android/README.md) swaps in the Android NDK — another
ELF target, but with a different libc (bionic), a different ABI (`arm64-v8a`),
and an unfree toolchain that needs `allowUnfree`.

---

[« Previous: 14 — Target: Linux x86_64](../14-target-linux/README.md) · [Index](../README.md) · [Next: 16 — Target: Android arm64-v8a »](../16-target-android/README.md)
