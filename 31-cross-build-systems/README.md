[« Previous: 30 — Autoconf/Automake](../30-autoconf-host-drivers/README.md) · [Index](../README.md) · [Next: 32 — Rust and Go »](../32-rust-go-cross/README.md)

# 31 — Cross-compiling with build systems

> **Goal.** Cross-compile a real Meson project (our `libadd → libmul → uselib2`
> chain) to **Windows** and **Android**, using a **cross file generated from the
> Nix stdenv** — no hand-written `-I`/`-L`, and no hand-written triple either.
> The chapter also gives the CMake and Autotools equivalents.

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. The problem build systems have when cross-compiling

A native build system guesses "the compiler is `cc`, the machine is *this*
machine". Cross-compiling needs it told otherwise:

| build system | the "tell it otherwise" file |
|---|---|
| Meson | a **cross file** (`--cross-file`) |
| CMake | a **toolchain file** (`-DCMAKE_TOOLCHAIN_FILE`) |
| Autotools | `--host=<triple>` (and `--build=`) |

In every case the content is the same three facts: *which tools*, *which
machine*, *where to look for libraries*. Nix already knows all three.

## 2. Meson: generate the cross file from the stdenv

The tool names carry the target prefix and are on `PATH` (via the cc/binutils
wrappers); the machine is `stdenv.hostPlatform`. So the cross file is generated,
not written:

```nix
mkCrossFile = stdenv: pkgs.writeText "meson-cross.ini" ''
  [binaries]
  c     = '${stdenv.cc.targetPrefix}cc'
  cpp   = '${stdenv.cc.targetPrefix}c++'
  ar    = '${stdenv.cc.targetPrefix}ar'
  strip = '${stdenv.cc.targetPrefix}strip'

  [host_machine]
  system     = '${if stdenv.hostPlatform.isWindows then "windows"
                  else if stdenv.hostPlatform.isAndroid then "android"
                  else "linux"}'
  cpu_family = '${stdenv.hostPlatform.parsed.cpu.name}'
  cpu        = '${stdenv.hostPlatform.parsed.cpu.name}'
  endian     = 'little'
'';
```

and passed to every package for that target:

```nix
mesonFlags = [ "--cross-file=${mkCrossFile target.stdenv}" ];
```

The result, verbatim:

```ini
# windows
c = 'x86_64-w64-mingw32-cc'      # host_machine.system = 'windows'
# android
c = 'aarch64-unknown-linux-android-cc'   # host_machine.system = 'android'
```

## 3. The rest is unchanged

The `meson.build` files are the same as in [chapter 28](../28-meson-host-drivers/README.md)
— `dependency('libadd')`, `dependency('libmul')`, `install : true`. Dependency
management does not change when cross-compiling: `buildInputs = [ libadd ]` and
`propagatedBuildInputs = [ libadd ]` still resolve through the **target's**
pkg-config path, because the build inputs are target packages.

## 4. Run it

```sh
nix build .#windows-uselib2 --max-jobs 1 --cores 1   # PE32+ x86-64
nix build .#android-uselib2 --max-jobs 1 --cores 1   # ELF aarch64 (NDK)
nix build .#crossFiles.windows --max-jobs 1 --cores 1
```

## 5. Verify

```sh
$ file …/windows-uselib2/bin/uselib2.exe
…: PE32+ executable for MS Windows (console), x86-64

$ file …/android-uselib2/bin/uselib2
…: ELF 64-bit LSB pie executable, ARM aarch64, … built by NDK r27
```

There is no `checkPhase`: a Windows or Android binary cannot run on the build
machine (that would be [chapter 1's topic] if we added an emulator).

## 6. The CMake and Autotools equivalents

**CMake toolchain file** (same facts, CMake spelling):

```cmake
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER   x86_64-w64-mingw32-cc)
set(CMAKE_CXX_COMPILER x86_64-w64-mingw32-c++)
set(CMAKE_AR           x86_64-w64-mingw32-ar)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
```

```nix
cmakeFlags = [ "-DCMAKE_TOOLCHAIN_FILE=${mkCMakeToolchain target.stdenv}" ];
```

**Autotools** needs no file at all — the nixpkgs Autoconf hook already passes
`--build`/`--host` for a cross stdenv. If you call `configure` yourself:

```sh
./configure --build=${stdenv.buildPlatform.config} --host=${stdenv.hostPlatform.config}
```

## 7. Pitfalls

* **Hard-coding the triple in the cross file.** Derive it from the stdenv
  (`targetPrefix`, `hostPlatform`), or it will break for the next target.
* **`host_machine.system`.** NixOS reports Android's platform as `aarch64-linux`;
  Meson wants `system = 'android'`. Map it (as above).
* **Running the result.** You cannot execute a Windows/Android binary on the
  build machine — do not add a `checkPhase`.
* **Forgetting `propagatedBuildInputs`.** Same as chapter 28: without it,
  `dependency('libmul')` cannot find `libadd.pc`.
* **pkg-config "cross" complaints.** nixpkgs' pkg-config wrapper already handles
  the cross sysroot; do not set `PKG_CONFIG_ALLOW_CROSS` by hand.

## 8. What's next

[Chapter 32](../32-rust-go-cross/README.md) leaves C behind and cross-compiles
**Rust and Go** for the same targets.

---

[« Previous: 30 — Autoconf/Automake](../30-autoconf-host-drivers/README.md) · [Index](../README.md) · [Next: 32 — Rust and Go »](../32-rust-go-cross/README.md)
