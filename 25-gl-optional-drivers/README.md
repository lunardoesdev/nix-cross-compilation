[« Previous: 24 — Bundled Mesa](../24-gl-bundled-mesa/README.md) · [Index](../README.md) · [Next: 26 — SHARUN_MESA_PATH »](../26-gl-sharun-mesa-path/README.md)

# 25 — Optional drivers: host-driver bundle + bundled variant

> **Goal.** Build the same C++ SDL3 + OpenGL triangle **twice** from one flake:
> a **host-driver** bundle (tiny, uses the machine's own driver — the only way to
> get NVIDIA acceleration) and a **bundled-Mesa** variant (renders anywhere,
> including musl). Learn how to choose between them.

The complete flake is in [`flake.nix`](flake.nix); the source in [`src/`](src).

---

## 1. One builder, one flag

Everything is shared; a single boolean decides whether the GL stack is copied:

```nix
mkPortable = { name, bundleGL, … }:
  stdenvNoCC.mkDerivation {
    installPhase = ''
      # app + glibc + DT_NEEDED closure …
    '' + lib.optionalString bundleGL ''
      # glvnd + Mesa (libgallium, dri/, glvnd manifest) …
    '' + ''
      # RPATH cleanup, .env, desktop file …
    '';
  };

portable        = mkPortable { bundleGL = false; … };  # host drivers
portableBundled = mkPortable { bundleGL = true;  … };  # bundled Mesa
```

* **`bundleGL = false`** — nothing GPU-facing is copied. The app loads the
  **host's** `libGL.so.1` / Mesa / NVIDIA driver at runtime, exactly like any
  normal program on that machine.
* **`bundleGL = true`** — a glibc Mesa (llvmpipe), glvnd and the DRI drivers are
  copied in, and the `.env` points the loader at them.

This is our Nix version of upstream `quick-sharun`'s `DEPLOY_OPENGL=1`
(bundle) versus `USE_HOST_MESA_DRIVERS=1` (host).

## 2. The sizes make the trade-off obvious

```sh
nix build .#portable-appimage             --max-jobs 1 --cores 1   # host drivers
nix build .#portable-bundled-gl-appimage  --max-jobs 1 --cores 1   # bundled Mesa
```

| output | AppImage | tar.zst | renders on musl? | NVIDIA GPU? |
|---|---|---|---|---|
| `portable` (host drivers) | **14 MB** | 15 MB | only if libc-compatible | **yes** |
| `portable-bundled-gl` | **89 MB** | 182 MB | **yes** | no (software) |

The difference is almost entirely `libLLVM`, which Mesa's `llvmpipe` needs. If
you want a middle ground, build Mesa without LLVM (upstream ships such a Mesa;
see the [overview](../23-gl-portability-overview/README.md), section 4).

## 3. Choosing

* **Ship one file that always renders, on any distro (glibc or musl), CPU is
  fine** → `portable-bundled-gl`.
* **Use the machine's real GPU, especially NVIDIA** → `portable` (host drivers).
  The proprietary NVIDIA blob is glibc-linked and broadly compatible, so a glibc
  bundle can load it; a musl one could not.
* **Both** → publish both, or use the runtime-switchable
  [`SHARUN_MESA_PATH`](../26-gl-sharun-mesa-path/README.md) approach.

## 4. Run it

```sh
nix build .#portable --max-jobs 1 --cores 1
./result/bin/sdl3-triangle --seconds 3
```

## 5. Verify

Each variant has its own headless check:

* the **host-driver** bundle is run through its bundled loader with nixpkgs'
  Mesa on the library path — simulating a host that provides a driver;
* the **bundled** variant is run with its own Mesa, as in chapter 24.

```sh
$ nix build .#portable --max-jobs 1 --cores 1 --no-link --print-out-paths
…-sdl3-triangle-portable-1        # 36 MB unpacked, no GL driver inside
```

```sh
$ ls "$(nix build --no-link --print-out-paths .#portable)/lib" | grep -c 'libGL\|gallium\|dri'
0
```

## 6. Pitfalls

* **A host-driver bundle on a machine with no compatible driver.** It fails with
  `Failed loading libGL.so.1` or `GLX is not supported`. That is the trade-off:
  tiny, but it depends on the host.
* **`--library-path` is the search path.** `sharun` runs the loader with
  `--library-path "$APPDIR/lib"` and then appends the host's directories. A
  `dlopen("libGL.so.1")` is resolved from *that* path, not from a leftover
  `LD_LIBRARY_PATH` — which is why the host-driver check adds the host dirs to
  `--library-path` rather than to `LD_LIBRARY_PATH`.
* **Forcing software in a bundled variant hides the GPU.** `LIBGL_ALWAYS_SOFTWARE=1`
  means NVIDIA/AMD are not used. Drop it (and stop overriding the glvnd vendor)
  if you want the bundle's Mesa to try hardware.
* **Assuming musl is covered by the host-driver variant.** It is not, in
  general: the host driver must match the app's libc.

## 7. What's next

[Chapter 26](../26-gl-sharun-mesa-path/README.md) keeps Mesa but moves it into a
separate directory behind **`SHARUN_MESA_PATH`**, so the same app can switch Mesa
versions at runtime without being rebuilt.

---

[« Previous: 24 — Bundled Mesa](../24-gl-bundled-mesa/README.md) · [Index](../README.md) · [Next: 26 — SHARUN_MESA_PATH »](../26-gl-sharun-mesa-path/README.md)
