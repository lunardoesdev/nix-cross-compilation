[« Previous: 19 — FHS libraries, the dynamic way](../19-fhs-libraries-dynamic/README.md) · [Index](../README.md) · [Next: 21 — Extra platforms that need no LLVM build »](../21-extra-platforms-no-llvm/README.md)

# 20 — FHS libraries, the static way

> **Goal.** Package the same two libraries as **static archives** (`.a`) for a
> normal distribution: no shared objects, no `SONAME`, no `$ORIGIN`, no runtime
> dependency at all. Consumers link the code *into* their binary.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. What changes vs the dynamic way

| | dynamic (chapter 19) | static (this chapter) |
|---|---|---|
| artifact | `libmul.so.1.0.0` + symlinks | `libmul.a` |
| compile flags | `-fPIC`, `-shared` | plain `-c` |
| version identity | `SONAME libmul.so.1` | none |
| runtime dependency | yes (the `.so` must be present) | **no** |
| relocation trick | `$ORIGIN` RUNPATH | not applicable |
| link a consumer | `-lmul -ladd` | `-lmul -ladd` (archives pulled in) |

## 2. The libraries

```sh
$CC -O2 -Wall -Wextra -c add.c -o add.o      # note: no -fPIC
$AR rcs libadd.a add.o
```

The bundle:

```
cdemo-libs-static/
├── include/{add.h,mul.h}
└── lib/
    ├── libadd.a
    ├── libmul.a
    └── pkgconfig/{libadd.pc,libmul.pc}
```

## 3. Static pkg-config

Because `libmul.a` references `add()`, a consumer must link **both** archives.
The `.pc` file says so:

```
Name: libmul
Libs: -L${libdir} -lmul -ladd
```

(`Libs.private` is the more "correct" field for transitive static deps, but
putting both in `Libs` is simpler and always works for this demo.)

## 4. Run it

```sh
nix build .#fhs-libs-static     --max-jobs 1 --cores 1
nix build .#fhs-libs-static-tar --max-jobs 1 --cores 1
tar --zstd -xf result/cdemo-libs-static-x86_64.tar.zst
```

## 5. Verify

The build checks a real static link (`doInstallCheck`):

```sh
$ CC test.c -Iinclude -Llib -Wl,-Bstatic -lmul -ladd -Wl,-Bdynamic -o app
$ ./app
mul(6, 7) = 42
```

`-Wl,-Bstatic … -Wl,-Bdynamic` links **our** libraries statically but keeps the C
library dynamic. That is usually what you want on a glibc distro.

Use it via pkg-config:

```sh
$ PKG_CONFIG_PATH=lib/pkgconfig pkg-config --cflags --libs libmul
-I…/include -L…/lib -lmul -ladd
```

## 6. Fully static binaries (and why this chapter stops short)

A **fully** static binary (`-static`, no libc dependency at all) needs a static C
library. nixpkgs' default glibc does not ship `libc.a` in the link path, so:

```sh
$ cc test.c -static … -lmul -ladd
ld.bfd: cannot find -lc
ld.bfd: have you installed the static version of the c library ?
```

To go fully static, build with a static package set:

* **musl** — `pkgs.pkgsStatic` / `pkgsCross.musl64` give a statically linkable
  libc; this is the usual choice for "runs anywhere" binaries.
* or add `pkgs.glibc.static` to the link path.

That is exactly the territory of [chapter 21](../21-extra-platforms-no-llvm/README.md),
which builds the libraries with the musl static target.

## 7. Pitfalls

* **`-fPIC` not needed.** Static archives may contain non-PIC objects; adding
  `-fPIC` wastes a little performance but is harmless. Omit it for clarity.
* **Link order.** `libmul.a` references `add`, so `-lmul` before `-ladd`; a wrong
  order gives `undefined reference to 'add'`.
* **Expecting `$ORIGIN`.** It is an ELF runtime concept; static archives have no
  runtime.
* **`-static` with default glibc.** Fails with `cannot find -lc` (section 6).
* **Duplicate symbols.** If two static archives both define a symbol, the linker
  reports it; keep leaf dependencies (like `libadd`) in exactly one archive.

## 8. What's next

[Chapter 21](../21-extra-platforms-no-llvm/README.md) adds more targets that need
no LLVM build — including a **musl static** build, which is the natural home for
fully static binaries.

---

[« Previous: 19 — FHS libraries, the dynamic way](../19-fhs-libraries-dynamic/README.md) · [Index](../README.md) · [Next: 21 — Extra platforms that need no LLVM build »](../21-extra-platforms-no-llvm/README.md)
