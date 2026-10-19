[« Previous: 29 — CMake](../29-cmake-host-drivers/README.md) · [Index](../README.md) · [Next: Appendix A — Troubleshooting & FAQ »](../appendix-a-troubleshooting/README.md)

# 30 — Autoconf/Automake: `PKG_CHECK_MODULES`

> **Goal.** The same SDL3 + OpenGL app and the same `libmul → libadd` chain,
> built with the classic **Autoconf + Automake + Libtool** stack, where every
> dependency is declared with `PKG_CHECK_MODULES` and no flag is written by hand
> — then packaged host-drivers-only like
> [chapter 27](../27-gl-host-drivers/README.md).

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. Three autotools projects

```
src/libadd/  configure.ac + Makefile.am  ->  libadd.la + add.h + libadd.pc
src/libmul/  configure.ac + Makefile.am  ->  libmul.la + mul.h + libmul.pc
src/app/     configure.ac + Makefile.am  ->  sdl3-triangle
```

**`libadd`** — a Libtool library plus a pkg-config file:

```m4
AC_INIT([libadd], [1.0.0])
AM_INIT_AUTOMAKE([foreign subdir-objects])
LT_INIT
AC_PROG_CC
AC_CONFIG_FILES([Makefile libadd.pc])
AC_OUTPUT
```

```make
lib_LTLIBRARIES = libadd.la
libadd_la_SOURCES = add.c
libadd_la_LDFLAGS = -version-info 1:0:0
include_HEADERS = add.h
pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = libadd.pc
```

**`libmul`** — finds `libadd` with `PKG_CHECK_MODULES` and links it:

```m4
PKG_CHECK_MODULES([LIBADD], [libadd])
```

```make
libmul_la_SOURCES = mul.c
libmul_la_CFLAGS  = $(LIBADD_CFLAGS)
libmul_la_LIBADD  = $(LIBADD_LIBS)
```

**the app** — one macro per dependency:

```m4
PKG_CHECK_MODULES([SDL3],  [sdl3])
PKG_CHECK_MODULES([EPOXY], [epoxy])
PKG_CHECK_MODULES([LIBMUL], [libmul])   # pulls libadd in transitively
```

```make
sdl3_triangle_SOURCES  = main.cpp
sdl3_triangle_CPPFLAGS = $(SDL3_CFLAGS) $(EPOXY_CFLAGS) $(LIBMUL_CFLAGS)
sdl3_triangle_LDADD    = $(SDL3_LIBS)  $(EPOXY_LIBS)  $(LIBMUL_LIBS)
```

(Automake turns `sdl3-triangle` into the `sdl3_triangle` variable prefix.)

## 2. Where the flags come from

| autotools needs | Nix provides it via |
|---|---|
| `autoreconf`, `autoconf`, `automake`, `libtool` | `nativeBuildInputs = [ autoreconfHook pkg-config ]` |
| the compiler | `stdenv` |
| `PKG_CHECK_MODULES` | `pkg-config` (macro + `PKG_CONFIG_PATH`) |
| `[sdl3] [epoxy] [libmul]` | `buildInputs = [ libmul sdl3 libepoxy ]` |
| `[libadd]` inside libmul | `buildInputs = [ libadd ]` in libmul |
| libadd for the app | `propagatedBuildInputs = [ libadd ]` in libmul |

`autoreconfHook` runs `autoreconf -i` for you in `preConfigure`, so there is no
build script to write and nothing is called by hand.

## 3. A real autotools gotcha: `exec_prefix`

Autoconf's default `libdir` is `${exec_prefix}/lib`, and `includedir` is
`${prefix}/include`. So a naive `.pc.in`

```
prefix=@prefix@
includedir=@includedir@
libdir=@libdir@
```

substitutes to `libdir=${exec_prefix}/lib` — and pkg-config then fails with:

```
Variable 'exec_prefix' not defined in '…/libadd.pc'
```

The fix is to define it:

```
prefix=@prefix@
exec_prefix=@exec_prefix@
includedir=@includedir@
libdir=@libdir@
```

## 4. Run it

```sh
nix build .#app               --max-jobs 1 --cores 1
nix build .#portable          --max-jobs 1 --cores 1   # AppDir (36 MB)
nix build .#portable-appimage --max-jobs 1 --cores 1   # 14 MB, host drivers only
```

## 5. Verify

The build's `checkPhase` runs the app and checks the chain:

```
OpenGL 4.6 (Compatibility Profile) Mesa 26.1.4 | AMD Radeon Vega 8 Graphics (radeonsi, …)
score = mul(3, 14) = 42
rendered 61 frame(s) in ~1 second(s)
```

## 6. The three build systems, side by side

| | discover a dep | link it | transitive dep |
|---|---|---|---|
| Meson ([28](../28-meson-host-drivers/README.md)) | `dependency('x')` | `dependencies:` | `pkg.generate(requires:)` |
| CMake ([29](../29-cmake-host-drivers/README.md)) | `find_package` / `pkg_check_modules(… IMPORTED_TARGET)` | `target_link_libraries(PUBLIC)` | `PUBLIC` |
| Autoconf (this) | `PKG_CHECK_MODULES([X],[x])` | `$(X_CFLAGS)` / `$(X_LIBS)` | `Requires:` in the `.pc` |

In **all three**, the Nix side is identical: `buildInputs` supplies the
pkg-config/CMake search paths, and `propagatedBuildInputs` makes a dependency
transitive.

## 7. Pitfalls

* **`exec_prefix` in `.pc.in`.** See section 3.
* **Forgetting `propagatedBuildInputs`.** `PKG_CHECK_MODULES([LIBMUL],[libmul])`
  fails in the app because `libadd.pc` is not on `PKG_CONFIG_PATH`.
* **`extern "C"`.** C headers used from C++ — same as
  [chapter 28](../28-meson-host-drivers/README.md#4-one-c-gotcha-extern-c).
* **Automake variable names.** `sdl3-triangle` → `sdl3_triangle_*`.
* **Musl.** Host drivers only → **no musl** (chapter 27, section 4).

## 8. End of the guide

These three chapters show that "cross/nix dependency management" does not mean
manual flags: whatever the build system, the dependency goes in `buildInputs`
(and `propagatedBuildInputs` for transitivity), and the build system's own
discovery mechanism does the rest.

Continue with [Appendix A — Troubleshooting & FAQ](../appendix-a-troubleshooting/README.md),
or go back to the [index](../README.md).

---

[« Previous: 29 — CMake](../29-cmake-host-drivers/README.md) · [Index](../README.md) · [Next: Appendix A — Troubleshooting & FAQ »](../appendix-a-troubleshooting/README.md)
