[« Previous: 35 — A musl-static bundle](../35-musl-static-bundle/README.md) · [Index](../README.md) · [Next: 37 — CI with GitHub Actions »](../37-ci-github-actions/README.md)

# 36 — Customizing nixpkgs: overlays, `override`, `overrideAttrs`

> **Goal.** Change packages without forking nixpkgs: add your own packages with
> an **overlay**, tweak a package argument with **`override`**, change a
> derivation with **`overrideAttrs`**, and rebuild with a **different compiler**.

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. The four tools

| tool | changes | example |
|---|---|---|
| **overlay** | the package *set* | add `libadd`/`libmul` to `pkgs` |
| **`override`** | a *function argument* of a package | `optLevel = "-O0"` |
| **`overrideAttrs`** | the *derivation* | add a `-D` flag, rename, patch |
| **`clangStdenv` / `overrideCC`** | the *compiler* | build with clang instead of gcc |

## 2. Overlay

```nix
overlay = final: prev: {
  libadd = final.callPackage ./src/libadd { };
  libmul = final.callPackage ./src/libmul { };
};

myPkgs = pkgs.extend overlay;
libadd = myPkgs.libadd;
```

`final` is the finished set (so `final.callPackage` sees the overlay's own
additions — this is the "fixpoint"), `prev` is the set before the overlay. Use
`prev` only when you deliberately want the pre-overlay version.

Overlays compose: `pkgs.extend o1` then `.extend o2`, or pass `overlays = [ o1 o2 ]`
when importing nixpkgs.

## 3. `override` — change a function argument

The package is a function:

```nix
# src/libadd/default.nix
{ stdenv, optLevel ? "-O2" }: stdenv.mkDerivation { … $CC ${optLevel} … }
```

so:

```nix
libadd-o0 = libadd.override { optLevel = "-O0"; };
```

This only works for `callPackage`-style packages (functions with named args).
It is the **safe** way to tweak behaviour: the package author exposed the knob.

## 4. `overrideAttrs` — change the derivation

For anything the package does not expose, rewrite the derivation:

```nix
libadd-extra = libadd.overrideAttrs (old: {
  pname = "libadd-extra";
  buildPhase = old.buildPhase + ''
    $CC -DLIBADD_EXTRA -c add.c -o add_extra.o
    $AR rcs libadd.a add.o add_extra.o
  '';
});
```

`old` is the original attribute set (including the original `buildPhase`,
`src`, `buildInputs`, ...). You can override any attribute, add `patches`, change
`installPhase`, set `NIX_CFLAGS_COMPILE`, etc.

## 5. A different compiler

```nix
libadd-clang = pkgs.callPackage ./src/libadd { stdenv = pkgs.clangStdenv; };
```

or, equivalently, via `overrideCC`:

```nix
libadd-clang = (pkgs.overrideCC pkgs.stdenv pkgs.clang).callPackage ./src/libadd { };
```

## 6. Verify that each change really happened

| output | object size | compiler | extra symbol |
|---|---|---|---|
| `libadd` | 1168 B | GCC | — |
| `libadd-o0` | **1192 B** | GCC | — |
| `libadd-clang` | **992 B** | **clang 21.1.8** | — |
| `libadd-extra` | 1168 B | GCC | **`add_extra`** |

```sh
$ ar x $(nix build --no-link --print-out-paths .#libadd-clang)/lib/libadd.a add.o
$ readelf -p .comment add.o | grep clang
  [     0]  clang version 21.1.8

$ ar t $(nix build --no-link --print-out-paths .#libadd-extra)/lib/libadd.a
add.o
add_extra.o
$ nm add_extra.o | grep ' T '
0000000000000010 T add_extra
```

## 7. Pitfalls

* **`override` on a non-`callPackage` derivation.** It does not exist; use
  `overrideAttrs` (or fix the package to be a function).
* **Using `overrideAttrs` for a documented argument.** Prefer `override` when the
  package exposes it; `overrideAttrs` is for internals.
* **Overlay `prev` vs `final`.** `prev.libadd` bypasses your own overlay; use
  `final` unless you mean it.
* **Recursion in overlays.** Referring to `final.x` from inside `x` is infinite
  recursion — that is what `prev` is for.
* **Rebuilding the world.** Overriding a low-level package (glibc, gcc) rebuilds
  everything that depends on it; override the leaf you care about.
* **Forgetting `strictDeps`/`doCheck`.** `overrideAttrs` inherits the original
  values unless you change them.

## 8. What's next

[Chapter 37](../37-ci-github-actions/README.md) puts the whole guide into CI:
GitHub Actions, a binary cache, and `nix flake check`.

---

[« Previous: 35 — A musl-static bundle](../35-musl-static-bundle/README.md) · [Index](../README.md) · [Next: 37 — CI with GitHub Actions »](../37-ci-github-actions/README.md)
