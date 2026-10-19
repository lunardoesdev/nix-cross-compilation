[« Previous: 17 — Target: Emscripten](../17-target-emscripten/README.md) · [Index](../README.md) · [Next: 19 — FHS libraries, the dynamic way »](../19-fhs-libraries-dynamic/README.md)

# 18 — Portable bundles with sharun + uruntime

> **Goal.** Turn the Linux build into a **self-contained bundle that runs on a
> normal distribution with no Nix, no `nix-portable` and no `nixGL`** — carrying
> its own dynamic linker, libc and libraries, while using the host's GPU drivers.

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. The problem

A normal `nix build` produces ELF binaries whose interpreter and shared libraries
live under `/nix/store/…`. On a distro without Nix they do not start. The goal is
a **bundle** that carries everything it needs:

```sh
./uselib2-portable/bin/uselib2     # console demo
./sdl3-game-portable/bin/sdl3-game # SDL3 game
```

## 2. Why `sharun` (and not `quick-sharun`)

[**`sharun`**](https://github.com/pkgforge-dev/Anylinux-sharun) is a single
static launcher. It is the runtime: it finds the real ELF, invokes the bundled
dynamic linker with `--library-path`, and sets up a pile of environment
variables. Upstream documents that it works *"even directly in NixOS without any
wrapper (non-FHS environment)"*.

**`quick-sharun`** is an upstream *shell wrapper* around `sharun` that
auto-detects dependencies with `ldd`+`strace` and downloads tools. It assumes an
**Arch/FHS build host with the app installed in `/usr`** — which fights with a
hermetic Nix build. So this chapter uses **`sharun` as the runtime** and
assembles the AppDir with Nix. `sharun` is fetched as a fixed-output derivation,
pinned by hash.

## 3. The AppDir layout

```
uselib2-portable/
├── AppRun                -> sharun      (hardlink)
├── sharun                               (static launcher)
├── bin/uselib2           -> sharun      (hardlink; argv[0] selects the binary)
├── shared/bin/uselib2                   (the real ELF)
├── lib/                                 (bundled ld-linux + all .so files)
├── uselib2.desktop
└── .env
```

At runtime `sharun` executes

```
$APPDIR/lib/ld-linux-x86-64.so.2 --library-path $APPDIR/lib \
    $APPDIR/shared/bin/uselib2 "$@"
```

and then appends the **host's** library directories (`/usr/lib`, `/lib`, the
`ld.so.cache`, and `/run/opengl-driver/lib`) *after* the bundled ones.

## 4. Assembling it in Nix

`mkPortable` does four things:

1. **Real ELF + launcher.** Copy the app to `shared/bin/`, copy `sharun`, and
   hardlink `AppRun` and `bin/<app>` to it.
2. **Bundle glibc** (`ld-linux`, `libc`, NSS modules, ...).
3. **Bundle the dependency closure.** `ldd` resolves the whole `DT_NEEDED` tree;
   for each directory we copy *all* its `.so*` files (preserving symlinks), so
   versioned names like `libfoo.so.1` survive.
4. **Drop Nix store RPATHs** with `patchelf --remove-rpath`, so nothing can
   silently load from `/nix/store`.

```nix
${pkgs.glibc.bin}/bin/ldd "$app" \
  | grep -o '/nix/store/[^ ]*' \
  | xargs -r -n1 dirname | sort -u \
  | while IFS= read -r dir; do
      for lib in "$dir"/*.so*; do … cp -a "$lib" "$out/lib/…" ; done
    done

for f in "$out"/lib/*.so* "$out/shared/bin/${mainProgram}"; do
  patchelf --remove-rpath "$f" || true
done
```

## 5. GPU drivers: why no `nixGL`

The bundle deliberately **does not** include kernel/GPU-facing libraries
(`libGL`, `libEGL`, `libgbm`, `libvulkan`, `libdrm`, ...). Those must match the
machine that runs the game. `sharun` looks in the bundle first and then falls
back to the host — including `/run/opengl-driver/lib` on NixOS. That fallback is
exactly why **no `nixGL` wrapper is needed**.

Bundling the *rest* of userspace (glibc, SDL3, X11/Wayland, audio, ...) is what
makes the same file work on any glibc distro.

## 6. Optional single-file AppImage (uruntime)

The AppImage is assembled directly (`cat runtime + mksquashfs`) with
[VHSgunzo's `uruntime`](https://github.com/VHSgunzo/uruntime). Unlike the classic
type-2 runtime, it **extracts and runs when FUSE is unavailable**, so no
`--appimage-extract-and-run` is needed. The pack step rewrites its embedded
`URUNTIME_EXTRACT` policy to `2` ("try FUSE, otherwise always extract"):

```sh
sed -i 's/URUNTIME_EXTRACT=[0-9]/URUNTIME_EXTRACT=2/' ./runtime
cat ./runtime app.squashfs > "$out/${name}-x86_64.AppImage"
```

## 7. Run it

```sh
nix build .#uselib2-portable          --max-jobs 1 --cores 1
./result/bin/uselib2

nix build .#sdl3-game-portable        --max-jobs 1 --cores 1
./result/bin/sdl3-game --frames 120

nix build .#uselib2-portable-tar      --max-jobs 1 --cores 1
nix build .#sdl3-game-portable-appimage --max-jobs 1 --cores 1
```

## 8. Verify — the important tests

**It does not need Nix.** Copy the bundle somewhere and clear the environment:

```sh
$ cp -r result /tmp/ul2p && chmod -R u+w /tmp/ul2p
$ env -i /tmp/ul2p/bin/uselib2
uselib2: add(6, 7) = 13
uselib2: mul(6, 7) = 42
```

**The game runs off the host's drivers.** With an empty environment (no
`/nix/store` on the library path):

```sh
$ env -i SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy /tmp/gp/bin/sdl3-game --frames 3
sdl3-game: video driver = offscreen
sdl3-game: score = mul(3, 14) = 42
sdl3-game: rendered 3 frame(s)
```

**The AppImage works without FUSE.** `uruntime` falls back to extraction:

```sh
$ env -i /tmp/uselib2-x86_64.AppImage
SUID fusermount not found in PATH, trying to unshare...
uselib2: add(6, 7) = 13
uselib2: mul(6, 7) = 42
```

The CLI bundle carries ~42 libraries; the SDL3 game ~296.

## 9. Pitfalls

* **Missing the dynamic linker.** The bundle must contain
  `lib/ld-linux-x86-64.so.2`; the build asserts it.
* **Leaving store RPATHs.** Always `patchelf --remove-rpath` the bundled ELFs;
  the `env -i` test is what proves it.
* **Bundling GPU drivers.** They must come from the host; bundling them
  re-introduces the `nixGL` problem.
* **Stripping the tree.** `dontFixup = true` is set so Nix does not re-patch the
  assembled AppDir.
* **Old kernel.** The bundled glibc needs a reasonably modern kernel on the
  target; this is inherent to shipping your own libc.
* **Expecting `quick-sharun`.** It wants Arch + `/usr`; use `sharun` + Nix, as
  here.

## 10. What's next

This bundled a whole *program* with its dependencies. [Chapter 19](../19-fhs-libraries-dynamic/README.md)
does the other half: packaging the two **libraries** themselves for FHS distros,
dynamically — with `SONAME` and a relocatable `$ORIGIN` RUNPATH.

---

[« Previous: 17 — Target: Emscripten](../17-target-emscripten/README.md) · [Index](../README.md) · [Next: 19 — FHS libraries, the dynamic way »](../19-fhs-libraries-dynamic/README.md)
