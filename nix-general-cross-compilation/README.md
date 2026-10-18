> **Superseded by the guide.** This directory is the original draft. Its content
> has been refactored into the interlinked chapters under [`guide/`](../guide/):
> the target table and generic builders are
> [chapters 11–13](../guide/11-one-recipe-many-targets/README.md), the four
> headline targets are [chapters 14–17](../guide/14-target-linux/README.md), and
> the portable (FHS) bundles and library packages are
> [chapters 18–20](../guide/18-fhs-portable-sharun-uruntime/README.md). Start at
> the [guide index](../guide/README.md).

# Nix general cross-compilation + portable (FHS) Linux bundles

A small, heavily commented demonstration of **cross-compiling real C code with
Nix**, plus a **portable Linux bundle** built with
[sharun](https://github.com/pkgforge-dev/Anylinux-sharun) that runs on a normal
distro **without Nix, `nix-portable` or `nixGL`**.

## What gets built

Two tiny C libraries, a console program and an SDL3 game:

| package   | what it is                                                        |
|-----------|-------------------------------------------------------------------|
| `libadd`  | `int add(int, int)`                                               |
| `libmul`  | `int mul(int, int)` — implemented with `add()` from `libadd`      |
| `uselib2` | console program that calls `add()` and `mul()` and prints `42`    |
| `sdl3-game` | SDL3 window + render loop; its "score" comes from `mul()`       |

The exact same sources are compiled for:

| target | stdenv / cross system | toolchain |
|---|---|---|
| Linux x86_64 | `pkgs.stdenv` | gcc |
| Windows x86_64 | `pkgs.pkgsCross.mingwW64` | mingw-w64 |
| Android arm64-v8a | `pkgs.pkgsCross.aarch64-android` | NDK clang |
| Emscripten (wasm) | `pkgs.emscripten` + `emcc` | emcc |
| **FHS Linux** | the Linux build + sharun | (bundled, no toolchain needed) |

## Requirements

* Nix with flakes (`experimental-features = nix-command flakes`).
* No other dependencies: every dependency is resolved by Nix. The flake sets
  `config.allowUnfree = true` because the Android NDK (and therefore the
  `aarch64-android-prebuilt` target) is unfree.

> **Project rule:** everything here is built with **one core and one job**.
> `scripts/build.sh` always passes `--max-jobs 1 --cores 1`, and every
> derivation sets `enableParallelBuilding = false`.

```sh
./scripts/build.sh .#linux-sdl3-game     # build one output
./scripts/build.sh all                   # build everything
```

## The portable (FHS) Linux bundle

This is the interesting part. A normal `nix build` produces binaries that only
run where `/nix/store` exists. The portable outputs instead ship a
self-contained **AppDir** that carries its own dynamic linker, libc and every
runtime library, launched by the static `sharun` binary:

```
uselib2-portable/
├── AppRun                -> sharun      (hardlink)
├── sharun                               (static launcher)
├── bin/uselib2           -> sharun      (hardlink; argv[0] picks the binary)
├── shared/bin/uselib2                   (the real ELF)
├── lib/                                 (ld-linux + all .so files)
├── uselib2.desktop
└── .env
```

At runtime sharun executes

```
$APPDIR/lib/ld-linux-x86-64.so.2 --library-path $APPDIR/lib $APPDIR/shared/bin/uselib2 "$@"
```

and then appends the host's library directories (`/usr/lib`, `/lib`, the
`ld.so.cache`, and `/run/opengl-driver/lib`) *after* the bundled ones.

### Outputs

| output | what |
|---|---|
| `linux-portable-uselib2` | AppDir directory tree |
| `linux-portable-sdl3-game` | AppDir directory tree |
| `linux-portable-uselib2-tar` | `uselib2-portable-x86_64.tar.zst` |
| `linux-portable-sdl3-game-tar` | `sdl3-game-portable-x86_64.tar.zst` |
| `linux-portable-uselib2-appimage` | single-file `.AppImage` |
| `linux-portable-sdl3-game-appimage` | single-file `.AppImage` |
| `linux-libs` | FHS layout: headers + static + shared libs + pkg-config |
| `linux-libs-tar` | `cdemo-libs-x86_64.tar.zst` |

```sh
./scripts/build.sh .#linux-portable-sdl3-game
./result/bin/sdl3-game --frames 120      # run it straight from the store

# prove it does not need Nix: copy it somewhere and clear the environment
cp -r result /tmp/sdl3-game-portable
env -i /tmp/sdl3-game-portable/bin/sdl3-game --frames 5
```

The tarball is just the same directory, archived:

```sh
./scripts/build.sh .#linux-portable-sdl3-game-tar
tar --zstd -xf result/sdl3-game-portable-x86_64.tar.zst
./sdl3-game-portable/bin/sdl3-game
```

The AppImages use VHSgunzo's [uruntime](https://github.com/VHSgunzo/uruntime),
which mounts the image through FUSE when it can and **automatically extracts and
runs when FUSE is not available**, so no `--appimage-extract-and-run` is needed:

```sh
./sdl3-game-x86_64.AppImage
```

The pack step rewrites the embedded `URUNTIME_EXTRACT` policy to `2` ("try
FUSE, otherwise always extract") so the fallback is not limited by image size.

### Library-only bundle (static + dynamic), for FHS distributions

Besides the whole-program bundles, the two demo libraries are also packaged on
their own in a normal distro layout, with **both** static and shared objects:

```sh
./scripts/build.sh .#linux-libs          # directory
./scripts/build.sh .#linux-libs-tar
tar --zstd -xf result/cdemo-libs-x86_64.tar.zst
```

```
cdemo-libs-x86_64/
├── include/
│   ├── add.h
│   └── mul.h
└── lib/
    ├── libadd.a                 # static
    ├── libadd.so -> libadd.so.1.0.0
    ├── libadd.so.1 -> libadd.so.1.0.0
    ├── libadd.so.1.0.0          # shared, SONAME libadd.so.1
    ├── libmul.a
    ├── libmul.so -> libmul.so.1.0.0
    ├── libmul.so.1 -> libmul.so.1.0.0
    ├── libmul.so.1.0.0          # shared, SONAME libmul.so.1
    └── pkgconfig/
        ├── libadd.pc
        └── libmul.pc
```

The shared objects are real versioned libraries (`DT_SONAME = lib*.so.1`) and
their `RUNPATH` is `$ORIGIN` — there is no `/nix/store` reference anywhere, so
the tree can be moved anywhere:

```sh
# use it in place, or install it into a prefix
sudo cp -a cdemo-libs-x86_64/include/* /usr/local/include/
sudo cp -a cdemo-libs-x86_64/lib/*     /usr/local/lib/

# dynamic link
cc app.c -Iinclude -Llib -lmul -ladd -o app && LD_LIBRARY_PATH=$PWD/lib ./app
# static link
cc app.c -Iinclude -Llib -Wl,-Bstatic -lmul -ladd -Wl,-Bdynamic -o app && ./app
# pkg-config
PKG_CONFIG_PATH=lib/pkgconfig cc app.c $(pkg-config --cflags --libs libmul) -o app
```

The bundle build runs all three of those checks itself (`doInstallCheck`), so a
broken layout fails the build.

### Why no `nixGL`?

The bundle deliberately **does not** include GPU/kernel-facing libraries
(`libGL`, `libEGL`, `libgbm`, `libvulkan`, `libdrm`, ...). sharun looks in the
bundle first and then in the host paths, so the game uses the machine's own
Mesa/NVIDIA drivers — including on NixOS, where the drivers live in
`/run/opengl-driver/lib`. That is the whole reason no `nixGL` wrapper is needed.

Bundling the *rest* of userspace (glibc, SDL3, X11/Wayland, audio, ...) is what
makes the same file work on any glibc distro.

## Repository layout

```
flake.nix                 # inputs + flake outputs
lib/targets.nix           # the platform table: one nixpkgs set per target
lib/packages.nix          # instantiates the four packages for every target
lib/c-lib.nix             # generic builder for the two C libraries
lib/c-app.nix             # generic builder for the console program
lib/sharun.nix            # AppDir / tar.zst / AppImage assembly (sharun)
lib/fhs-libs.nix          # static+shared library tree for FHS distros
lib/sdl3-emscripten.nix   # SDL3 built for wasm (nixpkgs has no such package)
lib/sdl3-android.nix      # SDL3 built for Android with the NDK toolchain
pkgs/{libadd,libmul,uselib2,sdl3-game}/
scripts/build.sh          # enforces single-core / single-job
```

## How the cross-compilation is set up

`lib/targets.nix` maps each target to a complete nixpkgs package set whose
`stdenv` targets that platform. Packages are then written exactly like normal
nixpkgs packages and instantiated through the target set, so **Nix resolves all
dependencies** — compiler, libc, SDL3, pkg-config, everything:

```nix
libadd  = linux.callPackage ../lib/c-lib.nix { ... };
libmul  = linux.callPackage ../lib/c-lib.nix { deps = [ libadd ]; ... };
uselib2 = linux.callPackage ../pkgs/uselib2  { inherit libadd libmul; };
game    = linux.callPackage ../pkgs/sdl3-game { sdl3 = linux.sdl3; ... };
```

`lib/targets.nix` also explains why Emscripten uses `emcc` directly instead of
`emscriptenStdenv` (the latter forces `emconfigure`, which the CMake/direct
compiler builds here do not use).

## Running the cross-built artifacts

* **Windows** (`.exe`): `result/bin/sdl3-game.exe`. Nix also links the required
  `SDL3.dll`, `libmul.dll` and `libadd.dll` next to it, so the `bin` directory
  is self-contained.
* **Android** (arm64-v8a): the outputs are native `arm64` ELF shared objects and
  executables (built against the NDK's bionic libc), not an APK. The binaries
  need their sibling libraries, so push the whole directory (`libadd.so`,
  `libmul.so`, and for the game `libSDL3.so`) next to them, or drop those `.so`
  files into an APK's `jniLibs/arm64-v8a/`. Packaging an APK is out of scope for
  this demo.
* **Emscripten**: `result/bin/sdl3-game.html` (+ `.js` and `.wasm`). Serve the
  directory over HTTP and open the `.html` in a browser, e.g.
  `python3 -m http.server -d result/bin`.

## Adding another target

Add one line to the table in `lib/targets.nix` (for example
`pkgsCross.musl64`), then instantiate the packages for it in
`lib/packages.nix`. The four recipes themselves do not change.

## Notes and limitations

* The Android `x86`/`x86_64` ABIs are not included; nixpkgs only ships
  `aarch64-android`, `aarch64-android-prebuilt` and `armv7a-android-prebuilt`
  (the other two need hand-written `crossSystem` records).
* `lib/sdl3-emscripten.nix` and `lib/sdl3-android.nix` exist because nixpkgs'
  `sdl3` package is only wired for native Unix/Windows (and the Android
  `-prebuilt` sysroot is too small for SDL3's Android backends, so that one is
  built with the NDK's own CMake toolchain).
* The bundled glibc comes from nixpkgs and therefore needs a reasonably modern
  kernel on the target machine; this is inherent to bundling your own libc.
