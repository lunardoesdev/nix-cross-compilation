[« Previous: 26 — `SHARUN_MESA_PATH`](../26-gl-sharun-mesa-path/README.md) · [Index](../README.md) · [Next: Appendix A — Troubleshooting & FAQ »](../appendix-a-troubleshooting/README.md)

# 27 — Host drivers only

> **Goal.** The smallest possible portable OpenGL app: **ship no driver at all**
> and use the machine's own. This is the approach that gets **hardware
> acceleration** (including the proprietary NVIDIA driver) — and it is the one
> that does **not** work on musl systems.

The complete flake is in [`flake.nix`](flake.nix); the source in [`src/`](src).

This is the same C++ SDL3 + OpenGL triangle as chapters
[24](../24-gl-bundled-mesa/README.md)–[26](../26-gl-sharun-mesa-path/README.md).
Chapter [25](../25-gl-optional-drivers/README.md) offers host drivers *and* a
bundled variant from one flake; this chapter is the **host-only** case, on its
own and explained fully.

---

## 1. What the bundle ships

```
sdl3-triangle-portable-host-drivers/
├── bin/sdl3-triangle   -> sharun   (hardlink)
├── AppRun              -> sharun   (hardlink)
├── lib/                            glibc + libstdc++ + SDL3 + epoxy + X11 + …
└── .env                            (empty)
```

**No GPU driver.** In particular: no Mesa, no DRI drivers, no vendor libraries
(`libGLX_mesa`, `libgallium`, `libGL.so.1`).

> It *does* contain glvnd's `libEGL.so.1` and `libGLdispatch.so.0`, because SDL3
> links them directly — those are **client/loader** libraries, not drivers. The
> actual driver (`libGLX_mesa.so.0` / `libEGL_mesa.so.0` / a vendor blob) is
> loaded from the host at runtime.

## 2. How it renders without a driver

SDL3 `dlopen`s `libGL.so.1` and the host's driver. `sharun` runs the app with its
bundled loader and appends the **host's** library directories after the bundled
ones:

```
/usr/local/lib:/usr/lib:/lib:/usr/lib64:/lib64  +  /etc/ld.so.cache dirs
+  /run/opengl-driver/lib  +  /run/current-system/sw/lib
```

So the app picks up whatever Mesa/NVIDIA the machine has. On NixOS the drivers
live in `/run/opengl-driver/lib`, which `sharun` already appends — so **no
`nixGL` wrapper is needed** there either.

## 3. Why this is the chapter for real GPUs

Because the driver is the machine's own, this is the only variant that gives
**hardware acceleration** and the only one that can use the **proprietary NVIDIA
driver** (a glibc-linked blob that cannot be bundled portably and cannot be used
from a musl process). Running the built bundle on a normal desktop:

```sh
$ env -i DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" ./result/bin/sdl3-triangle --seconds 1
OpenGL 4.6 (Compatibility Profile) Mesa 26.1.4 | AMD Radeon Vega 8 Graphics
  (radeonsi, raven, ACO, DRM 3.64)
rendered 60 frame(s) in ~1 second(s)
```

That is the **host's** Mesa driving the **host's** GPU — not `llvmpipe`.

## 4. The trade-off: no musl

This is the deliberate limitation of the chapter:

> **A driver must be built for the same libc as the process that loads it.**

The bundle is a glibc process. On a glibc distro it can load the host's glibc
Mesa/NVIDIA. On a **musl** distro (Alpine) the host's driver is musl-built and
**cannot** be loaded — `dlopen("libGL.so.1")` fails with a missing glibc symbol
such as `__memcpy_chk`.

So:

| runs on | this chapter | [24](../24-gl-bundled-mesa/README.md) / [26](../26-gl-sharun-mesa-path/README.md) |
|---|---|---|
| glibc distros | yes, **with GPU accel** | yes, software (unless host driver used) |
| musl distros | **no** | yes, software |
| NVIDIA accel | **yes** | no |

If you need "renders on musl too", use chapter 24 (bundled Mesa). If you need
both, publish two bundles — which is exactly what
[chapter 25](../25-gl-optional-drivers/README.md) does.

## 5. Run it

```sh
nix build .#portable          --max-jobs 1 --cores 1   # AppDir (36 MB)
nix build .#portable-tar      --max-jobs 1 --cores 1   # .tar.zst
nix build .#portable-appimage --max-jobs 1 --cores 1   # .AppImage (14 MB)

./result/bin/sdl3-triangle --seconds 3
```

Compare the sizes: **14 MB** here versus **89 MB** for the bundled-Mesa chapter.

## 6. Verify

The build proves two things:

```nix
# 1. no GL driver is bundled
if ls "$out"/lib/libGL.so.1 "$out"/lib/libGLX_mesa.so.0 "$out"/lib/libgallium-*.so …; then fail; fi

# 2. it renders against a *simulated host* driver
--library-path "$out/lib:${pkgs.mesa}/lib:${pkgs.libGL}/lib"
```

The second step puts nixpkgs' Mesa where a real host's `/usr/lib` would be, so
the check exercises the "host provides the driver" path (the Nix build sandbox
has no GPU). On a real machine you just run it — section 3.

## 7. Pitfalls

* **No driver on the target.** If the host has no GL driver (a bare container,
  a server), the app fails with `Failed loading libGL.so.1` or
  `GLX is not supported`. That is the price of a 14 MB bundle.
* **Musl hosts.** Not supported here — see section 4.
* **Assuming `LD_LIBRARY_PATH` helps.** `sharun` uses the loader's
  `--library-path` and appends the host directories itself; do not set
  `LD_LIBRARY_PATH`.
* **Old host Mesa.** You get whatever the machine has. A host with only OpenGL
  3.3 works (our shaders are `#version 330`); a host with less does not.
* **Bundling "just a little" GL.** The moment you copy any Mesa/vendor library
  you are back to chapter 24, with its libc-coupling — do not half-do it.

## 8. End of the guide

The four driver strategies:

| chapter | approach | musl | GPU accel |
|---|---|---|---|
| [24](../24-gl-bundled-mesa/README.md) | bundled Mesa | yes | no |
| [25](../25-gl-optional-drivers/README.md) | host default + bundled variant | both | host variant |
| [26](../26-gl-sharun-mesa-path/README.md) | `SHARUN_MESA_PATH` (swappable) | yes | no |
| 27 | host drivers only | no | **yes** |

Continue with [Appendix A — Troubleshooting & FAQ](../appendix-a-troubleshooting/README.md),
or go back to the [index](../README.md).

---

[« Previous: 26 — `SHARUN_MESA_PATH`](../26-gl-sharun-mesa-path/README.md) · [Index](../README.md) · [Next: Appendix A — Troubleshooting & FAQ »](../appendix-a-troubleshooting/README.md)
