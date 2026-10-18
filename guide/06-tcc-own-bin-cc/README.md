[« Previous: 05 — Variant 1: name the driver `gcc`](../05-tcc-driver-named-gcc/README.md) · [Index](../README.md) · [Next: 07 — Variant 3: write the `cc` package »](../07-tcc-hand-written-cc/README.md)

# 06 — Variant 2: ship your own `bin/cc`

> **Goal.** Make TCC the stdenv's compiler while **bypassing nixpkgs' cc-wrapper
> entirely**, so the flags are exactly the ones you choose. You keep `$AR`/`$LD`
> from the wrapped binutils but supply `$CC` yourself.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The idea

The cc-wrapper has install branches only for drivers named `gcc`, `clang` and
`arocc`. For any other name it installs **nothing** for `cc` — but its setup hook
still exports `CC=cc`, and the cc package's `bin/` is on `PATH`. So if your
package ships a `bin/cc`, then `$CC` resolves to *your* file and the wrapper
script never runs:

```nix
tccBinCc = pkgs.runCommand "tcc-bincc" { } ''
  mkdir -p $out/bin
  {
    echo '#!${pkgs.runtimeShell}'
    echo 'exec ${tcc}/bin/tcc -DTCC_FROM_BINCC=1 "$@"'
  } > $out/bin/cc
  chmod +x $out/bin/cc
'';
```

This is a real shell script that belongs to *you*. Add flags, add `-B` options,
wrap the output, log something — it is all up to you.

## 2. Wire it up

```nix
tccBintools = pkgs.wrapBintoolsWith {
  bintools = pkgs.binutils-unwrapped;
  libc = null;
};

tccBinCcCC = pkgs.wrapCCWith {
  cc = tccBinCc;        # a package whose $out/bin/cc is our script
  bintools = tccBintools;
  libc = null;
};

tccBinCcStdenv = pkgs.stdenv.override {
  cc = tccBinCcCC;
  hasCC = true;
  allowedRequisites = null;
};
```

You still call `wrapCCWith`, because that is what produces the setup hook that
sets `CC=cc`. But because the driver is named `cc`, the wrapper's flag machinery
is inert.

## 3. Prove the script was used

It would be easy to *think* your script ran when actually some other `cc` on
`PATH` did. Guard against it with a marker macro that only your script defines:

```nix
buildPhase = ''
  echo "CC=$CC"
  echo "resolves to: $(command -v "$CC")"

  printf '#ifndef TCC_FROM_BINCC\n#error "bin/cc wrapper was not used"\n#endif\nint from_bincc(void) { return TCC_FROM_BINCC; }\n' > check.c
  $CC -c check.c -o check.o

  $CC main.c add.c check.o -o hello
'';
```

If the wrapper's own (nonexistent) `cc` were used, or a different compiler, the
`#error` fires.

## 4. Run it

```sh
nix build .#binccDemo --max-jobs 1 --cores 1
./result/bin/hello
# add(6, 7) = 13
```

The build log shows which `cc` was picked up:

```
CC=cc
resolves to: /nix/store/…-tcc-bincc/bin/cc
```

## 5. Verify

```sh
$ w=$(nix eval --raw .#env.tccBinCcCC)
$ grep 'export CC' "$w/nix-support/setup-hook"
190:export CC${role_post}=cc

$ ls "$w/bin"          # only binutils, no gcc/clang/cc installed by the wrapper
addr2line ar as c++filt dwp elfedit gprof ld ld.bfd ld.gold nm objcopy objdump
ranlib readelf size strings strip
```

`CC=cc` plus "no `cc` in the wrapper's `bin`" is exactly why `$CC` resolves to our
script.

## 6. Pitfalls

* **No `bin/cc` → `CC` is empty.** A package that ships only a driver with an
  unknown name (say `bin/tcc`) and no `bin/cc` and no `nix-support/setup-hook`
  leaves `$CC` unset; the build fails with a bare "command not found". The setup
  hook is what sets the variable (chapter 03).
* **The wrapper's flags are gone.** That is the point, but it also means you no
  longer get `-fno-omit-frame-pointer`, hardening flags, or automatic
  `-isystem`/`-L` injection from dependencies through `NIX_CFLAGS_COMPILE`. If you
  need those, forward `$NIX_CFLAGS_COMPILE`/`$NIX_LDFLAGS` inside your script, or
  use variant 1.
* **Forgetting the shebang / executable bit.** The script must be executable;
  `chmod +x` it (or use `writeShellScriptBin`).
* **A different `cc` earlier on `PATH`.** Because `CC=cc` is a bare name, make
  sure your package's `bin/` is actually the one that wins — the marker macro in
  section 3 is how you check.

## 7. What's next

Variant 2 still leans on `wrapCCWith` for the setup hook. [Chapter 07](../07-tcc-hand-written-cc/README.md)
writes that package **by hand**, so you can see that `wrapCCWith` is not magic —
it is a driver in `bin/` plus a `nix-support/setup-hook`.

---

[« Previous: 05 — Variant 1: name the driver `gcc`](../05-tcc-driver-named-gcc/README.md) · [Index](../README.md) · [Next: 07 — Variant 3: write the `cc` package »](../07-tcc-hand-written-cc/README.md)
