[« Previous: 23 — Portable OpenGL: choosing where the driver comes from](../23-gl-portability-overview/README.md) · [Index](../README.md) · [Next: 25 — Optional drivers »](../25-gl-optional-drivers/README.md)

# 24 — Bundled Mesa: a C++ SDL3 + OpenGL app that renders anywhere

> **Goal.** Build a **C++** SDL3 application that draws an **OpenGL triangle**,
> shows it for three seconds and exits, and package it with **sharun + uruntime**
> so it runs on any x86-64 Linux — including **musl** distributions such as
> Alpine — with **no Nix, no `nixGL` and no matching host GPU driver**.

The complete flake is in [`flake.nix`](flake.nix); the source in [`src/`](src).

This is the "bundled Mesa" approach from the
[overview](../23-gl-portability-overview/README.md): the bundle carries its own
glibc Mesa, so it renders even where the host has no compatible driver. It
combines a real language runtime (C++), a real graphics API (OpenGL), and the
portable-bundle technique from
[chapter 18](../18-fhs-portable-sharun-uruntime/README.md).

---

## 1. The application

A single C++17 file, [`src/main.cpp`](src/main.cpp):

* creates an SDL3 window and an OpenGL context (3.3 requested),
* loads GL functions with **libepoxy** (no hand-written `glGetProcAddress`),
* draws one RGB triangle with a vertex + fragment shader,
* keeps it on screen for `--seconds N` (default **3**) or until you close it,
* prints the GL version/renderer and the frame count, then exits.

```sh
nix build .#app --max-jobs 1 --cores 1
./result/bin/sdl3-triangle --seconds 3
# OpenGL 4.6 (Compatibility Profile) Mesa 26.2.5 | llvmpipe (LLVM 21.1.8, 256 bits)
# rendered 1432 frame(s) in ~3 second(s)
```

## 2. What C++ adds

C++ means the binary needs the **C++ runtime** — `libstdc++.so.6` and
`libgcc_s.so.1` — in addition to libc. They are ordinary `DT_NEEDED`
dependencies, so the bundle's `ldd` pass picks them up automatically (section 4).
Nothing else changes versus a C program.

## 3. What OpenGL adds — and why musl is the hard part

Chapter 18's bundle deliberately shipped **no** GPU libraries and let the host
provide them (that is why it needed no `nixGL`). That works on a *glibc* host.
It **breaks on a musl host**:

* `sharun` runs the program with the bundle's own **glibc** loader. The program
  is a glibc process.
* On Alpine, the host's `libGL.so.1` and Mesa drivers are built against **musl**.
  Loading a musl library into a glibc process does not work — different libc,
  different ABI.

So to be *actually* portable, the bundle must bring its **own GL implementation**.
This chapter therefore **ships Mesa** (the `llvmpipe` software rasteriser), which
renders in pure CPU and needs no GPU driver at all:

```
bundle/lib/
├── libGL.so.1, libGLX.so.0, libEGL.so.1, libGLdispatch.so.0   (glvnd)
├── libGLX_mesa.so.0, libEGL_mesa.so.0, libgallium-*.so        (Mesa)
├── libLLVM.so.*                                               (used by llvmpipe)
├── dri/*.so                                                   (software drivers)
└── glvnd/egl_vendor.d/50_mesa.json                            (vendor manifest)
```

> **Trade-off.** Bundling Mesa + LLVM makes the bundle large: **~590 MB
> unpacked, ~90 MB as an AppImage**. That is the price of "renders anywhere,
> including musl". Chapter 18's host-driver bundle is far smaller but only works
> where the host's driver is ABI-compatible (glibc).

## 4. The bundle

`mkPortable` (see [`flake.nix`](flake.nix)) assembles the AppDir:

1. the real C++ ELF into `shared/bin/`, `sharun` into `bin/AppRun/sharun`;
2. the complete **glibc**;
3. the **glvnd** entry points (SDL/epoxy `dlopen` them, so `ldd` does not list
   them);
4. the **Mesa** vendor libraries, the `dri/` software drivers, and a rewritten
   glvnd manifest whose `library_path` is a bare soname so the bundle stays
   relocatable;
5. the `DT_NEEDED` closure of the app **and** of the Mesa seeds (this is how
   `libstdc++`, `libLLVM`, the X11 client libraries, and so on get in);
6. a `.env` with the GL environment.

### The `.env` — the `nixGL` problem, solved inside the bundle

On NixOS a GL program must be told where Mesa's vendor libraries and DRI drivers
are; that is what `nixGL` normally does. Here the bundle does it itself, pointing
at its own `lib/` (sharun expands `$APPDIR`):

```
LIBGL_ALWAYS_SOFTWARE=1
GALLIUM_DRIVER=llvmpipe
LD_LIBRARY_PATH=$APPDIR/lib
LIBGL_DRIVERS_PATH=$APPDIR/lib/dri
__GLX_VENDOR_LIBRARY_NAME=mesa
__EGL_VENDOR_LIBRARY_FILENAMES=$APPDIR/lib/glvnd/egl_vendor.d/50_mesa.json
```

`LIBGL_ALWAYS_SOFTWARE=1` forces the bundled software renderer. Remove it if you
want the bundle's Mesa to try hardware (only useful when the host kernel/DRM
allows it).

## 5. Run it

```sh
nix build .#portable              --max-jobs 1 --cores 1   # AppDir directory
nix build .#portable-tar          --max-jobs 1 --cores 1   # .tar.zst
nix build .#portable-appimage     --max-jobs 1 --cores 1   # single-file AppImage

./result/bin/sdl3-triangle --seconds 3
```

## 6. Verify

The build runs a headless check (`Xvfb` + the **bundled** Mesa through the
**bundled** loader), so a broken bundle fails the build.

To check by hand, copy the bundle somewhere and run it with an almost-empty
environment — keep only `DISPLAY` and `XAUTHORITY` (an X client needs them):

```sh
cp -r result /tmp/tri && chmod -R u+w /tmp/tri

# under a virtual X server, with everything else cleared:
xvfb-run -a -s "-screen 0 1024x768x24" \
  env -i DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" \
  /tmp/tri/bin/sdl3-triangle --seconds 1
# OpenGL 4.6 (Compatibility Profile) Mesa 26.2.5 | llvmpipe (LLVM 21.1.8, 256 bits)
# rendered 487 frame(s) in ~1 second(s)
```

The AppImage needs neither FUSE nor extraction flags:

```sh
env -i DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" /tmp/sdl3-triangle-x86_64.AppImage --seconds 1
```

Because the GL renderer string is `llvmpipe` (software) and the process uses the
bundle's own loader and libraries, this works identically on glibc and musl
hosts.

## 7. Pitfalls

* **Expecting the host driver to work on musl.** A musl `libGL` cannot be loaded
  into a glibc process. Bundle Mesa (this chapter) or build a musl-native app
  instead.
* **Forgetting `libstdc++`.** It is an `ldd` dependency, so the closure copy gets
  it — but if you ship only the `.exe`-equivalent you break C++.
* **Copying soname symlinks.** `ldd` prints the symlink path; `cp -a` would ship
  a **dangling** link. Dereference (`cp -L`) or copy the whole directory.
* **Missing the glvnd/DRI environment.** Without the `.env` variables the app
  fails with `GLX is not supported` (or `Could not find a valid EGL device`).
* **`env -i` without `DISPLAY`/`XAUTHORITY`.** X clients need both; `env -i` that
  drops them fails with `x11 not available` / "Authorization required".
* **Bundle size.** Bundling Mesa pulls in LLVM. If you only target glibc hosts,
  prefer chapter 25's host-driver approach, or a Mesa built without LLVM (see the
  [overview](../23-gl-portability-overview/README.md), section 4).
* **NVIDIA.** This bundle forces the software renderer, so an NVIDIA machine
  still renders on the CPU. To use the GPU (including the proprietary driver) use
  the [host-driver approach](../25-gl-optional-drivers/README.md).
* **Xvfb's GLX is old.** Under Xvfb the context may report "Compatibility
  Profile" even though 3.3 core was requested; on a real server you get the core
  profile.

## 8. What's next

[Chapter 25](../25-gl-optional-drivers/README.md) shows the same app as a
**host-driver** bundle by default, with the bundled-Mesa variant as an option —
the trade-off in the other direction. [Chapter 26](../26-gl-sharun-mesa-path/README.md)
keeps Mesa but puts it behind `SHARUN_MESA_PATH` so it can be swapped at runtime.

---

[« Previous: 23 — Portable OpenGL: choosing where the driver comes from](../23-gl-portability-overview/README.md) · [Index](../README.md) · [Next: 25 — Optional drivers »](../25-gl-optional-drivers/README.md)
