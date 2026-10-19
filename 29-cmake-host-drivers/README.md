[« Previous: 28 — Meson](../28-meson-host-drivers/README.md) · [Index](../README.md) · [Next: 30 — Autoconf/Automake »](../30-autoconf-host-drivers/README.md)

# 29 — CMake: `find_package` + `pkg_check_modules`

> **Goal.** The same SDL3 + OpenGL app, the same `libmul → libadd` dependency
> chain, built with **CMake** — discovering dependencies with `find_package` and
> `pkg_check_modules`, never with hand-written flags — then packaged
> host-drivers-only like [chapter 27](../27-gl-host-drivers/README.md).

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. Three CMake projects

```
src/libadd/  CMakeLists.txt  ->  libadd.so + add.h + libadd.pc
src/libmul/  CMakeLists.txt  ->  libmul.so + mul.h + libmul.pc   (needs libadd)
src/app/     CMakeLists.txt  ->  sdl3-triangle                   (needs libmul, SDL3, epoxy)
```

**`libadd`** installs a library, its header, and a pkg-config file:

```cmake
project(libadd VERSION 1.0.0 LANGUAGES C)
add_library(add add.c)
set_target_properties(add PROPERTIES VERSION ${PROJECT_VERSION}
                                    SOVERSION ${PROJECT_VERSION_MAJOR}
                                    PUBLIC_HEADER add.h)
install(TARGETS add LIBRARY DESTINATION lib ARCHIVE DESTINATION lib
                  PUBLIC_HEADER DESTINATION include)
configure_file(libadd.pc.in ${CMAKE_CURRENT_BINARY_DIR}/libadd.pc @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/libadd.pc DESTINATION lib/pkgconfig)
```

**`libmul`** finds `libadd` by name and forwards it:

```cmake
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBADD REQUIRED IMPORTED_TARGET libadd)
add_library(mul mul.c)
target_link_libraries(mul PUBLIC PkgConfig::LIBADD)   # PUBLIC -> transitive
```

**the app** mixes the two idiomatic discovery mechanisms:

```cmake
find_package(SDL3 REQUIRED)                              # SDL3 ships SDL3Config.cmake
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBMUL REQUIRED IMPORTED_TARGET libmul)
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
add_executable(sdl3-triangle main.cpp)
target_link_libraries(sdl3-triangle PRIVATE SDL3::SDL3 PkgConfig::LIBMUL PkgConfig::EPOXY)
```

## 2. Where the flags come from

| CMake needs | Nix provides it via |
|---|---|
| the compiler | `stdenv` |
| CMake + Ninja + pkg-config | `nativeBuildInputs = [ cmake ninja pkg-config ]` |
| `find_package(SDL3)` | `buildInputs = [ sdl3 ]` → `CMAKE_PREFIX_PATH` includes SDL3's config |
| `pkg_check_modules(... libmul epoxy)` | `buildInputs = [ libmul libepoxy ]` → `PKG_CONFIG_PATH` |
| `pkg_check_modules(... libadd)` in libmul | `buildInputs = [ libadd ]` |
| libadd for the app | `propagatedBuildInputs = [ libadd ]` in libmul |

The `PUBLIC` on `target_link_libraries(mul PUBLIC PkgConfig::LIBADD)` is CMake's
half of the same story: it makes `libadd` part of `libmul`'s interface, so the
app links it automatically. The Nix half is `propagatedBuildInputs`.

## 3. Run it

```sh
nix build .#app               --max-jobs 1 --cores 1
nix build .#portable          --max-jobs 1 --cores 1   # AppDir (36 MB)
nix build .#portable-appimage --max-jobs 1 --cores 1   # 14 MB, host drivers only
```

## 4. Verify

The build's `checkPhase` runs the app and asserts the chain is really linked in:

```
OpenGL 4.6 (Compatibility Profile) Mesa 26.1.4 | AMD Radeon Vega 8 Graphics (radeonsi, …)
score = mul(3, 14) = 42
rendered 61 frame(s) in ~1 second(s)
```

The pkg-config files are installed by CMake:

```sh
$ find $(nix build --no-link --print-out-paths .#libmul) -name '*.pc'
…/lib/pkgconfig/libmul.pc
```

## 5. Pitfalls

* **`pkg_check_modules` without `IMPORTED_TARGET`.** Then you get variables
  (`${LIBMUL_LIBRARIES}`, `${LIBMUL_INCLUDE_DIRS}`) and are back to writing
  flags by hand. Use `IMPORTED_TARGET` and link `PkgConfig::LIBMUL`.
* **`target_link_libraries` without `PUBLIC`.** `libadd` stops being part of
  libmul's interface, so the app must name it again.
* **Forgetting `propagatedBuildInputs`.** CMake's `PUBLIC` is only half; the app
  still needs `libadd.pc` on `PKG_CONFIG_PATH` at *configure* time.
* **`extern "C"`.** Same C-vs-C++ linkage lesson as
  [chapter 28](../28-meson-host-drivers/README.md#4-one-c-gotcha-extern-c).
* **Musl.** Host drivers only → **no musl** (chapter 27, section 4).

## 6. What's next

[Chapter 30](../30-autoconf-host-drivers/README.md) does the same with the
**Autoconf/Automake/Libtool** stack (`PKG_CHECK_MODULES`).

---

[« Previous: 28 — Meson](../28-meson-host-drivers/README.md) · [Index](../README.md) · [Next: 30 — Autoconf/Automake »](../30-autoconf-host-drivers/README.md)
