[« Previous: 18 — Portable bundles with sharun + uruntime](../18-fhs-portable-sharun-uruntime/README.md) · [Index](../README.md) · [Next: 20 — FHS libraries, the static way »](../20-fhs-libraries-static/README.md)

# 19 — FHS libraries, the dynamic way

> **Goal.** Package the two libraries for a normal (FHS) distribution as
> **versioned shared objects** with a relocatable `$ORIGIN` RUNPATH, headers and
> relocatable `pkg-config` files — usable by dropping them into `/usr`, or by
> pointing a compiler at the unpacked tree.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. What "FHS libraries" means

Chapter 18 bundled whole *programs*. This chapter packages the **libraries
themselves** the way a distro would ship them:

```
cdemo-libs/
├── include/
│   ├── add.h
│   └── mul.h
└── lib/
    ├── libadd.so -> libadd.so.1.0.0
    ├── libadd.so.1 -> libadd.so.1.0.0
    ├── libadd.so.1.0.0          # SONAME libadd.so.1
    ├── libmul.so -> libmul.so.1.0.0
    ├── libmul.so.1 -> libmul.so.1.0.0
    ├── libmul.so.1.0.0          # SONAME libmul.so.1
    └── pkgconfig/
        ├── libadd.pc
        └── libmul.pc
```

Two properties make it *relocatable*:

* **SONAME + versioned filenames.** `DT_SONAME = libmul.so.1`, with the
  `libmul.so.1` and `libmul.so` symlinks that consumers and the loader expect.
* **`RUNPATH = $ORIGIN`.** `libmul.so` finds `libadd.so` **right next to it**,
  wherever the tree is unpacked — no `/nix/store` reference anywhere.

## 2. The libraries

Same builder as before, but shared-only (no `.a` here; chapter 20 does static):

```sh
$CC -shared -Wl,-soname,"libmul.so.1" -o "libmul.so.1.0.0" obj/*.o -L… -ladd
ln -sf "libmul.so.1.0.0" "libmul.so.1"
ln -sf "libmul.so.1.0.0" "libmul.so"
```

## 3. The bundle and the `$ORIGIN` rewrite

```nix
installPhase = ''
  mkdir -p "$out/lib" "$out/include"
  cp -a ${libadd}/lib/. "$out/lib/"; cp -a ${libadd}/include/. "$out/include/"
  cp -a ${libmul}/lib/. "$out/lib/"; cp -a ${libmul}/include/. "$out/include/"
  chmod -R u+w "$out"

  find "$out/lib" -type f -name '*.so*' \
    -exec patchelf --set-rpath '$ORIGIN' {} \;
  … write pkg-config files …
'';
```

`dontFixup = true` keeps the `$ORIGIN` we set (Nix's fixup would otherwise add
store RPATHs again).

## 4. Relocatable pkg-config

The `.pc` files use `pcfiledir` so they work from any location:

```
prefix=${pcfiledir}/../..
libdir=${prefix}/lib
includedir=${prefix}/include
Name: libmul
Libs: -L${libdir} -lmul
Cflags: -I${includedir}
```

pkg-config expands `pcfiledir` at *use* time, so the paths follow the tree.

## 5. Run it

```sh
nix build .#fhs-libs     --max-jobs 1 --cores 1
nix build .#fhs-libs-tar --max-jobs 1 --cores 1
tar --zstd -xf result/cdemo-libs-x86_64.tar.zst
```

## 6. Verify

The build runs its own `doInstallCheck`, so a broken layout fails:

```sh
$ readelf -d …/lib/libmul.so.1.0.0 | grep -E 'SONAME|RUNPATH'
 (SONAME)   Library soname: [libmul.so.1]
 (RUNPATH)  Library runpath: [$ORIGIN]
```

Use the tree the way a distro would:

```sh
# in place, with the compiler pointed at it
cc app.c -Iinclude -Llib -lmul -ladd -o app
LD_LIBRARY_PATH=$PWD/lib ./app

# pkg-config
PKG_CONFIG_PATH=lib/pkgconfig cc app.c $(pkg-config --cflags --libs libmul) -o app
```

or install it into a prefix:

```sh
sudo cp -a cdemo-libs/include/* /usr/local/include/
sudo cp -a cdemo-libs/lib/*     /usr/local/lib/
sudo ldconfig
```

## 7. Pitfalls

* **Forgetting `dontFixup`.** Nix re-adds a store RPATH and the tree stops being
  relocatable.
* **Missing the `.so.<major>` symlink.** `DT_NEEDED` names `libmul.so.1`; that
  symlink must exist. The unversioned `libmul.so` is only for the linker.
* **Non-quoted heredoc for `.pc` files.** An unquoted heredoc expands
  `pcfiledir`/`prefix` at *build* time and produces a broken `.pc`. Use `<<'EOF'`
  (as the flake does) so pkg-config expands them later.
* **`libmul` cannot find `libadd`.** If you skip the `$ORIGIN` rewrite, `libmul`
  still points at the store; the tree then only works where `/nix/store` exists.
* **Assuming `$ORIGIN` works in a static library.** It is an ELF runtime concept;
  chapter 20 has no runtime at all.

## 8. What's next

[Chapter 20](../20-fhs-libraries-static/README.md) packages the same libraries as
**static archives** (`.a`) — no runtime dependency, no `$ORIGIN`, no loader.

---

[« Previous: 18 — Portable bundles with sharun + uruntime](../18-fhs-portable-sharun-uruntime/README.md) · [Index](../README.md) · [Next: 20 — FHS libraries, the static way »](../20-fhs-libraries-static/README.md)
