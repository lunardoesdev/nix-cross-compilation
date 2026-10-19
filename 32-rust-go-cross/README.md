[« Previous: 31 — Cross-compiling with build systems](../31-cross-build-systems/README.md) · [Index](../README.md) · [Next: 33 — A bare-metal firmware image »](../33-bare-metal-firmware/README.md)

# 32 — Cross-compiling Rust and Go

> **Goal.** Cross-compile a **Rust** crate (to musl and to Windows) and a **Go**
> program (to Windows and to Linux/arm64) with Nix — and see how different the two
> languages' cross stories are.

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. Rust: a target `rustPlatform`

nixpkgs gives you a whole Rust toolchain *per target*. The toolchain is even
named after the triple:

```sh
$ nix eval --raw .#… # e.g. pkgsCross.musl64.rustPlatform.rust.cargo.name
x86_64-unknown-linux-musl-cargo-1.98.1
```

So cross-compiling is just "build the crate with that platform":

```nix
mkRust = targetPkgs: targetPkgs.rustPlatform.buildRustPackage {
  pname = "rusthello";
  version = "0.1.0";
  src = ./src/rusthello;
  cargoLock.lockFile = ./src/rusthello/Cargo.lock;
};

rust-musl    = mkRust pkgs.pkgsCross.musl64;    # x86_64-linux-musl
rust-windows = mkRust pkgs.pkgsCross.mingwW64;  # x86_64-windows
```

No `--target`, no `RUSTFLAGS`, no linker flags: the platform implies all of it.

## 2. Go: one toolchain, `GOOS`/`GOARCH`

Go is the opposite: a single native `go` can already emit code for every
`GOOS`/`GOARCH`. For pure Go you need **no cross toolchain at all**:

```nix
mkGo = { goos, goarch }: pkgs.buildGoModule {
  pname = "gohello";
  src = ./src/gohello;
  vendorHash = null;              # no dependencies
  preBuild = ''
    export GOOS=${goos}
    export GOARCH=${goarch}
    export CGO_ENABLED=0          # pure Go, no C toolchain
  '';
};

go-windows     = mkGo { goos = "windows"; goarch = "amd64"; };
go-linux-arm64 = mkGo { goos = "linux";   goarch = "arm64"; };
```

> **Gotcha.** nixpkgs' Go builder sets `GOOS`/`GOARCH` *from the platform*, so
> putting them in the derivation's `env` has no effect — the build is native.
> They must be exported in `preBuild` (or you must use
> `pkgsCross.<target>.buildGoModule`). This is exactly the kind of thing that
> "compiles fine, runs on the wrong CPU".

## 3. Run it

```sh
nix build .#rust-musl       --max-jobs 1 --cores 1   # ELF x86-64, musl
nix build .#rust-windows    --max-jobs 1 --cores 1   # PE32+ x86-64
nix build .#go-windows      --max-jobs 1 --cores 1   # PE32+ x86-64
nix build .#go-linux-arm64  --max-jobs 1 --cores 1   # ELF aarch64, static
```

## 4. Verify

```sh
$ file …/rust-musl/bin/rusthello
…: ELF 64-bit LSB pie executable, x86-64, … (musl)
$ file …/rust-windows/bin/rusthello.exe
…: PE32+ executable for MS Windows (console), x86-64
$ file …/go-windows/bin/gohello.exe
…: PE32+ executable for MS Windows (console), x86-64
$ file …/go-linux-arm64/bin/gohello
…: ELF 64-bit LSB executable, ARM aarch64, statically linked
```

The Go binaries are **statically linked** (pure Go, `CGO_ENABLED=0`), which is
why Go is often the easiest language for "runs anywhere" distribution.

## 5. Rust vs Go vs C

| | cross toolchain needed? | how |
|---|---|---|
| **C/C++** (ch. 31) | yes (`pkgsCross.*`) | cross file / toolchain file / `--host` |
| **Rust** | yes (`pkgsCross.*.rustPlatform`) | pick the platform's `rustPlatform` |
| **Go** (pure) | **no** | `GOOS`/`GOARCH` on the native toolchain |

## 6. Pitfalls

* **Go `env` instead of `preBuild`.** Silently produces a *native* binary
  (section 2).
* **`CGO_ENABLED=1` with no cross C toolchain.** Pure-Go cross builds must keep
  it `0`; if you need cgo, use `pkgsCross.<target>.buildGoModule` so the C
  compiler matches.
* **Rust without a lock file.** `buildRustPackage` needs `Cargo.lock` (here via
  `cargoLock.lockFile`).
* **Assuming Rust needs a target flag.** It does not — the platform's
  `rustPlatform` already is the target.
* **Running the result.** As in chapter 31, a Windows/arm64 binary cannot run on
  the build machine.

## 7. What's next

[Chapter 33](../33-bare-metal-firmware/README.md) returns to C and produces an
actual **bare-metal firmware image** (linker script, startup code, `.elf`/`.bin`)
instead of a library archive.

---

[« Previous: 31 — Cross-compiling with build systems](../31-cross-build-systems/README.md) · [Index](../README.md) · [Next: 33 — A bare-metal firmware image »](../33-bare-metal-firmware/README.md)
