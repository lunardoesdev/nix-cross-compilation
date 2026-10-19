[« Previous: 20 — FHS libraries, the static way](../20-fhs-libraries-static/README.md) · [Index](../README.md) · [Next: 22 — devkitPro with devkitNix »](../22-devkitpro-devkitnix/README.md)

# 21 — Extra platforms that need no LLVM build

> **Goal.** Add six more targets — and one multi-target tool — that are **cheap**:
> every toolchain is already built and cached, so nothing as large as LLVM or a
> whole gcc is compiled from source.

The complete flake is in [`flake.nix`](flake.nix).

---

## 1. The rule

Adding a target is only worth it if its toolchain is **available**, not built.
Targets whose nixpkgs support compiles a compiler from source (for example
`aarch64-android`, or switching `crossSystem.libc` on an embedded target) can
turn a one-line addition into an hours-long build. Prefer:

* a `pkgsCross.*` whose toolchain is in the binary cache, or
* a **prebuilt** SDK (like the Android NDK `-prebuilt`), or
* a tool that ships its own compiler (Zig).

Every target below satisfies that rule.

## 2. The target table

```nix
targets = {
  musl-static      = pkgs.pkgsCross.musl64;            # x86_64-linux-musl
  riscv64-linux    = pkgs.pkgsCross.riscv64;           # riscv64-linux-gnu
  avr              = pkgs.pkgsCross.avr;               # avr-none (8-bit MCUs)
  riscv64-embedded = pkgs.pkgsCross.riscv64-embedded;  # riscv64-none (bare metal)
  wasi             = pkgs.pkgsCross.wasi32;            # wasm32-wasip1
  freebsd          = pkgs.pkgsCross.x86_64-freebsd;    # x86_64-freebsd
};
```

| target | CPU / OS | object format | toolchain |
|--------|----------|---------------|-----------|
| `musl-static` | x86-64, musl libc | ELF | gcc (musl) |
| `riscv64-linux` | RISC-V 64, Linux | ELF | gcc (riscv64) |
| `avr` | Atmel AVR 8-bit, none | ELF | avr-gcc |
| `riscv64-embedded` | RISC-V 64, none | ELF | gcc (bare metal) |
| `wasi` | wasm32, WASI | WebAssembly | clang + wasi-libc |
| `freebsd` | x86-64, FreeBSD | ELF | clang + FreeBSD libc |

`musl-static` is the natural home for **fully static binaries** (chapter 20,
section 6): musl links statically without fuss.

## 3. Build the libraries

Static archives work on all six (bare-metal and WASI have no shared objects):

```sh
nix build .#musl-static-libmul      --max-jobs 1 --cores 1
nix build .#riscv64-linux-libmul    --max-jobs 1 --cores 1
nix build .#avr-libmul              --max-jobs 1 --cores 1
nix build .#riscv64-embedded-libmul --max-jobs 1 --cores 1
nix build .#wasi-libmul             --max-jobs 1 --cores 1
nix build .#freebsd-libmul          --max-jobs 1 --cores 1
```

## 4. Zig: one binary, many targets

[Zig](https://ziglang.org/) ships its compiler **prebuilt** — including its own
clang/LLVM — so using it does not build LLVM. `zig cc -target <triple>` reaches
platforms you may not have a toolchain for:

```nix
mkZig = zigTarget: pkgs.stdenv.mkDerivation {
  nativeBuildInputs = [ pkgs.zig ];
  buildPhase = ''
    zig cc -target ${zigTarget} -O2 -c add.c -o obj/add.o
    zig ar rcs libadd.a obj/add.o
  '';
};
```

```sh
nix build .#zig-linux-musl   --max-jobs 1 --cores 1   # x86_64-linux-musl
nix build .#zig-windows      --max-jobs 1 --cores 1   # x86_64-windows-gnu
nix build .#zig-macos        --max-jobs 1 --cores 1   # x86_64-macos
nix build .#zig-freestanding --max-jobs 1 --cores 1   # x86_64-freestanding
```

## 5. Verify

`file` on the objects shows six different platforms from one source file:

```sh
musl-static:       ELF 64-bit LSB relocatable, x86-64, version 1 (SYSV)
riscv64-linux:     ELF 64-bit LSB relocatable, UCB RISC-V, RVC, double-float ABI
avr:               ELF 32-bit LSB relocatable, Atmel AVR 8-bit
riscv64-embedded:  ELF 64-bit LSB relocatable, UCB RISC-V, RVC, double-float ABI
wasi:              WebAssembly (wasm) binary module version 0x1 (MVP)
freebsd:           ELF 64-bit LSB relocatable, x86-64, version 1 (FreeBSD)
```

And Zig covers yet another three formats:

```sh
zig-linux-musl:    ELF 64-bit LSB relocatable, x86-64
zig-windows:       x86-64 COFF object file
zig-macos:         Mach-O 64-bit x86_64 object
zig-freestanding:  ELF 64-bit LSB relocatable, x86-64
```

## 6. Pitfalls

* **Assuming a `pkgsCross.*` is cached.** Check with
  `nix build .#<target>-libadd --dry-run`: if it lists hundreds of derivations
  "will be built", you are about to compile a toolchain.
* **Switching libc on an embedded target.** That rebuilds gcc (chapter 09,
  section 3). Use the default or a prebuilt toolchain.
* **Shared libraries on bare metal / WASI.** There is no dynamic loader; build
  static archives (as here).
* **`zig cc` needs a writable HOME.** Set `HOME="$TMPDIR"` inside the build.
* **Zig target strings.** Use Zig's triples (`x86_64-windows-gnu`), not nixpkgs'
  (`x86_64-w64-mingw32`).

## 7. What's next

[Chapter 22](../22-devkitpro-devkitnix/README.md) goes one step further: an
*external* flake — `devkitNix` — provides ready-made Nintendo homebrew toolchains,
and we build the same two libraries with all three of them.

---

[« Previous: 20 — FHS libraries, the static way](../20-fhs-libraries-static/README.md) · [Index](../README.md) · [Next: 22 — devkitPro with devkitNix »](../22-devkitpro-devkitnix/README.md)
