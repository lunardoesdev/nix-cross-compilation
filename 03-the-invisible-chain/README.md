[« Previous: 02 — Your first cross flake](../02-first-cross-flake/README.md) · [Index](../README.md) · [Next: 04 — Building TCC from source »](../04-tcc-from-source/README.md)

# 03 — The invisible chain

> **Goal.** Understand exactly how the `cc` and `binutils` attributes become the
> `$CC` / `$AR` / `$LD` variables a build uses, why `$CC` is *not* the real
> compiler, and where every injected flag (`-B`, `-idirafter`, `-isystem`, the
> hardening flags) comes from. This is the knowledge you need before you replace
> any part of a toolchain in Part 2.

The chapter ships a flake whose only interesting output is an app that prints the
whole translation for you:

```sh
nix run .#explain --max-jobs 1 --cores 1
```

Everything in the output below is read out of the *real* packages Nix built; none
of it is hard-coded prose.

---

## 1. The problem

A build script written in 1985 expects a compiler in the environment variable
`CC`, an archiver in `AR`, and a linker in `LD`:

```sh
$CC -Os -c add.c -o add.o
$AR rcs libadd.a add.o
```

Nix wants hermetic, reproducible builds, so it does **not** put tools in `/usr/bin`.
It puts packages in `/nix/store/<hash>-<name>`. So how do these variables get set,
and how does `CC=arm-none-eabi-gcc` end up resolving to a store path?

There are exactly three steps.

## 2. Step 1 — the stdenv puts `cc` into every build

`stdenv.mkDerivation` is bash plus a pile of setup hooks. The stdenv's definition
lists the compiler among its default build inputs
(`pkgs/stdenv/generic/default.nix`):

```nix
defaultNativeBuildInputs = extraNativeBuildInputs ++ defaultNativeBuildInputs0
  ++ lib.optionals hasCC [ cc ];
```

That is why the overridden stdenv in chapter 01 needed `hasCC = true;` — it is
the switch that adds *our* `cc` package to every derivation made with it.

## 3. Step 2 — a setup hook exports the variable names

At the start of a build, `setup.sh` sources `nix-support/setup-hook` from every
dependency (`pkgs/stdenv/generic/setup.sh`):

```sh
_addToEnv() {
  ...
  if [[ -f "$pkg/nix-support/setup-hook" ]]; then
      source "$pkg/nix-support/setup-hook"
  fi
}
```

The **cc-wrapper's** hook contains a line like:

```sh
export CC${role_post}=arm-none-eabi-gcc
export CXX${role_post}=arm-none-eabi-g++
```

The **bintools wrapper's** hook loops over `ar as ld nm objcopy objdump readelf
ranlib strip strings size windres rc` and exports each with the target prefix:

```sh
export AR=arm-none-eabi-ar
export AS=arm-none-eabi-as
export LD=arm-none-eabi-ld
...
```

That is the whole translation. `cc` and `binutils` are just packages whose setup
hooks define the variable names old build systems already use.

### Which package exports `CC`? (Two different packages are involved)

| package | example name | exports `CC`? |
|---------|--------------|---------------|
| the raw compiler | `arm-none-eabi-gcc-16.2.0` | **no** — only `bin/arm-none-eabi-gcc` + `passthru.isGNU` |
| the **cc-wrapper** (this is `env.cc`) | `arm-none-eabi-gcc-wrapper-16.2.0` | **yes** — its `setup-hook` contains `export CC…` |

The raw compiler is recorded in the wrapper, for inspection:

```sh
$ cat "$(nix eval --raw .#cc)/nix-support/orig-cc"
/nix/store/…-arm-none-eabi-gcc-16.2.0
```

`isGNU` / `isClang` (passthru flags on the raw compiler) do **not** choose the
*value* of `CC`. `wrapCCWith` reads them only to select **flags**. The value comes
from the driver **filename** found in the `cc` package:

| driver found in `$cc/bin` | variables | what `$CC` runs |
|---------------------------|-----------|-----------------|
| `gcc`   | `CC=<prefix>gcc`, `CXX=<prefix>g++` | the wrapper script |
| `clang` | `CC=<prefix>clang`, `CXX=<prefix>clang++` | the wrapper script |
| `arocc` | `CC=<prefix>arocc` | the wrapper script |
| `cc` only | `CC=<prefix>cc` — **the wrapper installs nothing** | your *raw* `bin/cc`, wrapper bypassed |
| anything else | `CC=<prefix>cc`, unresolved | nothing / some `cc` on `PATH` |

That last row is a trap and the seed of Part 2: to make your own compiler the
toolchain's `cc`, you either name its driver `gcc`/`clang`/`arocc`, ship your own
`bin/cc`, or write the `cc` package yourself.

The literal line in the wrapper is a template
(`pkgs/build-support/cc-wrapper/setup-hook.sh`):

```sh
export CC${role_post}=@named_cc@
```

and `@named_cc@` is substituted while the *wrapper package is built*, using the
name the installPhase found. The real output for our ARM target:

```
190:export CC${role_post}=arm-none-eabi-gcc
```

At build time `role_post` is empty for the package's own ("host") role, so the
line executes as `export CC=arm-none-eabi-gcc`.

## 4. Step 3 — `$CC` is a wrapper script that prepends flags

`CC` is not the compiler binary. It is a generated bash script in
`$cc-wrapper/bin/`. Its last lines are:

```sh
exec /nix/store/…-arm-none-eabi-gcc-16.2.0/bin/arm-none-eabi-gcc \
   ${extraBefore+"${extraBefore[@]}"} \
   ${params+"${params[@]}"} \
   ${extraAfter+"${extraAfter[@]}"}
```

The script also sources `nix-support/add-flags.sh`, which builds
`extraBefore`/`extraAfter` from files stored next to it. Those files are the
concrete answer to "where do the flags come from?":

| file | content (this chapter) |
|------|------------------------|
| `cc-cflags` | `-B…/arm-none-eabi-gcc-16.2.0-lib/arm-none-eabi/lib` |
| `cc-cflags-before` | `-fno-omit-frame-pointer` |
| `cc-ldflags` | `-L…/arm-none-eabi-gcc-16.2.0-lib/arm-none-eabi/lib` |
| `libc-cflags` | `-idirafter …/newlib-…/arm-none-eabi/include -idirafter …/gcc/…/include-fixed` |
| `libc-crt1-cflags` | `-B…/newlib-…/arm-none-eabi/lib` |
| `libc-ldflags` | (empty for bare-metal newlib) |

Which of these exist, and their contents, are decided by the toolchain parts you
chose:

* **`libc = targetPkgs.newlib`** → the `libc-*` files above.
* **`libc = null`** → no `libc-*` flags at all (freestanding).
* **`binutils = …`** → the cc-wrapper puts the bintools wrapper on `PATH`, so the
  real compiler finds your `as`/`ld`.
* **`cc = …`** → what the script finally `exec`s.

## 5. `targetPlatform` decides the prefix

The wrapper computes:

```nix
targetPrefix = optionalString (targetPlatform != hostPlatform)
  (targetPlatform.config + "-");
```

One condition produces every `arm-none-eabi-` in the tool names and variable
values above. For a native build the prefix is empty and you get `CC=gcc`,
`AR=ar`, etc.

## 6. Dependencies become `-isystem` and `-L`

Every `buildInputs` entry with an `include/` directory becomes
`-isystem <dep>/include` in `NIX_CFLAGS_COMPILE`; one with `lib/` becomes
`-L <dep>/lib` in `NIX_LDFLAGS`. That is why `libmul` in chapter 02 needed no
`-I`: the flag was injected for `libadd` automatically.

## 7. Hardening flags

`NIX_HARDENING_ENABLE` is a list of named hardening options (fortify, stack
protector, PIE, RELRO, ...). `add-hardening.sh` translates them into concrete
flags such as `-fstack-clash-protection`, `-fzero-call-used-regs=used-gpr`,
`-Wformat`. Chapter 10 shows how a compiler that cannot handle a flag tells the
wrapper to drop it.

## 8. See it yourself

The chapter's flake prints the whole translation. The essential part, from this
machine:

```
== target ==
buildPlatform  = x86_64-linux
targetPlatform = arm-none-eabi
targetPrefix   = 'arm-none-eabi-'  (empty == a native build)

== variables the setup hooks export ==
CC      = arm-none-eabi-gcc
CXX     = arm-none-eabi-g++
AR      = arm-none-eabi-ar
...
== raw compiler vs cc-wrapper (two different packages) ==
raw compiler : /nix/store/…-arm-none-eabi-gcc-16.2.0
wrapper      : /nix/store/…-arm-none-eabi-gcc-wrapper-16.2.0

== the CC line that makes $CC exist ==
  190:export CC${role_post}=arm-none-eabi-gcc

== flags the cc-wrapper injects ==
--- cc-cflags
-B/nix/store/…-arm-none-eabi-gcc-16.2.0-lib/arm-none-eabi/lib
--- libc-cflags
-idirafter /nix/store/…-newlib-arm-none-eabi-…/arm-none-eabi/include -idirafter …
--- libc-crt1-cflags
-B/nix/store/…-newlib-arm-none-eabi-…/arm-none-eabi/lib
```

You can also see the fully expanded command line for *any* build with
`NIX_DEBUG=1`:

```sh
nix build .#libadd --max-jobs 1 --cores 1 --impure --expr \
  '(builtins.getFlake (toString ./.)).packages.x86_64-linux.libadd.overrideAttrs { NIX_DEBUG = 1; }'
nix log <the .drv that prints>
```

And you can open the packages directly:

```sh
cc=$(nix eval --raw .#cc)
ls "$cc/bin" "$cc/nix-support"
cat "$cc/nix-support/libc-cflags" "$cc/nix-support/cc-cflags"
tail -30 "$cc/nix-support/setup-hook"
```

## 9. Pitfalls

* **Thinking Nix "sets `CC`".** It does not. Bash does, when `setup.sh` sources
  the wrapper's hook. Nix only evaluates nixpkgs and builds the wrapper.
* **Expecting the raw compiler package to work.** It exports no `CC`; if you pass
  it where a wrapper is expected, builds fail.
* **Editing `$CC` to add flags.** Use `NIX_CFLAGS_COMPILE`/`NIX_LDFLAGS`, or (for a
  custom compiler) `wrapCCWith { nixSupport.cc-cflags = ...; }` as shown in
  chapter 10.
* **Assuming `$CXX` exists for a C-only compiler.** The wrapper exports it
  regardless, but if the compiler has no C++ frontend the binary will not exist.

## 10. What's next

Now that you can see the chain, you can replace any link in it.
[Chapter 04](../04-tcc-from-source/README.md) starts Part 2 by building a compiler
that is *not* gcc — TinyCC — and shows the three different ways to make a stdenv
use it.

---

[« Previous: 02 — Your first cross flake](../02-first-cross-flake/README.md) · [Index](../README.md) · [Next: 04 — Building TCC from source »](../04-tcc-from-source/README.md)
