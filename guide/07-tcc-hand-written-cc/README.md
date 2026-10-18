[« Previous: 06 — Variant 2: ship your own `bin/cc`](../06-tcc-own-bin-cc/README.md) · [Index](../README.md) · [Next: 08 — Replacing binutils »](../08-replacing-binutils/README.md)

# 07 — Variant 3: write the `cc` package

> **Goal.** See that `wrapCCWith` is not magic. A `cc` package is just a driver
> in `$out/bin` **plus** a `nix-support/setup-hook` that exports `CC`. Write both
> by hand and give the result straight to `stdenv.override`.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The two things a `cc` package needs

Everything nixpkgs does to make a compiler usable comes down to two artifacts:

| artifact | why it exists |
|----------|---------------|
| a driver in `$out/bin` | so the name on `PATH` resolves to your compiler |
| `$out/nix-support/setup-hook` | so `setup.sh` exports `CC` (and `$AR`, ...) in every build |

`wrapCCWith` builds those for you, with a lot of extra flag machinery. Here we
build them ourselves:

```nix
tccOwnCc = pkgs.runCommand "tcc-own-cc" { } ''
  mkdir -p $out/bin $out/nix-support

  # 1. the driver
  ln -s ${tcc}/bin/tcc $out/bin/cc

  # 2. the setup hook — the entire interface the stdenv needs
  {
    echo 'export CC=cc'
    echo 'export AR=${pkgs.binutils-unwrapped}/bin/ar'
    echo 'export RANLIB=${pkgs.binutils-unwrapped}/bin/ranlib'
    echo 'export STRIP=${pkgs.binutils-unwrapped}/bin/strip'
    echo 'export LD=${pkgs.binutils-unwrapped}/bin/ld'
  } > $out/nix-support/setup-hook
'';
```

## 2. Use it as the stdenv's compiler

```nix
tccOwnStdenv = pkgs.stdenv.override {
  cc = tccOwnCc;
  hasCC = true;
  allowedRequisites = null;
};
```

That is it. There is no wrapper script in front of TCC, so the flags are exactly
those you put in the hook (here: none), and `$AR`/`$LD` are the raw binutils you
named.

## 3. Run it

```sh
nix build .#ownccDemo --max-jobs 1 --cores 1
./result/bin/hello
# add(6, 7) = 13
```

The build log prints:

```
CC=cc  -> /nix/store/…-tcc-own-cc/bin/cc
AR=/nix/store/…-binutils-…/bin/ar
```

## 4. Verify

```sh
$ c=$(nix eval --raw .#env.tccOwnCc)
$ ls "$c/bin" "$c/nix-support"
$c/bin:          $c/nix-support:
cc               setup-hook
$ cat "$c/nix-support/setup-hook"
export CC=cc
export AR=/nix/store/…-binutils-…/bin/ar
…
```

The `setup-hook` is the whole reason `$CC` exists in the build. This is the same
file `wrapCCWith` writes in variants 1 and 2 — just shorter.

## 5. The mandatory setup hook

This is the single most important lesson of the chapter, and it is easy to
verify: **a package that ships only `bin/cc` and no `nix-support/setup-hook`
leaves `$CC` empty**, and the build fails:

```
CC=[]                     # a bin/cc package without a hook
<no command> not on PATH
compile FAILED
```

The wrapper is part of `defaultNativeBuildInputs` (chapter 03), and it is the
wrapper's `bin/` **plus its setup hook** that introduce the variables. A package
without the hook contributes neither the variable nor a working command.

## 6. Pitfalls

* **Forgetting the hook.** `$CC` stays empty. This is not a typo you can ignore:
  the failure message is unhelpful ("command not found"), because the variable
  expands to nothing.
* **Relative tool paths in the hook.** Always use absolute store paths (as above);
  a build environment has no guarantee about `PATH` beyond what the hook sets.
* **Expecting hardening/`-isystem` injection.** A hand-written hook does whatever
  you wrote — no more. That is a feature (full control) and a hazard (you may
  forget something the wrapper would have done).
* **`CXX`.** Nothing sets it here. If you need C++, add `export CXX=…` and make
  sure the compiler actually has a C++ frontend.

## 7. Summary of Part 2's three variants

| # | package provides | `CC` | flags come from | package |
|---|------------------|------|-----------------|---------|
| 1 | `bin/gcc` → tcc | `gcc` | nixpkgs cc-wrapper | `.#hello` (ch. 05) |
| 2 | `bin/cc` (your script) | `cc` | your script | `.#binccDemo` (ch. 06) |
| 3 | `bin/cc` + `setup-hook` | `cc` | your hook | `.#ownccDemo` (ch. 07) |

## 8. What's next

You can replace the compiler. The other two parts are just as replaceable:
[chapter 08](../08-replacing-binutils/README.md) covers **binutils**, and
[chapter 09](../09-replacing-libc/README.md) covers the **C library**.

---

[« Previous: 06 — Variant 2: ship your own `bin/cc`](../06-tcc-own-bin-cc/README.md) · [Index](../README.md) · [Next: 08 — Replacing binutils »](../08-replacing-binutils/README.md)
