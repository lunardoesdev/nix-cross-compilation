[« Previous: 34 — Packaging an Android APK](../34-android-apk/README.md) · [Index](../README.md) · [Next: 36 — Customizing nixpkgs »](../36-customizing-nixpkgs/README.md)

# 35 — A musl-static bundle: the "runs anywhere" case

> **Goal.** Build a **fully static musl** binary and wrap it in a sharun AppDir /
> AppImage. The result has **no dynamic loader, no libc and no libraries** — it
> runs on any x86-64 Linux, glibc or musl, old or new.

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. Why static musl

[Chapter 18](../18-fhs-portable-sharun-uruntime/README.md) bundled glibc and its
loader. [Chapter 24](../24-gl-bundled-mesa/README.md) had to bundle a whole Mesa.
Both are necessary when you *need* dynamic loading. For a plain program you can
skip all of it:

| | glibc bundle | **musl-static** |
|---|---|---|
| dynamic loader | bundled | **none** |
| libc | bundled | **none** (linked in) |
| `lib/` directory | yes | **no** |
| AppImage size (CLI demo) | ~15 MB | **1.4 MB** |
| runs on musl | yes (bundled glibc) | **yes** (no libc needed) |
| `dlopen` / plugins / GL | yes | **no** |

`pkgsStatic` is nixpkgs built with musl and everything static:

```nix
static = pkgs.pkgsStatic;
libadd  = static.stdenv.mkDerivation { … };
uselib2 = static.stdenv.mkDerivation { … };
```

The resulting binary:

```sh
$ file result/bin/uselib2       # (the inner binary)
…: ELF 64-bit LSB executable, x86-64, statically linked
$ ldd result/bin/uselib2
        not a dynamic executable
```

## 2. The bundle has no libraries

Because there is nothing to load, `mkPortable` copies **only** the binary and
`sharun`:

```
uselib2-portable-static/
├── AppRun              -> sharun
├── bin/uselib2         -> sharun
├── shared/bin/uselib2  (the static ELF)
├── sharun
├── uselib2.desktop
└── .env
```

`sharun` detects that the target is a **static** ELF and simply executes it
(no interpreter, no `--library-path`). It is still useful as the AppDir/AppImage
wrapper and for desktop integration.

## 3. Run it

```sh
nix build .#portable          --max-jobs 1 --cores 1
nix build .#portable-tar      --max-jobs 1 --cores 1
nix build .#portable-appimage --max-jobs 1 --cores 1
```

## 4. Verify — the strongest portability test in the book

```sh
$ env -i result/bin/uselib2
uselib2: add(6, 7) = 13
uselib2: mul(6, 7) = 42
```

An empty environment, no `/nix/store`, no libc: it runs. The build check also
asserts that there is **no `lib/` directory and no loader**:

```nix
! test -e "$out/lib/ld-linux-x86-64.so.2"
! test -d "$out/lib"
```

And the AppImage is tiny:

```sh
$ ls -lh result/uselib2-static-x86_64.AppImage
-r-xr-xr-x … 1.4M …
```

## 5. The limits of static

Static linking is not free:

* **No `dlopen`.** glibc/musl NSS modules, glibc's `iconv`/`gconv`, GL drivers,
  PAM, and most plugin systems are loaded at runtime. A static binary cannot use
  them (or needs big workarounds).
* **No GPU.** OpenGL/Vulkan need a driver, which is a runtime library — this is
  why the GL chapters cannot be static (see
  [chapter 23](../23-gl-portability-overview/README.md)).
* **glibc static is discouraged** (NSS warnings, `getaddrinfo` problems); **musl
  static is the normal, supported choice**.
* **DNS/user lookups** use the libc built in, not the host's `/etc/nsswitch.conf`
  modules.

So: static musl is perfect for **self-contained CLI tools**, not for GUI/plugin
apps.

## 6. Pitfalls

* **Static glibc.** Works for simple programs but is officially discouraged;
  prefer musl.
* **Expecting `dlopen` to work.** It does not (section 5).
* **`pkgsStatic` everywhere.** It is a *parallel* package set; `pkgsStatic.foo`
  is the static build of `foo`. Mixing it with the normal set gives you two
  different libcs.
* **Assuming the AppImage still needs its runtime.** The uruntime is FUSE-less
  (extracts when needed), but the app itself needs nothing.
* **Stripping.** Add `strip`/`-s` if size matters; the demo is already 1.4 MB.

## 7. What's next

[Chapter 36](../36-customizing-nixpkgs/README.md) starts the "Nix craft" part:
overlays, `override`/`overrideAttrs`, and `overrideCC`.

---

[« Previous: 34 — Packaging an Android APK](../34-android-apk/README.md) · [Index](../README.md) · [Next: 36 — Customizing nixpkgs »](../36-customizing-nixpkgs/README.md)
