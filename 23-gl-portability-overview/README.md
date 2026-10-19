[« Previous: 22 — devkitPro with devkitNix](../22-devkitpro-devkitnix/README.md) · [Index](../README.md) · [Next: 24 — Bundled Mesa »](../24-gl-bundled-mesa/README.md)

# 23 — Portable OpenGL: choosing where the driver comes from

> **Goal.** Understand the one rule that governs every portable GPU app, how
> `sharun` makes a bundle run on both glibc and musl systems, and the three ways
> to give a bundle an OpenGL driver — so you can pick the right one. This is a
> **text-only** chapter; the next three are the worked examples.

---

## 1. The rule: the driver must match the app's libc

A GL driver is a shared library the app loads at runtime. Shared libraries are
built **for a libc**. So:

> **A process can only load a driver built for the same libc it is.**

This is not a preference; it is a hard ABI fact. Concretely, a **musl** program
trying to load a glibc `libGL.so.1` fails immediately:

```
musl: dlopen(libGL.so.1) FAILED:
  Error relocating …/libGL.so.1: __memcpy_chk: symbol not found
```

`__memcpy_chk` is a glibc "fortify" symbol musl does not provide. The reverse
(a **glibc** program loading a musl library) *sometimes* works, because glibc
exports the superset of symbols — but it is not guaranteed and version skew
between the two Mesa builds causes its own problems.

Everything below follows from that one rule.

## 2. How `sharun` runs on both musl and glibc

`sharun` does **not** produce two builds. It bundles **one** userland — glibc —
plus glibc's **dynamic linker**, and never touches the host libc:

* it cannot `patchelf` a relative interpreter (the `$ORIGIN` is resolved *by* the
  interpreter), so instead it **runs the bundled loader first**:

  ```sh
  exec "$APPDIR"/ld-linux-x86-64.so.2 --library-path "$APPDIR"/lib "$APPDIR"/bin/app "$@"
  ```

* it uses `--library-path` rather than `LD_LIBRARY_PATH` (upstream's docs are
  blunt: never set `LD_LIBRARY_PATH` — it leaks into child processes);

* it fixes `/proc/self/exe` (the kernel points it at the loader) using
  `userland-execve`, so programs that inspect themselves still work.

Because the process's libc **is the bundled glibc**, the host's libc is
irrelevant: the same bundle runs on glibc, on musl (Alpine), on ancient glibc
(Ubuntu 6.10 era) and even directly on NixOS without any FHS wrapper.

**Why bundle glibc and not musl?** (from upstream's FAQ)

* the **proprietary NVIDIA driver** is a glibc-linked blob; a musl app cannot use
  it, which kills hardware acceleration on NVIDIA;
* it does not save meaningful space (libc is a small fraction of a bundle);
* and a glibc process can `dlopen` musl host libraries (used for optional host
  integration), while the reverse — as shown above — usually fails.

So glibc is the right base even though the target is "runs on musl".

## 3. `sharun` sets the GL environment for you

A GL app needs to be told where Mesa's **glvnd vendor libraries** and **DRI
drivers** live — this is the job `nixGL` does on NixOS. `sharun` does it
automatically *if it finds the files in the expected places*:

| if the bundle contains… | `sharun` sets |
|---|---|
| `lib/dri/` | `LIBGL_DRIVERS_PATH` |
| `share/glvnd/egl_vendor.d/` | `__EGL_VENDOR_LIBRARY_DIRS` |
| `share/vulkan/icd.d/` | `VK_DRIVER_FILES` |

So the idiomatic bundle just lays the files out correctly; a `.env` is only
needed for extras (e.g. forcing the software renderer).

## 4. The three ways to supply a driver

| approach | what the bundle ships | runs on musl? | NVIDIA accel? | size | chapter |
|---|---|---|---|---|---|
| **Bundled Mesa** | a glibc Mesa (llvmpipe) + glvnd + DRI | yes | no (software only) | big (LLVM) | [24](../24-gl-bundled-mesa/README.md) |
| **Host drivers** | nothing GPU; loads the host's | only if libc-compatible | yes (host blob) | tiny | [25](../25-gl-optional-drivers/README.md) |
| **`SHARUN_MESA_PATH`** | a Mesa in its own dir, swappable | yes | no (software only) | big | [26](../26-gl-sharun-mesa-path/README.md) |

* **Bundled Mesa** — the canonical approach: `quick-sharun` enables
  `DEPLOY_OPENGL=1` automatically for GPU apps. Bullet-proof, but the bundle
  carries Mesa and its `libLLVM` (~130 MB; upstream builds a **no-LLVM** Mesa to
  cut this to ~66 MB).
* **Host drivers** — ship no driver and let the host's be loaded. Tiny and it is
  the *only* way to use the proprietary NVIDIA driver, but it only works when
  the host driver matches the app's libc (glibc hosts, or sometimes musl via the
  one-way `dlopen` above). Upstream calls this `USE_HOST_MESA_DRIVERS=1`.
* **`SHARUN_MESA_PATH`** — bundle Mesa but keep it in a separate directory and
  point `SHARUN_MESA_PATH` at it. Same size, but you can **swap the Mesa version
  at runtime** without rebuilding the app, and you can ship one Mesa for many
  apps.

## 5. What about NVIDIA?

The proprietary NVIDIA driver is the awkward case, and it is worth stating
plainly:

* It is a **binary blob linked against old glibc**, so it is broadly compatible
  on its own — its only requirement is a *new enough* glibc, which a glibc
  bundle provides.
* Therefore a **glibc** bundle can use the host's NVIDIA driver; a **musl** one
  cannot (section 1). This is the main reason the ecosystem bundles glibc.
* But if the bundle also ships **Mesa** and forces software rendering (as
  chapter 24 does), NVIDIA is *not* used — you get `llvmpipe` on the CPU.
* `sharun` has NVIDIA-specific handling: it defaults
  `__EGL_VENDOR_LIBRARY_FILENAMES` to the host's `10_nvidia.json` when unset, and
  has EGL "prime" logic (`SHARUN_NO_NVIDIA_EGL_PRIME=1` to disable).
* To get NVIDIA acceleration you generally want the **host-driver** approach
  (chapter 25) — optionally combined with `cross-libc-dlopen`
  (`USE_HOST_DRIVERS_EXPERIMENTAL=1`) which lets a glibc bundle load even musl
  host drivers. It is experimental and only applies to apps that do not need a
  recent OpenGL (our 3.3 triangle qualifies).

Rule of thumb:

* **Ship it and it always renders (CPU)** → bundle Mesa (ch. 24/26).
* **Use the machine's real GPU, including NVIDIA** → host drivers (ch. 25).

## 6. What's next

Three worked examples of the *same* C++ SDL3 + OpenGL triangle, differing only
in how the driver is supplied:

* [24 — Bundled Mesa](../24-gl-bundled-mesa/README.md): self-contained, renders
  anywhere including musl.
* [25 — Optional drivers](../25-gl-optional-drivers/README.md): a host-driver
  bundle by default plus a bundled-Mesa variant.
* [26 — `SHARUN_MESA_PATH`](../26-gl-sharun-mesa-path/README.md): Mesa in its own
  directory, swappable at runtime.

---

[« Previous: 22 — devkitPro with devkitNix](../22-devkitpro-devkitnix/README.md) · [Index](../README.md) · [Next: 24 — Bundled Mesa »](../24-gl-bundled-mesa/README.md)
