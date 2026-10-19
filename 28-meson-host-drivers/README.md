[« Previous: 27 — Host drivers only](../27-gl-host-drivers/README.md) · [Index](../README.md) · [Next: 29 — CMake »](../29-cmake-host-drivers/README.md)

# 28 — Meson: a real build system, dependencies the Nix way

> **Goal.** Build the SDL3 + OpenGL app **with Meson**, where the app depends on
> `libmul`, which depends on `libadd` — and **no compiler or linker flag is
> written by hand**. Everything (`-I`, `-L`, `-l`, the compiler itself) comes from
> the build system plus ordinary Nix `buildInputs`. Then package it host-drivers-
> only, like [chapter 27](../27-gl-host-drivers/README.md).

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. The anti-pattern this replaces

Chapters 24–27 built the app with a hand-written command:

```sh
# DON'T do this
$CXX -std=c++17 -O2 -I${sdl3}/include -I${epoxy}/include main.cpp \
  -o sdl3-triangle -L${sdl3}/lib -lSDL3 -L${epoxy}/lib -lepoxy
```

That hard-codes the compiler, the include paths and the libraries. It does not
scale, it does not carry dependencies transitively, and it duplicates what
`buildInputs` already provides. Here, instead, each piece is a normal package
with a real build system.

## 2. Three Meson projects, one dependency chain

```
src/libadd/   meson.build  ->  libadd.so + add.h + libadd.pc
src/libmul/   meson.build  ->  libmul.so + mul.h + libmul.pc   (depends on libadd)
src/app/      meson.build  ->  sdl3-triangle                   (depends on libmul, sdl3, epoxy)
```

**`libadd`** — a library and a pkg-config file:

```meson
project('libadd', 'c', version : '1.0.0')
libadd = library('add', 'add.c', version : meson.project_version(), install : true)
install_headers('add.h')
pkg = import('pkgconfig')
pkg.generate(libadd, name : 'libadd', version : meson.project_version())
```

**`libmul`** — depends on `libadd` **by name**:

```meson
libadd_dep = dependency('libadd')          # resolved via pkg-config
libmul = library('mul', 'mul.c', dependencies : libadd_dep, install : true)
pkg.generate(libmul, requires : libadd_dep) # advertise the transitive dep
```

**the app** — depends on everything by name:

```meson
sdl3   = dependency('sdl3')
epoxy  = dependency('epoxy')
libmul = dependency('libmul')              # pulls libadd in transitively
executable('sdl3-triangle', 'main.cpp',
  dependencies : [sdl3, epoxy, libmul], install : true)
```

## 3. Where the flags come from (nothing manual)

| what Meson needs | who provides it |
|---|---|
| the compiler | `stdenv` (`$CXX`, via the cc-wrapper) |
| Meson + Ninja + pkg-config | `nativeBuildInputs = [ meson ninja pkg-config ]` |
| `dependency('sdl3')`, `('epoxy')` | `buildInputs = [ sdl3 libepoxy ]` → their `.pc` files on `PKG_CONFIG_PATH` |
| `dependency('libmul')` | `buildInputs = [ libmul ]` |
| `dependency('libadd')` (inside libmul) | `buildInputs = [ libadd ]` in **libmul** |
| `libadd` for the **app** | `propagatedBuildInputs = [ libadd ]` in **libmul** |

That last row is the lesson: `libmul.pc` says `Requires: libadd`, so anything
that links `libmul` must also be able to find `libadd`'s pkg-config file. In Nix
that is exactly what **`propagatedBuildInputs`** is for:

```nix
libmul = pkgs.stdenv.mkDerivation {
  src = ./src/libmul;
  nativeBuildInputs = [ meson ninja pkg-config ];
  buildInputs = [ libadd ];
  propagatedBuildInputs = [ libadd ];   # <- consumers get it too
};
```

The Nix Meson setup hook runs `meson setup`, `ninja` and `meson install` for you
— there is no `buildPhase` to write.

## 4. One C++ gotcha: `extern "C"`

The app is C++ and the libraries are C. A C++ caller mangles `mul(int,int)` to
`_Z3mulii`, which does not match the C symbol `mul`. The headers therefore carry

```c
#ifdef __cplusplus
extern "C" {
#endif
int mul(int a, int b);
#ifdef __cplusplus
}
#endif
```

Without it the link fails with `undefined reference to 'mul(int, int)'`.

## 5. Run it

```sh
nix build .#app               --max-jobs 1 --cores 1
nix build .#portable          --max-jobs 1 --cores 1   # AppDir (36 MB)
nix build .#portable-appimage --max-jobs 1 --cores 1   # 14 MB, host drivers only
```

## 6. Verify

The app's `checkPhase` runs it headlessly and asserts the dependency chain was
actually linked in:

```sh
score = mul(3, 14) = 42      # <- computed by libmul -> libadd
rendered 61 frame(s) in ~1 second(s)
```

Inspect what the libraries installed:

```sh
$ find $(nix build --no-link --print-out-paths .#libmul) -name '*.pc'
…/lib/pkgconfig/libmul.pc
$ cat …/libmul.pc
Requires: libadd
Libs: -L${libdir} -lmul
Cflags: -I${includedir}
```

And the bundle runs on a real host with the **host's** driver (no bundled GL):

```sh
$ env -i DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" ./result/bin/sdl3-triangle --seconds 1
OpenGL 4.6 (Compatibility Profile) Mesa 26.1.4 | AMD Radeon Vega 8 Graphics (radeonsi, …)
score = mul(3, 14) = 42
rendered 61 frame(s) in ~1 second(s)
```

## 7. Pitfalls

* **Forgetting `propagatedBuildInputs`.** `dependency('libmul')` then fails with
  "Package libadd was not found", because the app cannot see `libadd.pc`.
* **Missing `extern "C"`.** The link fails on the mangled name (section 4).
* **Missing `pkg-config` in `nativeBuildInputs`.** Meson cannot run
  `dependency()` lookups.
* **Writing flags anyway.** If you find yourself adding `-I`/`-L`, stop: put the
  dependency in `buildInputs` and let the setup hooks do it.
* **Musl.** Same as chapter 27 — host drivers only, so **no musl**.

## 8. What's next

[Chapter 29](../29-cmake-host-drivers/README.md) does the same thing with
**CMake** (`find_package` / `pkg_check_modules`), and
[chapter 30](../30-autoconf-host-drivers/README.md) with **Autoconf/Automake**.

---

[« Previous: 27 — Host drivers only](../27-gl-host-drivers/README.md) · [Index](../README.md) · [Next: 29 — CMake »](../29-cmake-host-drivers/README.md)
