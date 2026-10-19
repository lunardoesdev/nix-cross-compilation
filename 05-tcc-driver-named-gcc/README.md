[« Previous: 04 — Building TCC from source](../04-tcc-from-source/README.md) · [Index](../README.md) · [Next: 06 — Variant 2: ship your own `bin/cc` »](../06-tcc-own-bin-cc/README.md)

# 05 — Variant 1: name the driver `gcc`

> **Goal.** Make TCC the stdenv's compiler by *renaming its driver* so nixpkgs'
> own cc-wrapper accepts it. This is the least code and the most "normal"
> approach: you keep all of the wrapper's machinery and only supply the compiler.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The idea

From chapter 03: the cc-wrapper recognizes a compiler by the **filename** of the
driver it finds in the `cc` package's `$out/bin`. It knows `gcc`, `clang` and
`arocc`. TCC's driver is called `tcc`, which the wrapper does not recognize, so
we expose it under the name `gcc`:

```nix
tccAsGcc = pkgs.runCommand "tcc-as-gcc" { } ''
  mkdir -p $out/bin
  ln -s ${tcc}/bin/tcc $out/bin/gcc

  # (see the pitfalls: this line matters)
  ln -s ${tcc}/lib/tcc $out/lib
'';
```

That symlink is the entire "adapter". The wrapper then:

* creates `$out/bin/cc -> gcc`,
* sets `named_cc=gcc`,
* writes `export CC=…gcc` into `nix-support/setup-hook`,
* and wraps every invocation with the flags from chapter 03.

## 2. The wrapper and the stdenv

```nix
tccBintools = pkgs.wrapBintoolsWith {
  bintools = pkgs.binutils-unwrapped;   # TCC only needs ar/ld
  libc = null;
};

tccCC = pkgs.wrapCCWith {
  cc = tccAsGcc;        # the driver (named gcc)
  bintools = tccBintools;
  libc = null;          # TCC carries its own include/library paths
};

tccStdenv = pkgs.stdenv.override {
  cc = tccCC;
  hasCC = true;
  allowedRequisites = null;
};
```

`libc = null` is deliberate: TCC was configured with its own search paths in
chapter 04, and the `-idirafter`/`-B` flags the wrapper would add for glibc are
both unnecessary and harmful.

## 3. Telling the wrapper which hardening flags TCC cannot take

The wrapper translates `NIX_HARDENING_ENABLE` into flags like
`-fstack-clash-protection`. TCC understands none of them. Instead of disabling
hardening in every consumer, attach the information to the **compiler package**
as `passthru` metadata:

```nix
tccAsGcc = (pkgs.runCommand "tcc-as-gcc" { } '' … '').overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    hardeningUnsupportedFlagsByTargetPlatform = _: [
      "fortify" "fortify3" "shadowstack" "stackprotector"
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
and substitutes the result into `nix-support/add-hardening.sh`, so exactly those
flags are filtered out for every consumer. Chapter 10 goes deeper.

## 4. Build something with it

The build script never mentions TCC:

```nix
hello = tccStdenv.mkDerivation {
  pname = "tcc-hello-wrapped";
  src = ./src;
  dontConfigure = true;
  enableParallelBuilding = false;
  buildPhase = ''
    $CC main.c add.c -o hello
  '';
  installPhase = ''mkdir -p $out/bin; cp hello $out/bin/'';
  doCheck = true;
  checkPhase = ''
    output="$(./hello)"; echo "$output"
    echo "$output" | grep -q 'add(6, 7) = 13'
  '';
};
```

## 5. Run it

```sh
nix build .#hello --max-jobs 1 --cores 1
./result/bin/hello
# add(6, 7) = 13
```

## 6. Verify

Prove that `CC` is the wrapper and that the wrapper execs TCC:

```sh
$ w=$(nix eval --raw .#env.tccCC)
$ grep 'export CC' "$w/nix-support/setup-hook"
190:export CC${role_post}=gcc

$ "$w/bin/gcc" --version
tcc version 0.9.28rc (x86_64 Linux)
```

And the produced program is a normal dynamically-linked x86-64 ELF whose
interpreter is the nixpkgs glibc loader (thanks to `--elfinterp` in chapter 04).

## 7. Pitfalls

* **`error: include file 'stddef.h' not found`.** This is the trap of this
  variant. The cc-wrapper *always* injects `-B${cc}/lib`, because for gcc that is
  where libgcc and crt files live. But TCC reads `-Bdir` as **"my private dir"**
  and replaces its include search with `dir/include`. With a bare `gcc` symlink
  the injected `-B` therefore points at an empty directory and TCC loses its own
  headers. The fix is the second symlink in section 1: make `$out/lib` point at
  TCC's real private dir (`$out/lib/tcc` from chapter 04), which contains both
  `include/` and `libtcc1.a`.
* **Hardening flags.** Without the `passthru` list, TCC fails on
  `-fstack-clash-protection` and friends.
* **`$CXX` is unusable.** The wrapper exports `CXX=g++`, but TCC has no C++
  frontend and `$out/bin/g++` is never created. A C++ build would fail — with a
  confusing "g++: command not found", not a clear error.
* **No `-idirafter` for glibc.** Keeping `libc = null` avoids the wrapper adding
  flags TCC misframes. If you *want* a libc here, you must also teach TCC about
  it (chapter 09).

## 8. What's next

Naming the driver `gcc` reuses the wrapper — convenient, but it also drags in
`-B` and `-fno-omit-frame-pointer` and expects a GCC-compatible driver. If you
would rather control the flags yourself, [chapter 06](../06-tcc-own-bin-cc/README.md)
shows how to **bypass the wrapper entirely** with your own `bin/cc`.

---

[« Previous: 04 — Building TCC from source](../04-tcc-from-source/README.md) · [Index](../README.md) · [Next: 06 — Variant 2: ship your own `bin/cc` »](../06-tcc-own-bin-cc/README.md)
