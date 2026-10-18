[« Previous: 11 — One recipe, many targets](../11-one-recipe-many-targets/README.md) · [Index](../README.md) · [Next: 13 — An application with dependencies »](../13-application-with-dependencies/README.md)

# 12 — Two libraries that depend on each other

> **Goal.** Build **two** C libraries, the second depending on the first, for
> every platform in the target table — with real, distro-shaped shared libraries
> and ordinary Nix dependency management.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The two libraries

| library | source | depends on | provides |
|---------|--------|------------|----------|
| `libadd` | `src/add.c` | — | `int add(int, int)` |
| `libmul` | `src/mul.c` | **libadd** | `int mul(int, int)` |

`mul` calls `add`, so `libmul` genuinely references `libadd` — visible later as
`NEEDED libadd.so.1`.

## 2. Passing the dependency

Two fields express it, and they are the same on every platform:

```nix
libmul = mkLib target {
  pname = "libmul";
  src = ./src;
  sources = [ "mul.c" ];
  headers = [ "mul.h" ];
  libName = "mul";
  deps = [ libadd ];      # a Nix dependency: headers from $dep/include,
                          # libraries from $dep/lib
  linkLibs = [ "add" ];   # how it is linked: -ladd
};
```

Inside the builder:

```nix
buildInputs = deps;                                            # Nix manages it
includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
depFlags = … "-L${d}/lib" … + " " + … "-l${l}" … linkLibs;
```

`deps` are ordinary derivations — the exact same mechanism as any nixpkgs
package. The explicit `-I`/`-L` are spelled out (instead of relying only on the
cc-wrapper's injection) so the *same* builder also works with `emcc` in
[chapter 17](../17-target-emscripten/README.md), which is not a cc-wrapper.

## 3. Shared libraries per platform

The builder handles the platform-specific output shapes so the recipe does not
have to:

| platform | static | shared | import lib | naming |
|----------|--------|--------|-----------|--------|
| Linux (ELF) | `libmul.a` | `libmul.so.1.0.0` | — | `SONAME libmul.so.1` + symlinks |
| Windows (PE) | `libmul.a` | `libmul.dll` | `libmul.dll.a` | no SONAME |

The ELF branch:

```sh
$CC -shared -Wl,-soname,"libmul.so.1" -o "libmul.so.1.0.0" obj/*.o -L… -ladd
ln -sf "libmul.so.1.0.0" "libmul.so.1"
ln -sf "libmul.so.1.0.0" "libmul.so"
```

The Windows branch:

```sh
$CC -shared -o "libmul.dll" obj/*.o -L… -ladd -Wl,--out-implib,"libmul.dll.a"
```

## 4. Run it

```sh
nix build .#linux-libmul   --max-jobs 1 --cores 1
nix build .#windows-libmul --max-jobs 1 --cores 1
```

## 5. Verify

Linux — a properly versioned shared library that depends on `libadd`:

```sh
$ ls "$(nix build --no-link --print-out-paths .#linux-libmul)/lib"
libmul.a  libmul.so -> libmul.so.1.0.0  libmul.so.1 -> libmul.so.1.0.0  libmul.so.1.0.0

$ readelf -d libmul.so.1.0.0 | grep -E 'SONAME|NEEDED'
 0x0000000000000001 (NEEDED)  Shared library: [libadd.so.1]
 0x0000000000000001 (NEEDED)  Shared library: [libc.so.6]
 0x000000000000000e (SONAME)  Library soname: [libmul.so.1]
```

Windows — a DLL plus its import library, and Nix links `libadd.dll` alongside it:

```sh
$ ls "$(nix build --no-link --print-out-paths .#windows-libmul)/bin"
libadd.dll  libmul.dll
$ ls …/lib
libmul.a  libmul.dll.a
```

## 6. Pitfalls

* **Forgetting `linkLibs`.** The dependency is present as a Nix input, but the
  linker still needs `-ladd` (or the archive/`.so` path). `deps` alone is not
  enough at link time.
* **Wrong link order with static archives.** `libmul.a` references `add`, so
  `-lmul` must come before `-ladd` (chapter 13).
* **Shipping only the DLL, not the import library.** Windows consumers link
  against `libmul.dll.a`; without it they cannot link.
* **Missing the `.so.<major>` symlink.** `DT_NEEDED` names `libmul.so.1`, so that
  symlink must exist at runtime; the unversioned `libmul.so` is only for the
  linker.
* **`$ORIGIN` vs absolute RUNPATH.** These libraries have a `/nix/store` RUNPATH
  (fine inside Nix). [Chapter 19](../19-fhs-libraries-dynamic/README.md) rewrites
  it to `$ORIGIN` for use on a normal distro.

## 7. What's next

[Chapter 13](../13-application-with-dependencies/README.md) adds the third piece:
an **application** that links both libraries, with a run-time check on the
platforms where it can actually run.

---

[« Previous: 11 — One recipe, many targets](../11-one-recipe-many-targets/README.md) · [Index](../README.md) · [Next: 13 — An application with dependencies »](../13-application-with-dependencies/README.md)
