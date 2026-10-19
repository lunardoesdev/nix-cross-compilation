[« Previous: 13 — An application with dependencies](../13-application-with-dependencies/README.md) · [Index](../README.md) · [Next: 15 — Target: Windows x86_64 »](../15-target-windows/README.md)

# 14 — Target: Linux x86_64

> **Goal.** Build the two libraries and the console program for native Linux,
> and see what "native" means in the same terms the other targets use. This is
> the baseline the cross targets are compared against.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. What "Linux target" means here

```nix
target = pkgs;   # the native package set
```

Nothing is cross: `build == host == x86_64-linux`. So the toolchain is the
ordinary one:

| part | value |
|------|-------|
| compiler | `gcc` (native, no prefix) |
| binutils | `ar`, `ld`, ... |
| libc | glibc |
| object format | ELF |
| program extension | none |
| runs on the build machine? | yes |

Because the binary runs here, the build can **check itself** — see section 4.

## 2. The build

The flake builds `libadd`, `libmul` (depending on `libadd`) and `uselib2`,
exactly as in chapters 12–13, but with a single target. The output shapes are the
Linux ones:

```
libadd/lib/libadd.a  libadd.so -> libadd.so.1.0.0  libadd.so.1  libadd.so.1.0.0
libmul/lib/libmul.a  libmul.so -> libmul.so.1.0.0  libmul.so.1  libmul.so.1.0.0
uselib2/bin/uselib2
```

## 3. Run it

```sh
nix build .#uselib2 --max-jobs 1 --cores 1
./result/bin/uselib2
# uselib2: add(6, 7) = 13
# uselib2: mul(6, 7) = 42
```

## 4. Verify — the self-check

Unlike the cross targets, Linux can run what it builds, so the flake has a real
`checkPhase`:

```nix
doCheck = true;
checkPhase = ''
  output="$(./uselib2)"; echo "$output"
  echo "$output" | grep -q 'mul(6, 7) = 42'
'';
```

The build fails if the program does not print the expected value, so a broken
`libmul`→`libadd` link is caught at build time rather than later.

Inspect the shared library:

```sh
$ readelf -d …/libmul/lib/libmul.so.1.0.0 | grep -E 'SONAME|NEEDED'
 (NEEDED)  Shared library: [libadd.so.1]
 (NEEDED)  Shared library: [libc.so.6]
 (SONAME)  Library soname: [libmul.so.1]
```

## 5. The one thing Linux is *not* good at here

These binaries carry a `/nix/store` RUNPATH, so they only run where `/nix/store`
exists. On a normal distribution they will not start. Making them portable is
the subject of [Part 5](../18-fhs-portable-sharun-uruntime/README.md), where the
libraries are also rebuilt with `$ORIGIN` RUNPATHs.

## 6. Pitfalls

* **Forgetting the check.** It is easy to build a native target and never run
  it; here you *can*, so do.
* **Assuming native == portable.** It is not (section 5).
* **Hard-coding `gcc`.** Use `$CC` even natively, so the recipe stays identical
  to the cross chapters.

## 7. What's next

[Chapter 15](../15-target-windows/README.md) keeps the same recipes and swaps the
target set to `pkgsCross.mingwW64` — same C, different object format, different
runtime library rules.

---

[« Previous: 13 — An application with dependencies](../13-application-with-dependencies/README.md) · [Index](../README.md) · [Next: 15 — Target: Windows x86_64 »](../15-target-windows/README.md)
