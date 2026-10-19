[« Previous: 16 — Target: Android arm64-v8a](../16-target-android/README.md) · [Index](../README.md) · [Next: 18 — Portable bundles with sharun + uruntime »](../18-fhs-portable-sharun-uruntime/README.md)

# 17 — Target: Emscripten (WebAssembly)

> **Goal.** Compile the same two libraries, and a program that uses them, to
> WebAssembly, and understand why Emscripten is used as a *tool* rather than as
> a stdenv here.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The target

```nix
emscripten = pkgs.emscripten;
emcc = "${emscripten}/bin/emcc";
emar = "${emscripten}/bin/emar";
```

| part | value |
|------|-------|
| compiler | `emcc` (clang with a wasm backend) |
| archiver | `emar` |
| libc | Emscripten's musl-derived libc (part of the SDK) |
| output | WebAssembly (`.wasm`) + JS glue + an `.html` page |
| runs on the build machine? | no (it runs in a browser) |

## 2. Why not `emscriptenStdenv`?

nixpkgs has an `emscriptenStdenv` whose `mkDerivation` runs `emconfigure`. That is
designed for **autoconf** projects. Our packages call the compiler directly, so
we keep the ordinary stdenv and pass `emcc`/`emar` explicitly. `emscripten` is
still a declared build input — this is ordinary Nix dependency management, just
without the autoconf wrapper.

Because we call `emcc` directly, the recipe cannot rely on the cc-wrapper
injecting `-I`/`-L`, which is exactly why the generic builder in
[chapter 12](../12-two-libraries-depending-on-each-other/README.md) spells those
flags out.

## 3. The libraries (static only)

```nix
buildPhase = ''
  export HOME="$TMPDIR"; export EM_CACHE="$TMPDIR/emscripten-cache"
  for f in add.c; do ${emcc} -O2 -c "$f" -o "obj/…o"; done
  ${emar} rcs "libadd.a" obj/*.o
'';
```

Emscripten output here is **static only** — there is no shared-object step.

## 4. The program → `.html` + `.js` + `.wasm`

```sh
${emcc} -O2 -I… main.c libmul.a libadd.a \
  -o uselib2.html \
  -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1
```

Asking `emcc` for an `.html` output produces all three files.

## 5. Run it

```sh
nix build .#uselib2 --max-jobs 1 --cores 1
ls result/bin
# uselib2.html  uselib2.js  uselib2.wasm
```

Serve the directory over HTTP and open the page (browsers refuse to load wasm
from `file://`):

```sh
python3 -m http.server -d result/bin
# then open http://localhost:8000/uselib2.html and watch the browser console
```

## 6. Verify

```sh
$ file result/bin/uselib2.wasm
result/bin/uselib2.wasm: WebAssembly (wasm) binary module version 0x1 (MVP)

$ ls -l result/bin
uselib2.html  uselib2.js  uselib2.wasm
```

The program prints its `uselib2: … = 42` lines to the browser's JavaScript
console (Emscripten's `printf` goes there by default).

## 7. Pitfalls

* **Using `emscriptenStdenv` with direct-compiler builds.** It forces
  `emconfigure` and breaks the build.
* **Forgetting `HOME`/`EM_CACHE`.** `emcc` wants a writable cache; without it the
  build can fail or write outside the sandbox.
* **Trying to build a shared library.** Emscripten is static-only here.
* **Opening the `.html` from `file://`.** WebAssembly needs to be fetched over
  HTTP.
* **Linking a cc-wrapper library.** `emcc` does not read the cc-wrapper's
  `-isystem`; pass `-I`/`-L` explicitly (which the builder does).

## 8. End of Part 4

You have now built the same code for Linux, Windows, Android and the web — four
object formats, four toolchains, one set of recipes. Part 5 turns to a different
problem: making the Linux build run on machines that have **no Nix at all**,
starting with [chapter 18](../18-fhs-portable-sharun-uruntime/README.md).

---

[« Previous: 16 — Target: Android arm64-v8a](../16-target-android/README.md) · [Index](../README.md) · [Next: 18 — Portable bundles with sharun + uruntime »](../18-fhs-portable-sharun-uruntime/README.md)
