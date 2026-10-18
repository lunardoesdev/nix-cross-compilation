[« Previous: 09 — Replacing libc](../09-replacing-libc/README.md) · [Index](../README.md) · [Next: 11 — One recipe, many targets »](../11-one-recipe-many-targets/README.md)

# 10 — Compiler metadata that changes flags

> **Goal.** Learn the two pieces of **metadata** a compiler package can carry
> that change which flags the cc-wrapper passes: one that *removes* flags the
> compiler cannot handle, and one that *adds* flags of your own.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. Two directions

The wrapper builds the compiler command line from several sources. A compiler
package can influence two of them without touching any consumer:

| metadata | direction | where it lands |
|----------|-----------|----------------|
| `passthru.hardeningUnsupportedFlagsByTargetPlatform` | **remove** hardening flags | `nix-support/add-hardening.sh` |
| `nixSupport = { "cc-cflags" = …; }` | **add** flags | `nix-support/cc-cflags` |

Both are properties of the *compiler*, so they apply to every build that uses it.

## 2. Removing flags: `hardeningUnsupportedFlagsByTargetPlatform`

The wrapper translates `NIX_HARDENING_ENABLE` (fortify, pic, relro, pie, ...)
into concrete flags. TCC understands none of them. Rather than disable hardening
in every derivation, advertise the unsupported set on the compiler package:

```nix
tccAsGcc = (pkgs.runCommand "tcc-as-gcc" { } ''
  mkdir -p $out/bin
  ln -s ${tcc}/bin/tcc $out/bin/gcc
  ln -s ${tcc}/lib/tcc $out/lib      # the -B trap from chapter 05
'').overrideAttrs (old: {
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
and substitutes the result into `add-hardening.sh`, so exactly those flags are
filtered out for **every** consumer. No `hardeningDisable` anywhere.

## 3. Adding flags: `nixSupport`

If a compiler needs extra flags on *every* invocation, put them in the wrapper:

```nix
tccCC = pkgs.wrapCCWith {
  cc = tccAsGcc;
  bintools = tccBintools;
  libc = null;
  nixSupport = {
    "cc-cflags" = "-DTCC_FROM_NIXSUPPORT=1";
  };
};
```

Other keys exist too: `cc-ldflags`, `cc-cflags-before`, `libc-cflags`, ...
(anything the wrapper reads from `nix-support/`).

## 4. Run it

```sh
nix build .#metadataDemo --max-jobs 1 --cores 1
./result/bin/hello
# add(6, 7) = 13
```

The build compiles a `check.c` that `#error`s unless `TCC_FROM_NIXSUPPORT` is
defined, so it fails loudly if the metadata is not applied.

## 5. Verify

```sh
$ w=$(nix eval --raw .#env.tccCC)

$ cat "$w/nix-support/cc-cflags"
-B/nix/store/…-tcc-as-gcc/lib -DTCC_FROM_NIXSUPPORT=1

$ sed -n '/Remove unsupported flags/,+1p' "$w/nix-support/add-hardening.sh"
# Remove unsupported flags.
for flag in fortify fortify3 shadowstack stackprotector stackclashprotection …; do
```

The first line shows our added flag merged with the wrapper's own `-B`; the
second shows the removal list, exactly as advertised.

## 6. Pitfalls

* **`passthru` is on the compiler package, not the derivation.** If you set
  `hardeningDisable` per-derivation instead, you must repeat it everywhere; the
  metadata approach is one place.
* **`nixSupport` values are literal.** They are written into the wrapper's flag
  files verbatim; store paths interpolate, but shell expansion does not happen.
* **Names must match.** `add-hardening.sh` unsets flags by their
  `NIX_HARDENING_ENABLE` name (`fortify`, `pic`, ...), so use those names, not the
  flag spellings (`-D_FORTIFY_SOURCE`).
* **Ordering.** `cc-cflags-before` runs before the user's own flags;
  `cc-cflags` after. If a flag must be overridable, put it in `-before`.

## 7. End of Part 2

You have now replaced **every** part of a toolchain:

| part | chapter |
|------|---------|
| the compiler | 05, 06, 07 |
| binutils | 08 |
| libc | 09 |
| the metadata that tunes flags | 10 |

Part 3 stops fiddling with toolchains and builds real, multi-platform libraries
with ordinary Nix dependency management, starting with
[chapter 11](../11-one-recipe-many-targets/README.md).

---

[« Previous: 09 — Replacing libc](../09-replacing-libc/README.md) · [Index](../README.md) · [Next: 11 — One recipe, many targets »](../11-one-recipe-many-targets/README.md)
