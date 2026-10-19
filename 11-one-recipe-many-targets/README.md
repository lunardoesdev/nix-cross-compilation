[« Previous: 10 — Compiler metadata that changes flags](../10-compiler-metadata-and-flags/README.md) · [Index](../README.md) · [Next: 12 — Two libraries that depend on each other »](../12-two-libraries-depending-on-each-other/README.md)

# 11 — One recipe, many targets

> **Goal.** Stop writing one flake per platform. Learn the two ideas that make
> multi-platform builds manageable: a **target table** (one nixpkgs package set
> per platform) and a **generic builder** (one recipe instantiated per target).

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The target table

Each platform is a *complete nixpkgs package set* whose `stdenv` targets that
platform:

```nix
targets = {
  linux   = pkgs;                    # native x86_64 (glibc)
  windows = pkgs.pkgsCross.mingwW64; # Windows x86_64 via mingw-w64
};
```

That is the whole cross-compilation story. A package written once can be
instantiated through the package set of the platform we want, and Nix resolves
the compiler, libc and every dependency from that set. **Adding a platform is one
line** — chapters 14–17 add Android and Emscripten exactly this way.

## 2. The generic builder

```nix
mkLib = target: { pname, src, sources, headers ? [], libName, deps ? [], linkLibs ? [] }:
  target.callPackage ({ lib, stdenv }: stdenv.mkDerivation {
    inherit pname src;
    buildInputs = deps;
    dontConfigure = true;
    enableParallelBuilding = false;      # the single-core rule
    buildPhase = ''
      for f in ${lib.concatStringsSep " " sources}; do
        $CC -O2 -fPIC -Wall -Wextra ${includeFlags} -c "$f" -o "obj/…"
      done
      $AR rcs "lib${libName}.a" obj/*.o
    '';
    installPhase = '' … cp lib${libName}.a + headers into $out … '';
  }) { };
```

Two things make it generic:

* **`target.callPackage`** resolves `lib` and `stdenv` from the target package
  set and passes them in; everything else is closed over.
* **`$CC`/`$AR`** are whatever that target's stdenv provides — gcc for Linux,
  `x86_64-w64-mingw32-gcc` for Windows — with no `if windows` in the recipe.

## 3. Instantiate it per target

```nix
mkFor = name: target: {
  "${name}-libadd" = mkLib target {
    pname = "libadd"; src = ./src;
    sources = [ "add.c" ]; headers = [ "add.h" ]; libName = "add";
  };
};

packages = mkFor "linux" targets.linux // mkFor "windows" targets.windows;
```

The same `add.c` is compiled twice, by two different toolchains, with no
conditional code.

## 4. Run it

```sh
nix build .#linux-libadd   --max-jobs 1 --cores 1
nix build .#windows-libadd --max-jobs 1 --cores 1
```

## 5. Verify

The archives contain objects in each platform's format:

```sh
$ ar x "$(nix build --no-link --print-out-paths .#linux-libadd)/lib/libadd.a" && file add.o
add.o: ELF 64-bit LSB relocatable, x86-64, version 1 (SYSV), not stripped

$ ar x "$(nix build --no-link --print-out-paths .#windows-libadd)/lib/libadd.a" && file add.o
add.o: x86-64 COFF object file, no line number info, not stripped, 6 sections, …
```

`ELF` for Linux, `COFF` for Windows — the same source, two toolchains, no
special-casing.

## 6. Pitfalls

* **Platform conditionals leak in.** If you find yourself writing
  `if isWindows then …` for *toolchain* reasons (not output-format reasons), you
  have probably bypassed the target package set.
* **Using `pkgs.stdenv.mkDerivation` instead of `target.callPackage`.** You lose
  the target toolchain and build native objects.
* **Forgetting `enableParallelBuilding = false`.** The rule applies to generated
  recipes too.
* **`callPackage` argument shadowing.** The lambda `{ lib, stdenv }:` receives
  those two from the target set; do not also define them in the outer scope.

## 7. What's next

One library is easy. [Chapter 12](../12-two-libraries-depending-on-each-other/README.md)
adds the second one — `libmul`, which depends on `libadd` — and shows how the
dependency is passed on every platform, including shared-library naming for ELF
and Windows.

---

[« Previous: 10 — Compiler metadata that changes flags](../10-compiler-metadata-and-flags/README.md) · [Index](../README.md) · [Next: 12 — Two libraries that depend on each other »](../12-two-libraries-depending-on-each-other/README.md)
