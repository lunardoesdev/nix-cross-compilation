# nix-embed-crosscompilation

Two tiny C libraries cross-compiled for an embedded target with Nix — plus
worked examples of replacing each part of the toolchain with your own.

## Libraries

- `libadd` (`lib/add/`): `int add(int a, int b);`
- `libmul` (`lib/mul/`): `int multiply(int a, int b);` implemented with `add()`.

`libmul` depends on `libadd` through the normal Nix dependency mechanism
(`buildInputs` / `propagatedBuildInputs`), exactly like any other Nix package.

## Target

The target is one declaration in `flake.nix` — bare-metal ARM with newlib:

```nix
crossSystem = {
  config = "arm-none-eabi";  # GNU triple <cpu>-<vendor>-<os><abi>
  libc   = "newlib";         # C library linked on the target
};
```

`gcc = { arch, cpu, fpu, abi }`, `useLLVM`, `useZig` and `useArocc` are
documented (commented out) knobs in that declaration. Any other
`config`/`libc` targets a different platform entirely.

## How a cross toolchain is built from parts

A cross toolchain is four independent pieces plus three machine descriptions.
The flake names each one:

| piece                                  | what nixpkgs expects from it |
| -------------------------------------- | ---------------------------- |
| `cc` — compiler driver                 | a package whose driver is in `$out/bin`, named `gcc`, `clang` or `arocc` |
| `binutils` — as, ld, ar, objcopy, …    | `$out/bin/<targetPrefix>{ar,as,ld,nm,objcopy,ranlib,strip,...}` plus a `targetPrefix` attribute |
| `libc` — headers, start files, library | `$out/include/` and `$out/lib/` (`crt1.o`, `libc.a`); `null` = freestanding |
| `buildPlatform`                        | machine that runs the build |
| `hostPlatform`                         | machine the result runs on |
| `targetPlatform`                       | machine the produced compiler emits code for |

nixpkgs' `cc`-wrapper turns those pieces into `$CC`, `$AR`, `$LD`, … and the
matching flags. The `stdenv` then only needs to know the three platforms and
the `cc`; `mkDerivation` does the rest:

```nix
stdenv = nativePkgs.stdenv.override {
  inherit buildPlatform;
  hostPlatform   = targetPlatform;
  targetPlatform = targetPlatform;
  cc = cc;
  hasCC = true;
  extraBuildInputs = [ ];
  overrides = _: _: { };
  allowedRequisites = null;
};
```

The rest of this file is the "what if I want my own …" part.

## From Nix attributes to `$CC` and actual flags

This is the part that is normally invisible. Here is the exact chain, with
values taken from this repo.

### 1. `stdenv` puts `cc` into every build

`stdenv.mkDerivation` is bash plus `setup.sh`. The stdenv's own definition
includes the compiler in the default build inputs
(`pkgs/stdenv/generic/default.nix`):

```nix
defaultNativeBuildInputs = extraNativeBuildInputs ++ defaultNativeBuildInputs0
  ++ lib.optionals hasCC [ cc ];
```

So every derivation made with the stdenv has the `cc` package available.

### 2. Setup hooks export the variable names

`setup.sh` sources `nix-support/setup-hook` from every dependency. The
**cc-wrapper's** hook ends with:

```sh
export NIX_CC=/nix/store/...-arm-none-eabi-gcc-wrapper-16.2.0
export CC=arm-none-eabi-gcc
export CXX=arm-none-eabi-g++
```

The **bintools wrapper's** hook loops over `ar as ld nm objcopy objdump readelf
ranlib strip strings size windres rc` and exports each one:

```sh
export AR=arm-none-eabi-ar
export AS=arm-none-eabi-as
export LD=arm-none-eabi-ld
export NM=arm-none-eabi-nm
export OBJCOPY=arm-none-eabi-objcopy
export RANLIB=arm-none-eabi-ranlib
export STRIP=arm-none-eabi-strip
...
```

That is the entire translation: `cc` and `binutils` are packages whose setup
hooks define the variables build scripts already expect.

#### Which package actually defines `CC`?

Two different packages are involved, and the raw compiler is not the one that
defines `CC`:

| package | example name | exports `CC`? |
| --- | --- | --- |
| raw compiler | `arm-none-eabi-gcc-16.2.0` | **no** — provides `bin/arm-none-eabi-gcc`, `passthru.isGNU = true` |
| cc wrapper (this is `env.cc`) | `arm-none-eabi-gcc-wrapper-16.2.0` | yes — `nix-support/setup-hook` contains `export CC…` |

```sh
$ W=$(nix eval --raw .#env.cc); RAW=$(cat "$W/nix-support/orig-cc")
$ ls "$RAW/nix-support"
propagated-build-inputs
$ grep -r 'export CC' "$RAW/nix-support" || echo "raw gcc exports no CC"
raw gcc exports no CC
$ grep '^export CC' "$W/nix-support/setup-hook"
export CC${role_post}=arm-none-eabi-gcc
```

`isGNU` / `isClang` (passthru on the raw compiler) do **not** choose the value
of `CC`; `wrapCCWith` reads them only to select **flags**. `CC`'s value comes
from the driver **filename** found in `$ccPath` (`gcc`/`clang`/`arocc`) →
`named_cc` → `setup-hook.sh`'s `export CC${role_post}=@named_cc@`.

Finally, the hook is sourced by bash, not by Nix. In
`pkgs/stdenv/generic/setup.sh`:

```sh
_addToEnv() {
  ...
  if [[ -f "$pkg/nix-support/setup-hook" ]]; then
      nixTalkativeLog "sourcing setup hook '$pkg/nix-support/setup-hook'"
      source "$pkg/nix-support/setup-hook"
  fi
}
```

The wrapper is part of `defaultNativeBuildInputs`, so this runs in every
build. Nix (the package manager) only evaluates nixpkgs and builds the
wrapper; it never reads `isGNU`/`isClang` and never sets `CC`.

#### The literal source locations

The `gcc` attribute our flake uses is *already* the wrapper — nixpkgs applies
`wrapCCWith` to the raw compiler (`pkgs/development/compilers/gcc/ng/common/default.nix:218`):

```nix
gcc = wrapCCWith {
  cc = gccPackages.gcc-unwrapped;    # the raw compiler
  bintools = binutils;
  nixSupport = { cc-cflags = [ "-B…/libgcc/lib" … ]; };  # gcc's own -B flags
};
```

The wrapper package is created in `pkgs/build-support/cc-wrapper/default.nix`:

```nix
# line 424: this mkDerivation IS the wrapper package
stdenvNoCC.mkDerivation {
  pname = targetPrefix + (if name != "" then name else "${ccName}-wrapper");
  ...

# lines 559-566 (installPhase): choose the name and install bin/cc
    export named_cc=${targetPrefix}cc
    if [ -e $ccPath/${targetPrefix}gcc${exeSuffix} ]; then
      wrap ${targetPrefix}gcc $wrapper $ccPath/${targetPrefix}gcc${exeSuffix}
      ln -s ${targetPrefix}gcc $out/bin/${targetPrefix}cc
      export named_cc=${targetPrefix}gcc

# lines 636-640: tell the builder to publish the hook
  setupHooks = [
    ../setup-hooks/role.bash
  ]
  ++ optional (cc.langC or true) ./setup-hook.sh
```

The variable itself is a template in
`pkgs/build-support/cc-wrapper/setup-hook.sh`:

```sh
# line 119
export CC${role_post}=@named_cc@
```

`@named_cc@` is replaced while the *wrapper package* is being built. The
generic builder's `fixupPhase` (`pkgs/stdenv/generic/setup.sh`) concatenates
every `setupHooks` file into the output and substitutes environment variables:

```sh
if [ -n "${setupHooks:-}" ]; then
    for hook in ${setupHooks[@]}; do
        consumeEntire content < "$hook"
        substituteAllStream content "file '$hook'" >> "${!outputDev}/nix-support/setup-hook"
    done
fi
```

Because the installPhase did `export named_cc=arm-none-eabi-gcc`, the built
file contains the literal line:

```sh
$ W=$(nix eval --raw .#env.cc)
$ nix path-info --derivation "$W"
/nix/store/9jbrx…-arm-none-eabi-gcc-wrapper-16.2.0.drv
$ grep -n 'export CC' "$W/nix-support/setup-hook"
190:export CC${role_post}=arm-none-eabi-gcc
$ ls -l "$W/bin/arm-none-eabi-cc"
…/bin/arm-none-eabi-cc -> arm-none-eabi-gcc
```

Then, in a *consumer* build, `_addToEnv` in the same `setup.sh` sources it:

```sh
if [[ -f "$pkg/nix-support/setup-hook" ]]; then
    nixTalkativeLog "sourcing setup hook '$pkg/nix-support/setup-hook'"
    source "$pkg/nix-support/setup-hook"
fi
```

and `role_post` is empty for the host role, so the line executes as
`export CC=arm-none-eabi-gcc`. That is the exact moment `CC` comes into
existence.



### 3. `$CC` is a wrapper script that prepends flags

First a naming clarification: `CC` is only the conventional variable name for
"the C compiler command" — it does not mean GNU gcc. Its value is the name of
the driver family nixpkgs found inside the `cc` package:

| driver found in `$cc/bin` | exported variables |
| --- | --- |
| `gcc` | `CC=<prefix>gcc`, `CXX=<prefix>g++` |
| `clang` | `CC=<prefix>clang`, `CXX=<prefix>clang++` |
| `arocc` | `CC=<prefix>arocc` |
| none of those | default would be `<prefix>cc`, but the wrapper installs no such binary — expose your driver under one of the names above |

In this repo: the ARM target gives `CC=arm-none-eabi-gcc` (the driver *is*
gcc), and the TCC demo gives `CC=gcc` (because the TCC binary is exposed under
that name).

`$CC` is not the real compiler either. It is a generated bash script in
`$cc/bin/`; its last lines are:

```sh
exec /nix/store/...-arm-none-eabi-gcc-16.2.0/bin/arm-none-eabi-gcc \
   ${extraBefore+"${extraBefore[@]}"} \
   ${params+"${params[@]}"} \
   ${extraAfter+"${extraAfter[@]}"}
```

`extraBefore`/`extraAfter` are built by `nix-support/add-flags.sh` from files in
the wrapper. Their real contents in this repo:

| file | content |
| --- | --- |
| `nix-support/cc-cflags` | `-B…/arm-none-eabi-gcc-16.2.0-lib/arm-none-eabi/lib` |
| `nix-support/cc-cflags-before` | `-fno-omit-frame-pointer` |
| `nix-support/cc-ldflags` | `-L…/arm-none-eabi-gcc-16.2.0-lib/arm-none-eabi/lib` |
| `nix-support/libc-cflags` | `-idirafter …/newlib-arm-none-eabi…/arm-none-eabi/include -idirafter …/gcc/…/include-fixed` |
| `nix-support/libc-crt1-cflags` | `-B…/newlib-arm-none-eabi…/arm-none-eabi/lib` |
| `nix-support/libc-ldflags` | (C library linker flags; empty for this bare-metal newlib) |

Which of these exist and what they contain is decided by the attributes in the
flake:

- `libc = targetPkgs.newlib` → the `libc-*` files above; `libc = null` → they
  are absent/empty, so no `-idirafter`/`-B` for a C library.
- `binutils = …` → the wrapper prepends the bintools wrapper to `$PATH`, so
  the real compiler finds the `as`/`ld` you chose.
- `cc = …` → what the script `exec`s.

### 4. `targetPlatform` decides the prefix

The wrapper computes:

```nix
targetPrefix = optionalString (targetPlatform != hostPlatform)
  (targetPlatform.config + "-");
```

That one condition produces the `arm-none-eabi-` in every tool name and
variable value above, and the matching `-B`/`-idirafter` paths. For a native
build the prefix is empty, so `CC=gcc`, `AR=ar`, etc.

### 5. Dependencies become `-isystem` / `-L`

Every `buildInputs` entry with an `include/` directory is added to
`NIX_CFLAGS_COMPILE` as `-isystem <dep>/include` by the cc-wrapper's env hook;
one with a `lib/` directory becomes `-L <dep>/lib`. `flake.nix` therefore has
no `-I` in `libmul`'s build phase.

### 6. Hardening flags

`NIX_HARDENING_ENABLE` (set by the setup hooks, emptied by
`hardeningDisable = [ "all" ]`) is translated by `add-hardening.sh` into
`-fstack-clash-protection`, `-fzero-call-used-regs=used-gpr`, `-Wformat`,
`-fstrict-flex-arrays=1`, `-fno-strict-overflow`, ….

### See it for yourself

The real expanded command is printed when `NIX_DEBUG=1`:

```sh
nix build --impure --cores 1 --max-jobs 1 --expr \
  '(builtins.getFlake (toString ./.)).packages.x86_64-linux.libmul.overrideAttrs { NIX_DEBUG = 1; }'
nix log <the .drv it prints>
```

Relevant excerpt (paths shortened):

```
CC=arm-none-eabi-gcc
CXX=arm-none-eabi-g++
AR=arm-none-eabi-ar
LD=arm-none-eabi-ld

original flags:
  -Os -c mul.c -o mul.o

extra flags after:
  -B…/newlib…/arm-none-eabi/lib
  -idirafter …/newlib…/arm-none-eabi/include
  -idirafter …/gcc…/include-fixed
  -B…/gcc-16.2.0-lib/arm-none-eabi/lib
  -isystem …/libadd-arm-none-eabi-0.1.0/include     # from buildInputs
```

And the wrapper's own files can be inspected directly:

```sh
cc=$(nix eval --raw .#env.cc)
ls "$cc/bin" "$cc/nix-support"
cat "$cc/nix-support/libc-cflags" "$cc/nix-support/cc-cflags"
cat "$cc/nix-support/setup-hook" | tail -30
```

Even quicker, the flake prints the whole translation:

```sh
nix run .#explain --cores 1 --max-jobs 1
```

```
== target ==
buildPlatform  = x86_64-linux
targetPlatform = arm-none-eabi
targetPrefix   = 'arm-none-eabi-' (empty == native build)

== variables exported by the setup hooks ==
CC    = arm-none-eabi-gcc
CXX   = arm-none-eabi-g++
AR    = arm-none-eabi-ar
AS    = arm-none-eabi-as
LD    = arm-none-eabi-ld
...

== flags injected by the cc-wrapper ==
--- cc-cflags
-B…/arm-none-eabi-gcc-16.2.0-lib/arm-none-eabi/lib
--- libc-cflags
-idirafter …/newlib-arm-none-eabi…/arm-none-eabi/include -idirafter …/gcc…/include-fixed
--- libc-crt1-cflags
-B…/newlib-arm-none-eabi…/arm-none-eabi/lib

== the wrapper script and the real compiler ==
wrapper: …/arm-none-eabi-gcc-wrapper-16.2.0/bin/arm-none-eabi-gcc
execs:   …/arm-none-eabi-gcc-16.2.0/bin/arm-none-eabi-gcc
```


The same mechanism applies to the TCC example: its `$CC` executes TCC, and
since `libc = null` the `libc-*` flag files are empty.


## Replacing the compiler (worked example: TCC)

TCC is not in nixpkgs, so `flake.nix` builds it from its own source
(`tccSrc`/`tcc`), then wires it in:

```nix
# 1. nixpkgs' wrapper recognises compilers by executable name in $out/bin.
#    TCC's driver is called `tcc`, so expose it as `gcc`.
tccAsGcc = nativePkgs.runCommand "tcc-as-gcc" { } ''
  mkdir -p $out/bin
  ln -s ${tcc}/bin/tcc $out/bin/gcc
'';

# 2. choose binutils (see next section) — TCC needs ar/ld only
tccBintools = nativePkgs.wrapBintoolsWith {
  bintools = nativePkgs.binutils-unwrapped;
  libc = null;
};

# 3. wrap driver + binutils + libc into a `cc`
tccCC = nativePkgs.wrapCCWith {
  cc = tccAsGcc;
  bintools = tccBintools;
  libc = null;
};

# 4. make it the stdenv's compiler
tccStdenv = nativePkgs.stdenv.override {
  cc = tccCC;
  hasCC = true;
  allowedRequisites = null;
};
```

Result: `nix build .#tcc-demo` compiles `libadd` with **tcc 0.9.28rc** and
produces `ELF 64-bit LSB relocatable, x86-64`.

### Where is `CC` defined in the TCC example?

`CC` is not set by the flake, and not set by the TCC package. It is written
into the wrapper that `wrapCCWith` builds around TCC. Inspect it:

```sh
$ W=$(nix eval --raw .#env.tccCC)

$ ls -l "$W/bin/cc" "$W/bin/gcc"
.../bin/cc -> gcc
-r-xr-xr-x ... .../bin/gcc

$ cat "$W/nix-support/orig-cc"
/nix/store/...-tcc-as-gcc

$ grep '^export CC' "$W/nix-support/setup-hook"
export CC${role_post}=gcc

$ grep exec "$W/bin/gcc"
    exec /nix/store/...-tcc-as-gcc/bin/gcc \
```

Step by step, with the nixpkgs source:

1. `tccAsGcc` provides a driver named `gcc` (`$out/bin/gcc` → tcc).
2. When the wrapper is built, its installPhase
   (`pkgs/build-support/cc-wrapper/default.nix`) runs
   `export named_cc=${targetPrefix}cc`, then looks for a driver called
   `gcc`/`clang`/`arocc`. Ours is found, so it runs `wrap gcc …`,
   `ln -s gcc $out/bin/cc`, and sets `named_cc=gcc`. (`targetPrefix` is empty
   because host == build platform in this example.)
3. `setup-hook.sh` (`pkgs/build-support/cc-wrapper/setup-hook.sh`) contains
   `export CC${role_post}=@named_cc@`. It is processed with `substituteAll`
   when the wrapper is built, so `@named_cc@` becomes `gcc`.
4. `setup.sh` sources that hook in every build. `getRole` sets
   `role_post=""` for the package's own (host) role, so the exported variable
   is literally `CC=gcc`.
5. `gcc` is on `PATH` via the wrapper's `bin`, i.e. `$W/bin/gcc` — the wrapper
   script — and its last line `exec`s `$tccAsGcc/bin/gcc`, which is
   `/nix/store/...-tcc/bin/tcc`.

Counterfactual: had we left the binary named `tcc`, the installer would match
none of the `gcc`/`clang`/`arocc` branches: no `$W/bin/cc` would be created,
and `CC` would stay at its default `cc`, pointing at nothing. **The symlink is
what defines `CC`.**

The ARM target is identical except `targetPrefix = "arm-none-eabi-"`, so the
same code exports `CC=arm-none-eabi-gcc`.

Caveat for TCC: the wrapper also exports `CXX=g++`, but TCC has no C++ frontend
and `$W/bin/g++` is not created, so `$CXX` is unusable in that environment.

Notes that apply to any custom compiler:

- **Name matters, but not because the compiler must be "gcc".** The wrapper
  does not care *what* the compiler is; the filename decides what the wrapper
  installs and what `CC` is set to:

  | driver in `$cc/bin` | wrapper installs | exported | `$CC` executes |
  | --- | --- | --- | --- |
  | `gcc` | `bin/<prefix>cc -> <prefix>gcc` | `CC=<prefix>gcc` | the wrapper script (flags applied) |
  | `clang` | `bin/<prefix>cc -> <prefix>clang` | `CC=<prefix>clang` | the wrapper script (flags applied) |
  | `arocc` | `bin/<prefix>cc -> <prefix>arocc` | `CC=<prefix>arocc` | the wrapper script (flags applied) |
  | `cc` only | nothing (default `named_cc`) | `CC=<prefix>cc` | your **raw** `bin/cc` — wrapper bypassed |
  | any other name | nothing | `CC=<prefix>cc` (unresolved) | nothing / another `cc` from PATH |

  Verified by exposing TCC as `cc` instead of `gcc`: the build ran with
  `CC=cc`, and `which cc` was `/nix/store/…-tcc-as-cc/bin/cc` — the raw TCC,
  with none of the wrapper's flags. That is exactly why the example exposes
  TCC under the name `gcc`.

  So the options are:

  1. expose the driver as `gcc` (or the other name the wrapper knows) — what
     this example does;
  2. ship a `bin/cc` that is itself a wrapper (this is how nixpkgs' zig
     package does it);
  3. write your own `cc` package that provides `bin/<prefix>cc` and a
     `nix-support/setup-hook` exporting `CC`, and pass it to
     `stdenv.override { cc = …; }` — that is all `wrapCCWith` is.
- **Command line.** The wrapper passes GCC-style flags. GCC/Clang-compatible
  drivers just work; others may need an adapter, or declare the flags they
  cannot handle (the TCC example uses
  `passthru.hardeningUnsupportedFlagsByTargetPlatform`).
- **libc = null** because TCC carries its own include/library paths. Pass your
  libc package instead if the compiler expects one (see below).
- TCC only emits x86-64, so this example builds natively. For an embedded
  target use a compiler with that backend — `cc`/`binutils`/`libc` wiring is
  identical, only `hostPlatform`/`targetPlatform` change.

## Three verified ways to provide a compiler

All three are in the flake and build a working x86-64 object with TCC.

| # | package provides | `CC` | where the flags come from | package |
| --- | --- | --- | --- | --- |
| 1 | `bin/gcc` → tcc | `gcc` | nixpkgs cc-wrapper (libc paths, hardening) | `.#tcc-demo` |
| 2 | `bin/cc` (your wrapper script) | `cc` | your script; the nixpkgs wrapper script is bypassed | `.#bincc-demo` |
| 3 | `bin/cc` **+** `nix-support/setup-hook` | `cc` | whatever your hook exports (no `wrapCCWith` at all) | `.#owncc-demo` |

**1. Name the driver `gcc`** — what `.#tcc-demo` does. The wrapper installs
`bin/cc` and exports `CC=gcc`.

**2. Ship your own `bin/cc`** — `.#bincc-demo`. The cc-wrapper has no branch
for a driver called `cc`, so it installs nothing; its setup hook still exports
`CC=cc`, and because the cc package's `bin/` is on `PATH`, `$CC` resolves to
*your* script. The wrapper's flag injection is skipped, so the flags are the
ones you write. `$AR`/`$LD` still come from the wrapped binutils.

Evidence from the build log (the `-D` lives in our `bin/cc`; the `check.c`
with `#ifndef TCC_FROM_BINCC / #error` would fail to compile otherwise):

```
CC=cc
resolves to: /nix/store/…-tcc-bincc/bin/cc
```

**3. Write the cc package yourself** — `.#owncc-demo`. This is what
`wrapCCWith` produces, minus the wrapper: a package with a driver in `bin/`
and a `nix-support/setup-hook`:

```nix
tccOwnCc = nativePkgs.runCommand "tcc-own-cc" { } ''
  mkdir -p $out/bin $out/nix-support
  ln -s ${tcc}/bin/tcc $out/bin/cc
  {
    echo 'export CC=cc'
    echo 'export AR=${nativePkgs.binutils-unwrapped}/bin/ar'
    echo 'export RANLIB=${nativePkgs.binutils-unwrapped}/bin/ranlib'
    echo 'export STRIP=${nativePkgs.binutils-unwrapped}/bin/strip'
    echo 'export LD=${nativePkgs.binutils-unwrapped}/bin/ld'
  } > $out/nix-support/setup-hook
'';

stdenv = nativePkgs.stdenv.override { cc = tccOwnCc; hasCC = true; allowedRequisites = null; };
```

Evidence:

```
CC=cc
resolves to: /nix/store/…-tcc-own-cc/bin/cc
AR=/nix/store/…-binutils-2.46/bin/ar
```

**The setup hook is mandatory.** A package that only ships `bin/cc` (no
`nix-support/setup-hook`) leaves `$CC` **empty**, and the build fails:

```
CC=[]                     # verified with a bin/cc package without a hook
<no command> not on PATH
compile FAILED
```

(The wrapper is part of `defaultNativeBuildInputs`, and its `bin/` plus setup
hook are what introduce the variables — see the `CC` section above.)

## Compiler-package metadata that changes flags

Besides the wrapper's per-build flags, the *compiler package* can carry
metadata the wrapper reads. TCC uses one such field:

```nix
tccAsGcc = (nativePkgs.runCommand "tcc-as-gcc" { } ''
  mkdir -p $out/bin
  ln -s ${tcc}/bin/tcc $out/bin/gcc
'').overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    hardeningUnsupportedFlagsByTargetPlatform = _: [
      "fortify" "fortify3" "stackshadow" "stackprotector"
      "stackclashprotection" "nostrictaliasing" "pacret"
      "strictflexarrays1" "strictflexarrays3" "pic"
      "strictoverflow" "libcxxhardeningfast" "libcxxhardeningextensive"
      "glibcxxassertions" "format" "trivialautovarinit"
      "zerocallusedregs" "pie" "relro" "bindnow"
    ];
  };
});
```

The wrapper calls `cc.hardeningUnsupportedFlagsByTargetPlatform targetPlatform`
and substitutes the result into `@hardening_unsupported_flags@` of
`nix-support/add-hardening.sh`, so those flags are never passed to TCC — no
`hardeningDisable` is needed in any consumer. You can see it in the generated
wrapper:

```sh
w=$(nix eval --raw .#env.tccCC)
grep '^export CC' "$w/nix-support/setup-hook"          # export CC${role_post}=gcc
grep -A1 'Remove unsupported flags' "$w/nix-support/add-hardening.sh"
```

If a compiler needs extra flags on *every* invocation, the wrapper has an
extension point for that too:

```nix
myCC = nativePkgs.wrapCCWith {
  cc = myCompiler;
  bintools = myBintools;
  libc = myLibc;
  nixSupport = { "cc-cflags" = "-myspecialflag"; };   # written into the wrapper
};
```

(`extraBuildCommands` runs arbitrary shell while the wrapper is assembled.)

## Replacing binutils (and which ones are suitable)

Binutils must target **the same architecture and object format as the code the
compiler emits** — that is the entire suitability rule:

- **gcc** → GNU binutils for the same triple (e.g. `arm-none-eabi-binutils`).
- **tcc** → it has its own code generator/assembler, so it never calls `as`;
  it only needs `ar` (to archive) and `ld` (if it links). Any binutils that
  works for the target you emit code for is fine.
- A **mismatched** pair (x86 binutils with an ARM compiler, say) fails: the
  assembler cannot parse the emitted assembly and the linker rejects the
  object format.

Swap the whole set:

```nix
myBintools = nativePkgs.wrapBintoolsWith {
  bintools = myBinutilsPackage;   # must provide $out/bin/<prefix>{ar,as,ld,...}
  libc = myLibc;                  # or null
};

myCC = nativePkgs.wrapCCWith {
  cc = myCompiler;
  bintools = myBintools;
  libc = myLibc;
};
```

## Replacing libc

`libc` is just a package with headers and start files:

```
$out/include/   headers
$out/lib/       crt1.o, libc.a (and/or libc.so)
```

- **Keep the platform default**: `libc = targetPkgs.newlib;` (what the ARM
  target uses).
- **A different packaged libc**: change `libc` in `crossSystem`, e.g.
  `libc = "newlib-nano";` or `libc = "picolibc";`. nixpkgs then picks that
  package for the target (verified: picolibc resolves to
  `picolibc-arm-none-eabi-1.8.12-1`).
- **Your own libc**: build/get a package with the layout above and pass it to
  `wrapCCWith { libc = myLibc; ... }`.
- **Freestanding** (no libc at all): `libc = null;` — the wrapper then adds no
  libc include/library flags (this is what the TCC example uses).

## Replacing the platforms

The three platforms are ordinary elaborated descriptors, so you can write them
yourself:

```nix
buildPlatform  = nixpkgs.lib.systems.elaborate localSystem;
targetPlatform = nixpkgs.lib.systems.elaborate crossSystem;
```

- `buildPlatform` — where the build executes.
- `hostPlatform` — where the produced packages run.
- `targetPlatform` — what the produced compiler emits code for.

For a normal cross build, `hostPlatform == targetPlatform`. They differ only
for a Canadian cross (a compiler that runs on one machine, targets another).

Everything nixpkgs can parse works directly; for a machine it has no name for,
give `elaborate` an explicit `parsed` description:

```nix
targetPlatform = nixpkgs.lib.systems.elaborate {
  config = "mycpu-unknown-myos";
  parsed = { cpu = { name = "mycpu"; bits = 32; }; kernel = { name = "myos"; }; abi = { name = "eabi"; }; };
};
```

Changing `crossSystem` (its `config`, `libc`, `gcc.*`, `useLLVM`, …) recomputes
the platform *and* everything built from it — the compiler, binutils and libc
packages are keyed by those values. Using a combination nixpkgs has no prebuilt
toolchain for means Nix builds that toolchain from source the first time.

## Build

Always single core / single job:

```sh
nix build .#libadd     --cores 1 --max-jobs 1   # ARM bare metal, gcc + newlib
nix build .#libmul     --cores 1 --max-jobs 1   # ARM bare metal, depends on libadd
nix build .#tcc-demo   --cores 1 --max-jobs 1   # own compiler: driver named gcc
nix build .#bincc-demo --cores 1 --max-jobs 1   # own compiler: bin/cc wrapper
nix build .#owncc-demo --cores 1 --max-jobs 1   # own cc package + setup-hook
```

## Verify

```sh
$ nix eval .#env.cc.name                 # arm-none-eabi-gcc-wrapper-...
$ nix eval .#env.binutils.name           # arm-none-eabi-binutils-wrapper-...
$ nix eval .#env.libc.name               # newlib-arm-none-eabi-...
$ nix eval .#env.targetPlatform.config   # arm-none-eabi
$ nix eval .#env.buildPlatform.system    # x86_64-linux

$ file .../libadd-arm-none-eabi-0.1.0/lib/libadd.a
ELF 32-bit LSB relocatable, ARM, EABI5
$ file .../libadd-built-with-tcc-0.1.0/lib/libadd.a
ELF 64-bit LSB relocatable, x86-64
```
