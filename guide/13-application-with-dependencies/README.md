[« Previous: 12 — Two libraries that depend on each other](../12-two-libraries-depending-on-each-other/README.md) · [Index](../README.md) · [Next: 14 — Target: Linux x86_64 »](../14-target-linux/README.md)

# 13 — An application with dependencies

> **Goal.** Build an **application** that links both libraries, for every
> platform, and run it wherever it can run. This is the last piece before the
> per-target deep dives.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The program

`uselib2` calls both `add()` and `mul()` and prints the results:

```c
int main(void)
{
    printf("uselib2: add(%d, %d) = %d\n", a, b, add(a, b));
    printf("uselib2: mul(%d, %d) = %d\n", a, b, mul(a, b));
    return mul(a, b) == 42 ? 0 : 1;
}
```

It depends on `libmul` (which depends on `libadd`), so it exercises the whole
chain.

## 2. The application builder

```nix
mkApp = target: { pname, src, sources ? [ "main.c" ], binName ? pname
                , deps ? [], linkLibs ? [], checkCommand ? "" }:
  target.callPackage ({ lib, stdenv }:
    let
      isWindows = stdenv.hostPlatform.isWindows;
      exeExt = if isWindows then ".exe" else "";
      includeFlags = lib.concatMapStringsSep " " (d: "-I${d}/include") deps;
      libraryFlags = lib.concatMapStringsSep " " (d: "-L${d}/lib") deps;
      linkFlags = lib.concatMapStringsSep " " (l: "-l${l}") linkLibs;
      canRun = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
    in
    stdenv.mkDerivation {
      buildInputs = deps;
      enableParallelBuilding = false;
      buildPhase = ''
        $CC -O2 -Wall -Wextra ${includeFlags} ${sources} \
          -o "${binName}${exeExt}" ${libraryFlags} ${linkFlags}
      '';
      doCheck = canRun && checkCommand != "";
      checkPhase = …;   # runs ./uselib2 and greps the output
    }) { };
```

Two details:

* **`exeExt`** — Windows executables end in `.exe`; nothing else changes.
* **`canRun`** — `stdenv.buildPlatform.canExecute stdenv.hostPlatform` is true
  only when the build machine can run the produced binary. So the run-time
  `checkPhase` is enabled for Linux and silently skipped for Windows/Android.

## 3. Instantiate it

```nix
uselib2 = mkApp target {
  pname = "uselib2"; src = ./src; sources = [ "main.c" ];
  deps = [ libmul libadd ];
  linkLibs = [ "mul" "add" ];      # order matters for static archives
  checkCommand = ''… grep -q 'mul(6, 7) = 42' …'';
};
```

`deps` gives the headers; `linkLibs` gives the link order. `-lmul` must come
before `-ladd`, because `libmul.a` references `add`.

## 4. Run it

```sh
nix build .#linux-uselib2   --max-jobs 1 --cores 1
./result/bin/uselib2
# uselib2: add(6, 7) = 13
# uselib2: mul(6, 7) = 42
```

```sh
nix build .#windows-uselib2 --max-jobs 1 --cores 1
ls "$(nix build --no-link --print-out-paths .#windows-uselib2)/bin"
# libadd.dll  libmul.dll  uselib2.exe
```

## 5. Verify

The Linux build runs the program during `checkPhase`, so a broken dependency
fails the build:

```
checkPhase: uselib2: add(6, 7) = 13
            uselib2: mul(6, 7) = 42
```

The Windows build cannot run here, but Nix has linked the required DLLs **next
to the `.exe`**, so the `bin/` directory is self-contained:

```sh
$ file …/bin/uselib2.exe
…/bin/uselib2.exe: PE32+ executable (console) x86-64, for MS Windows
```

## 6. Pitfalls

* **Link order.** `-ladd -lmul` fails with `undefined reference to 'mul'` (or to
  `add` when linking statically). Dependencies first, dependents last.
* **Missing DLLs.** A PE executable is not self-contained; the `*.dll` files
  must travel with it. Nix arranges that inside `bin/`, but if you copy only the
  `.exe` you break it.
* **Running a cross binary in `checkPhase`.** Guard the run with
  `buildPlatform.canExecute hostPlatform`, or the check fails on a platform the
  build machine cannot execute.
* **`.exe` suffix.** Forget it on Windows and the binary is still built, but
  Windows will not run it as an executable.

## 7. What's next

Part 3 built the same code for several platforms through one recipe. Part 4 takes
each of the four headline targets in turn and explains its specific gotchas,
starting with [Linux](../14-target-linux/README.md).

---

[« Previous: 12 — Two libraries that depend on each other](../12-two-libraries-depending-on-each-other/README.md) · [Index](../README.md) · [Next: 14 — Target: Linux x86_64 »](../14-target-linux/README.md)
