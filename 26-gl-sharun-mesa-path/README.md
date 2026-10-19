[« Previous: 25 — Optional drivers](../25-gl-optional-drivers/README.md) · [Index](../README.md) · [Next: Appendix A — Troubleshooting & FAQ »](../appendix-a-troubleshooting/README.md)

# 26 — `SHARUN_MESA_PATH`: a swappable Mesa

> **Goal.** Keep Mesa out of the bundle's own `lib/`, put it in a **separate
> directory**, and let `sharun` wire it up via **`SHARUN_MESA_PATH`** — so the
> same app can switch Mesa versions at runtime without being rebuilt.

The complete flake is in [`flake.nix`](flake.nix); the source in [`src/`](src).

---

## 1. What `SHARUN_MESA_PATH` is

The Anylinux `sharun` fork adds `SHARUN_MESA_PATH`:

> *"External mesa install dir (with `lib/` and `share/`) to source graphics env
> vars and libraries from."*

When set, `sharun` treats it as a Mesa prefix and derives everything from it:

| path inside the prefix | becomes |
|---|---|
| `<path>/lib/dri/` | `LIBGL_DRIVERS_PATH`, `LIBVA_DRIVERS_PATH` |
| `<path>/lib/gbm/` | `GBM_BACKENDS_PATH` |
| `<path>/share/glvnd/egl_vendor.d/` | `__EGL_VENDOR_LIBRARY_DIRS` |
| `<path>/share/vulkan/icd.d/` | `VK_DRIVER_FILES` |
| `<path>/share/drirc.d/` | `DRIRC_CONFIGDIR` |

and it **prepends `<path>/lib` to the library search path**, so glvnd finds the
vendor libraries. You do not set any of those variables yourself.

## 2. The layout

```
sdl3-triangle-portable-mesa-path/
├── bin/sdl3-triangle        -> sharun   (hardlink)
├── AppRun                   -> sharun   (hardlink)
├── AppRun.sh                            (points sharun at mesa/)
├── lib/                                 (glibc, glvnd, SDL3, X11, …)
└── mesa/
    ├── lib/                             (libgallium, libGLX_mesa, dri/…)
    └── share/glvnd/egl_vendor.d/50_mesa.json
```

The Mesa part is a normal Mesa prefix, exactly what `SHARUN_MESA_PATH` expects.

## 3. Setting it — and the `.env` trap

`sharun` reads `.env`, but its values are **literal**: it does **not** expand
`$APPDIR`. So this does *not* work:

```
# WRONG — sharun does not expand $APPDIR in .env
SHARUN_MESA_PATH=$APPDIR/mesa
```

Instead, the bundle ships a tiny **`AppRun.sh`**, which `sharun` runs (with
`APPDIR` already set) before starting the app:

```sh
#!/bin/sh
export SHARUN_MESA_PATH="$APPDIR/mesa"
exec "$APPDIR/bin/sdl3-triangle" "$@"
```

`.env` then only carries the literal flags:

```
LIBGL_ALWAYS_SOFTWARE=1
GALLIUM_DRIVER=llvmpipe
__GLX_VENDOR_LIBRARY_NAME=mesa
```

## 4. Run it

```sh
nix build .#portable          --max-jobs 1 --cores 1
nix build .#portable-tar      --max-jobs 1 --cores 1
nix build .#portable-appimage --max-jobs 1 --cores 1

./result/AppRun --seconds 3     # AppRun.sh sets SHARUN_MESA_PATH
```

## 5. Verify

The build asserts the wiring and renders through the bundled loader:

```sh
test -x AppRun.sh && grep -q SHARUN_MESA_PATH AppRun.sh
```

On a real machine (where `sharun`'s `userland-execve` works normally — see the
note in section 6), running via `AppRun` renders with the **bundled** Mesa:

```sh
$ env -i DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" SDL_VIDEODRIVER=x11 \
    ./result/AppRun --seconds 1
OpenGL 4.6 (Compatibility Profile) Mesa 26.2.5 | llvmpipe (LLVM 21.1.8, 256 bits)
rendered 116 frame(s) in ~1 second(s)
```

And because the Mesa location is just an environment variable, you can point it
at **any** Mesa prefix at runtime — a system Mesa, a newer one, or a separate
Mesa bundle:

```sh
SHARUN_MESA_PATH=/opt/mesa-25.0 ./result/bin/sdl3-triangle --seconds 3
```

That is the whole point: **swap the driver without touching the app**.

## 6. Pitfalls

* **`$APPDIR` in `.env`.** It is not expanded. Use `AppRun.sh` (as here) or an
  absolute path.
* **Pointing `SHARUN_MESA_PATH` at `/usr`.** Upstream warns explicitly: it must
  be a directory containing *only* a Mesa install (`lib/` + `share/`), not a
  general prefix, or unrelated libraries leak onto the search path.
* **Forgetting `bin/<app>` is a hardlink.** `AppRun.sh` must exec
  `"$APPDIR/bin/<app>"` (or `"$APPDIR/sharun" <app>`), not the real ELF, so
  `sharun` keeps handling `/proc/self/exe` and the library path.
* **The build-sandbox caveat.** This `sharun` build's `userland-execve` does not
  initialise glvnd inside the Nix build sandbox, so the in-build check renders
  through the bundled loader instead of `AppRun`. On a normal host `AppRun`
  works (verified). This is a sandbox/sharun interaction, not a bundle defect.
* **Forcing software hides the GPU.** As in chapter 24, `LIBGL_ALWAYS_SOFTWARE=1`
  means NVIDIA/AMD are unused; drop it for hardware.

## 7. End of the guide

You now have all three ways to give a portable GL app a driver:

| chapter | approach |
|---|---|
| [24](../24-gl-bundled-mesa/README.md) | bundled Mesa (renders anywhere) |
| [25](../25-gl-optional-drivers/README.md) | host drivers, optionally bundled |
| 26 | `SHARUN_MESA_PATH` (swappable) |

Continue with [Appendix A — Troubleshooting & FAQ](../appendix-a-troubleshooting/README.md),
or go back to the [index](../README.md).

---

[« Previous: 25 — Optional drivers](../25-gl-optional-drivers/README.md) · [Index](../README.md) · [Next: Appendix A — Troubleshooting & FAQ »](../appendix-a-troubleshooting/README.md)
