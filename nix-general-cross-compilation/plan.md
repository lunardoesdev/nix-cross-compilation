# Nix general cross-compilation demo + portable (FHS) Linux bundles

## 0. Original brief (kept verbatim)

1. make a simple c library with function like int add
2. make second c library that uses first library and defines lets say int multiply using int add from previous library
3. make a c binary program that uses second library to print something to console.
4. make a simple SDL3 c game.
5. write nix code describing how to build all of above for linux, windows, android (all 4 archs), emscripten.
6. define stdenvs and everything else needed for proper cross-compilation
7. dependencies must be passed same way as in any other nix package, nix must manage the dependencies.
8. I want the nix code to be simple, detailed and documented
9. ALWAYS USE SINGLE CORE AND SINGLE JOB FOR NIX! PASS NEEDED ARGUMENTS FOR THAT.

### Addition (this round)

10. Also build for **FHS Linux** using **quick-sharun / sharun** technology, so the produced
    binaries launch on a **non-Nix** system **without `nix-portable` and without `nixGL`**.

---

## 1. What "portable / FHS Linux" means here

A normal `nix build` produces ELF binaries whose interpreter and shared libraries live in
`/nix/store/...`. On a distro without Nix they do not start. The goal is a **self-contained
bundle** that carries its own dynamic linker, libc and libraries, so it runs on any glibc
(and ideally musl) distro directly:

```sh
./uselib2-portable/bin/uselib2     # CLI demo
./sdl3-game-portable/bin/sdl3-game # SDL3 game
```

For the SDL3 game the bundle must also work without `nixGL`, i.e. it relies on the host's
GPU drivers at runtime (via `sharun`'s host fallback paths) rather than shipping a driver
stack.

---

## 2. Why `sharun` (and where `quick-sharun` fits)

Both come from the [Anylinux-AppImages](https://github.com/pkgforge-dev/Anylinux-AppImages)
project.

* **`sharun`** is a single static launcher binary (Rust, per-arch releases from
  [Anylinux-sharun](https://github.com/pkgforge-dev/Anylinux-sharun)). It is the runtime:
  it finds the real ELF, invokes the bundled dynamic linker with `--library-path`,
  preserves `/proc/self/exe`, and sets up a big pile of env vars. It is explicitly
  documented to work **"even directly in NixOS without any wrapper (non FHS environment)"**.
  AppDir layout it expects/creates:

  ```
  AppDir/
    sharun                     # the launcher
    AppRun      -> sharun      # hardlink
    bin/<app>   -> sharun      # hardlink; arg0 basename selects the real binary
    shared/bin/<app>           # the real ELF
    lib/                       # 64-bit libs + bundled ld-linux
    lib32/                     # 32-bit libs (unused here)
    .env                       # KEY=VALUE env exported to the app
  ```

  At runtime `sharun` searches its bundled `lib/` first and then falls back to the host
  (`/usr/lib`, `/lib`, ld.so.cache, and notably `/run/opengl-driver/lib` for NixOS).
  That fallback is exactly why **nixGL is not needed**.

* **`quick-sharun`** is an upstream *shell wrapper* around `sharun` that auto-detects
  dependencies with `ldd`+`strace`, downloads `sharun`/`appimagetool`, and can build an
  AppImage. Upstream deliberately embeds these instructions in the script:

  > * MUST INSTALL THE APPLICATION TO /usr BEFORE DEPLOYING!
  > * DEPLOYING ON ANY SYSTEM OTHER THAN ARCHLINUX IS A VERY BAD IDEA
  > * DO NOT EVER COPY LIBRARIES/BINARIES MANUALLY, INSTEAD PASS THEM TO quick-sharun

  So `quick-sharun` assumes an **Arch/FHS build host with the app in `/usr`**. That fights
  with a hermetic Nix build (sandbox, no network, everything in `/nix/store`) and with
  requirement 7 ("nix must manage the dependencies").

**Decision (proposed):** use **`sharun` as the runtime** and **assemble the AppDir with Nix**
(`sharun` is fetched as a fixed-output derivation, pinned by hash). Keep `quick-sharun`
as an *optional* alternative track (run inside a container/FHS env) documented in the
README, not as the default. This keeps the build hermetic, reproducible and
single-source-of-truth for dependencies.

---

## 3. Build matrix (confirmed)

| # | output | cross system / stdenv | toolchain | runs where |
|---|---|---|---|---|
| 1 | linux-x86_64 | `pkgs.stdenv` | gcc | normal Nix build, `./result/bin/...` |
| 2 | linux-x86_64-portable | from #1 | — | **FHS/sharun bundle**, any distro (no nix/nixGL) |
| 3 | windows-x86_64 | `pkgsCross.mingwW64.stdenv` | mingw-w64 gcc | Windows, `x86_64-w64-mingw32-*` |
| 4 | android-arm64-v8a | `pkgsCross.aarch64-android-prebuilt.stdenv` | NDK clang | Android arm64-v8a |
| 5 | emscripten | `pkgs.emscriptenStdenv` | `emcc` | browser (`index.html` + `.wasm` + `.js`) |

The loader across all of these is the same four C packages (§5.3). Only libs #1 and #2
are needed for #1/#2; #3–#5 reuse the identical sources.

Adding more targets later (musl, aarch64-linux, i686-windows, the other three Android
ABIs) is a one-line addition to the target table in `lib/targets.nix` — the packages don't
change. The Android `x86`/`x86_64` ABIs would need hand-rolled `crossSystem` records
(`config = "x86_64-unknown-linux-android"`, `androidNdkVersion = "27"`), which is why they
are deliberately out of scope now.

---

## 4. Repository layout

```
.
├── flake.nix                 # inputs + outputs (packages, devShells, apps)
├── flake.lock
├── README.md                 # how to build each target (written last)
├── lib/
│   ├── targets.nix           # target table (§3) -> one pkgs set per target
│   ├── packages.nix          # builds all pkgs for one pkgs set
│   ├── c-lib.nix             # generic builder for the two C libraries (§5.3)
│   ├── c-app.nix             # generic builder for CLI / SDL3 game
│   └── sharun.nix            # AppDir assembler + sharun FOD (§6)
├── pkgs/
│   ├── libadd/               # add.c + add.h + Makefile
│   ├── libmul/               # mul.c + mul.h + Makefile  (depends on libadd)
│   ├── uselib2/              # main.c                (depends on libmul)
│   └── sdl3-game/            # main.c + assets/      (depends on sdl3)
└── scripts/
    └── build.sh              # wrapper that always passes single-core/ single-job flags
```

The four source packages are plain, build-system-agnostic C with a tiny hand-written
`Makefile` (or direct `$CC` invocations) so the **same source** builds under gcc,
mingw, NDK clang and emcc. No CMake/Meson noise.

---

## 5. Nix design

### 5.1 Flake shape

```nix
outputs = { self, nixpkgs, ... } @ inputs:
  let
    # every supported *host* we can evaluate from (only x86_64-linux for now)
    systems = [ "x86_64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (s: f (import nixpkgs { system = s; }));
  in {
    packages = forAllSystems (pkgs: import ./lib/packages.nix { inherit pkgs; });
  };
```

### 5.2 Per-target package sets

`lib/targets.nix` maps each matrix row to a *pkgs set* obtained either from
`pkgs.pkgsCross.*` or from `import nixpkgs { inherit system; crossSystem = ...; }`.
`lib/packages.nix` then references every package through its **target** pkgs set:

```nix
libadd = targetPkgs.callPackage ./pkgs/libadd { };
libmul = targetPkgs.callPackage ./pkgs/libmul { libadd = libadd; };
uselib2 = targetPkgs.callPackage ./pkgs/uselib2 { libmul = libmul; };
sdl3-game = targetPkgs.callPackage ./pkgs/sdl3-game { sdl3 = targetPkgs.sdl3; };
```

This is requirement 7: dependencies are ordinary Nix arguments resolved in the target
platform's package set — exactly like any nixpkgs package. No manual `-I`/`-L` paths,
no vendored blobs (except the pinned `sharun` download in §6).

### 5.3 The C libraries and apps

* `libadd` → `lib/libadd.a` + `include/add.h` + pkg-config file.
* `libmul` → `lib/libmul.a` + `include/mul.h`; `buildInputs = [ libadd ]`, uses `add()`.
* `uselib2` → console binary; `buildInputs = [ libmul libadd ]` (static-ish, prints `mul(a,b)`).
* `sdl3-game` → SDL3 window + render loop; `buildInputs = [ sdl3 ]`.

For Linux/Windows we link the small libs **statically** into the executables (simple and
portable). Android/emscripten: SDL3 game only (the two libs are still built and linked in).

### 5.4 Android arm64-v8a

`pkgsCross.aarch64-android-prebuilt.stdenv` (NDK clang, prebuilt bionic). SDL3 is not
packaged for Android in nixpkgs, so the SDL3 game uses a local `sdl3-android`
instantiation built from the SDL3 source with the NDK toolchain. The two small C
libs and `uselib2` build there unchanged.

### 5.5 Emscripten

`pkgs.emscriptenStdenv.mkDerivation`; SDL3 is not packaged for emscripten, so a local
`sdl3-emscripten` derivation is built from the SDL3 source with `-DSDL_EMSCRIPTEN=ON`.
The game emits `index.html`/`.wasm`/`.js` + `--preload-file` assets; the shell page is
generated with `-sUSE_SDL=0` (we link our own SDL3) and `-sALLOW_MEMORY_GROWTH=1`.

---

## 6. Portable FHS Linux bundles (`sharun`) — the new part

### 6.1 Artifacts

| name | what | how to run |
|---|---|---|
| `result-portable-cli` | AppDir dir tree | `./bin/uselib2` |
| `result-portable-game` | AppDir dir tree | `./bin/sdl3-game` |
| `result-portable-tar` | `*.tar.zst` of an AppDir | `tar xf` then `./bin/...` |
| `result-portable-appimage` (optional) | single `.AppImage` | `./Foo.AppImage` |

Primary artifact = the plain directory (and its `.tar.zst`). It needs no FUSE, no
AppImage runtime, nothing from the host beyond a Linux kernel. AppImage is an optional
extra built from the same AppDir with a pinned `appimagetool` FOD.

### 6.2 How the AppDir is assembled in Nix

`lib/sharun.nix` exposes `mkPortable { pkgs, sharun, app, mainProgram, extraLibs ? [] }`:

```nix
closure = pkgs.closureInfo { rootPaths = [ app ] ++ extraLibs; };   # store-paths file
```

installPhase (sketch):

```
mkdir -p $out/{bin,shared/bin,lib}
cp ${app}/bin/${mainProgram} $out/shared/bin/${mainProgram}     # real ELF
cp ${sharun}/sharun          $out/sharun
ln -s ../sharun              $out/AppRun
ln -s ../sharun              $out/bin/${mainProgram}
cp ${targetGlibc}/lib/ld-linux-x86-64.so.2 $out/lib/            # bundled interpreter
# copy every .so from the closure (preserving the relative lib subpaths we need)
while read p; do find "$p" -path '*/lib/*.so*' -exec cp -a {} $out/lib/ \; ; done < ${closure}/store-paths
echo 'KEY=VALUE' > $out/.env
```

Notes:
* `closureInfo` is the idiomatic, sandbox-safe way to get the dependency closure
  (no `nix-store` calls inside the build). This *is* "nix manages the dependencies".
* `sharun` resolves the real binary as `shared/bin/<arg0-name>` and runs it with the
  bundled `lib/ld-linux...` and `--library-path $out/lib`, so bundled libs win over any
  leftover `/nix/store` `DT_RUNPATH`. A `patchelf --set-rpath '$ORIGIN'` pass is added if
  we find store paths leaking into strings.
* dlopen'd libraries (SDL3's `libSDL3.so` video/audio backends, `libEGL`, `libGL`,
  `libvulkan`, wayland/x11 client libs) are *not* visible to `ldd`. We bundle them by
  listing them explicitly in `extraLibs` — they are already declared as `buildInputs`, in
  the spirit of requirement 7.

### 6.3 GPU / `nixGL`-free strategy

**Host drivers only (locked decision).** The bundle ships *no* GPU drivers.
`sharun` appends `/usr/lib`, `/lib`, ld.so.cache and `/run/opengl-driver/lib` to the
library search path after its own `lib/`, so the distro's real Mesa/NVIDIA drivers are
used. Consequences:

* Works on Fedora/Ubuntu/Arch/Debian out of the box, and even on NixOS (via
  `/run/opengl-driver/lib`) — **without `nixGL`**.
* A machine with no GPU driver at all will not render (no bundled llvmpipe). That is the
  accepted trade-off for a small bundle; a future `gpu = "bundled"` mode could add Mesa.

The CLI demo (`uselib2`) obviously does not care about this at all.

### 6.4 Optional: `quick-sharun` track

Documented as `nix run .#quick-sharun-container` — runs upstream `quick-sharun` inside a
`dockerTools` Arch image (the only configuration upstream supports), fed with a Nix-built
FHS prefix. Not the default; kept because the user explicitly named it.

---

## 7. Single core / single job (requirement 9)

* `scripts/build.sh` always invokes: `nix build --max-jobs 1 --cores 1 ...`.
* `flake.nix` does not re-enable parallelism; every derivation inherits `NIX_BUILD_CORES`.
* README documents `--option cores 1 --option max-jobs 1` and the per-derivation
  `enableParallelBuilding = false;` used in the C packages.
* A `Makefile` target `make build-<target>` wraps the flags so nobody forgets them.

---

## 8. Testing

* Linux native: `checkPhase` runs the CLI and asserts the printed value; the game is run
  under `xvfb-run` with SDL's `dummy` video driver (`SDL_VIDEODRIVER=dummy`).
* Portable bundle: a `--simple-test`-style check that launches `./bin/uselib2` inside a
  minimal non-Nix `busybox`/`ubuntu` chroot if we add one later (stretch goal).
* Cross targets: at minimum `file`/`objdump` sanity checks on the produced ELF/PE/APK/wasm.

---

## 9. Milestones

1. **M1** – repo skeleton + flake + native Linux build of libadd/libmul/uselib2 (tests pass).
2. **M2** – SDL3 game on native Linux (Xvfb + `SDL_VIDEODRIVER=dummy` check).
3. **M3** – Windows x86_64 cross build (libs + CLI + game).
4. **M4** – Android arm64-v8a (libs + CLI + game, local `sdl3-android`).
5. **M5** – Emscripten build of the SDL3 game (local `sdl3-emscripten`).
6. **M6** – `sharun` portable bundles for CLI + game (dir + `tar.zst`), host-GPU mode.
7. **M7** – optional AppImage from the same AppDir.
8. **M8** – README + `scripts/build.sh` (single-core/single-job) + optional CI.

---

## 10. Risks and decisions

Decisions (locked)
* Portable bundling is **Nix-native `sharun` AppDir** (no quick-sharun dependency).
* Artifacts: **directory + `tar.zst`**; AppImage is optional (M7).
* GPU drivers: **host only** by default (`sharun` fallback path → no `nixGL`).
* Targets: linux x86_64 (native **and** portable), windows x86_64, android arm64-v8a,
  emscripten. (Original "4 Android ABIs" and linux musl/aarch64 dropped per user choice;
  the target table keeps them a one-line add later.)

Risks
* `pkgs.sdl3` does not declare Android/emscripten platforms; both need local SDL3
  derivations (§5.4, §5.5). This is the largest piece of work.
* Bundling Nix's glibc + libs can leave `/nix/store` references in data/strings; a
  RPATH/string audit pass is included (`patchelf`, plus a grep check in `checkPhase`).
* `quick-sharun` upstream insists on Arch + `/usr`, so the default stays Nix-native.

## 11. Open decisions

None blocking. Defaults taken from the review above:
1. Bundle form: directory + `tar.zst` first, AppImage optional. ✅
2. Driver policy: host-only. ✅
3. Which apps get a portable bundle: CLI **and** game, as two separate outputs. ✅
4. Android: arm64-v8a only. ✅
5. Windows: x86_64 only. ✅

---

## 12. Implementation status

Built and verified on this machine (x86_64-linux):

* `linux-libadd`, `linux-libmul`, `linux-uselib2` — native, `checkPhase` asserts
  `mul(6, 7) = 42`.
* `linux-sdl3-game` — native, `checkPhase` renders 5 frames with
  `SDL_VIDEODRIVER=offscreen`.
* `windows-uselib2`, `windows-sdl3-game` — mingw-w64; Nix links `SDL3.dll`,
  `libmul.dll`, `libadd.dll` next to the `.exe`.
* `android-uselib2`, `android-sdl3-game` — arm64-v8a, NDK clang (see §13).
* `emscripten-libadd`, `emscripten-libmul`, `emscripten-sdl3-game` — wasm
  (see §13).
* `linux-portable-uselib2`, `linux-portable-sdl3-game` — sharun AppDirs.
* `linux-portable-*-tar` — `tar.zst` archives.
* `linux-portable-*-appimage` — single-file AppImages (uruntime, FUSE-less).
* `linux-libs`, `linux-libs-tar` — library-only bundle for FHS distros:
  versioned shared objects (`SONAME lib*.so.1`, `RUNPATH $ORIGIN`), static
  archives, headers and relocatable `pkg-config` files.  The build checks a
  dynamic link, a static link and a `pkg-config` build.

FHS verification performed:

```sh
cp -r result /tmp/x && chmod -R u+w /tmp/x
env -i /tmp/x/bin/uselib2                 # prints 42 with an empty environment
env -i /tmp/x/bin/sdl3-game --frames 3    # offscreen, uses host GPU driver libs
./x.AppImage                              # uruntime: FUSE or automatic extraction
```

The bundle contains 38 (CLI) / 77 (game) libraries, the bundled
`ld-linux-x86-64.so.2`, a `.desktop` file (so `AppRun` works) and an empty
`.env`. Nix store RPATHs are removed from every bundled ELF so nothing can
silently load from `/nix/store`.

## 13. Deviations from the original plan

* Emscripten does not use `emscriptenStdenv`: that stdenv forces `emconfigure`,
  while SDL3 and our packages are CMake / direct-compiler builds. We use the
  normal stdenv and pass `${emscripten}/bin/emcc` explicitly.
* Android SDL3 is built with the NDK's own CMake toolchain
  (`lib/sdl3-android.nix`), because `aarch64-android-prebuilt` ships a reduced
  bionic sysroot that lacks `libandroid`/`libOpenSLES`/`jni.h`. The target also
  uses `aarch64-android-prebuilt` rather than `aarch64-android`: the from-source
  variant currently fails while building compiler-rt (`pthread.h not found`),
  and the prebuilt NDK is unfree, hence `config.allowUnfree = true`.
* The AppImage is assembled directly (`cat runtime + mksquashfs`) instead of via
  `appimagetool`. The runtime is VHSgunzo's `uruntime`
  (`uruntime-appimage-squashfs-lite`), whose embedded `URUNTIME_EXTRACT` policy
  is rewritten to `2` so the image tries FUSE and otherwise always extracts and
  runs — i.e. it works on machines without FUSE.
