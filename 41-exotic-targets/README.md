[« Previous: 40 — A realistic dependency chain](../40-dependency-chain/README.md) · [Index](../README.md) · [Next: 42 — `nix bundle` vs sharun »](../42-nix-bundle-vs-sharun/README.md)

# 41 — Exotic targets: UEFI (and a kernel-module recipe)

> **Goal.** Build something that is not an ordinary Linux user-space program:
> a **UEFI application** (`.efi`), and see the recipe for an out-of-tree
> **Linux kernel module**.

The complete flake is in [`flake.nix`](flake.nix); source in [`src/main.c`](src/main.c).

---

## 1. UEFI is a freestanding target

UEFI on x86-64 uses the **System V ABI**, so the *native* gcc can compile it.
What makes it "exotic" is everything else:

* no libc, no `main`, no startup code;
* the entry point is `efi_main(EFI_HANDLE, EFI_SYSTEM_TABLE *)`;
* the output is a **PE32+** image with the EFI application subsystem.

[gnu-efi](https://sourceforge.net/projects/gnu-efi/) supplies the missing pieces:
a `crt0-efi-x86_64.o`, a linker script, and C wrappers for the boot services.

## 2. The build

```sh
CFLAGS="-I$GNU/include/efi -I$GNU/include/efi/x86_64 \
        -fPIC -fshort-wchar -ffreestanding -fno-stack-protector \
        -mno-red-zone -O2"

gcc $CFLAGS -c main.c -o main.o
# ... compile/link our libadd + libmul archives the same way ...

ld -shared -Bsymbolic -T $GNU/lib/elf_x86_64_efi.lds \
   $GNU/lib/crt0-efi-x86_64.o main.o libmul.a libadd.a \
   -L$GNU/lib -lefi -lgnuefi -o uefi-demo.so

objcopy -I elf64-x86-64 -O efi-app-x86_64 \
   -j .text -j .sdata -j .data -j .dynamic \
   -j .dynsym -j .rel -j .rela -j .reloc \
   uefi-demo.so uefi-demo.efi
```

Flags that matter:

| flag | why |
|---|---|
| `-I…/include/efi/x86_64` | the arch-specific headers (`efisetjmp_arch.h`) live in a subdir |
| `-fshort-wchar` | UEFI uses 16-bit `CHAR16` |
| `-mno-red-zone` | the firmware's interrupt handlers use the red zone |
| `-fno-stack-protector` | no libc / TLS for the stack canary |
| `-ffreestanding` | no hosted assumptions |

## 3. The app

```c
EFI_STATUS efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    InitializeLib(image, systab);
    Print(L"uefi-demo: hello from a Nix-built UEFI application\n");
    Print(L"uefi-demo: mul(6, 7) = %d\n", mul(6, 7));
    return EFI_SUCCESS;
}
```

`mul()` is our `libmul` → `libadd` chain, linked into the `.efi`.

## 4. Run it

```sh
nix build .#uefiApp --max-jobs 1 --cores 1
file result/bin/uefi-demo.efi
# …: PE32+ executable for EFI (application), x86-64
```

To actually boot it, put it on a FAT image with QEMU + OVMF:

```sh
qemu-system-x86_64 -machine q35 -m 256 \
  -drive if=pflash,format=raw,readonly=on,file=$(nix eval --raw nixpkgs#OVMF.fd)/FV/OVMF.fd \
  -drive format=raw,file=fat:rw:esp
```

(That is a separate packaging exercise; this chapter verifies the image format.)

## 5. Two real gotchas we hit

1. **The default binutils has no EFI target.** `objcopy --target=efi-app-x86_64`
   fails with `file format not recognized`. Fix: use
   `binutils-unwrapped.override { withAllTargets = true; }`.
2. **`--target` is not `-I`/`-O`.** With binutils 2.46, `--target=efi-app-x86_64`
   makes objcopy try to *read* the input as PE. Use explicit
   `-I elf64-x86-64 -O efi-app-x86_64`.

## 6. Out-of-tree Linux kernel module (recipe)

The same ideas apply, but the "crt0" is the kernel's own build system:

```nix
kernelModule = pkgs.stdenv.mkDerivation {
  pname = "hello-module";
  src = ./module;
  nativeBuildInputs = [ pkgs.kmod ];
  buildInputs = [ pkgs.linuxPackages.kernel.dev ];
  dontConfigure = true;
  buildPhase = ''
    make -C ${pkgs.linuxPackages.kernel.dev}/lib/modules/${pkgs.linuxPackages.kernel.modDirVersion}/build \
         M=$PWD modules
  '';
  installPhase = ''
    mkdir -p $out/lib/modules/${pkgs.linuxPackages.kernel.modDirVersion}/extra
    cp hello.ko $out/lib/modules/.../extra/
  '';
};
```

with a `Makefile`:

```make
obj-m += hello.o
```

and `hello.c` using `module_init` / `module_exit`.

Notes:

* modules must be built against the **exact** kernel (`vermagic`), so pin the
  same `linuxPackages`;
* building needs the kernel's generated headers/`Module.symvers`, which is why
  the `kernel.dev` output is used;
* the module is loaded with `insmod`/`modprobe` on the target, and is out of
  scope for the portable bundles (it is kernel code, not user space).

## 7. Pitfalls

* **Using the default binutils.** No EFI targets (section 5).
* **`--target` vs `-I`/`-O`.** See section 5.
* **Missing `-fshort-wchar`.** `CHAR16` strings are wrong and `Print` misbehaves.
* **Red zone.** Without `-mno-red-zone`, firmware interrupts corrupt the stack.
* **Kernel version mismatch.** A module built for another kernel is rejected
  with "invalid module format" (vermagic).
* **Expecting to run the `.efi` under Linux.** It is firmware code; use QEMU +
  OVMF or real hardware.

## 8. What's next

[Chapter 42](../42-nix-bundle-vs-sharun/README.md) compares Nix's own
**`nix bundle`** with the sharun approach used throughout Part 5.

---

[« Previous: 40 — A realistic dependency chain](../40-dependency-chain/README.md) · [Index](../README.md) · [Next: 42 — `nix bundle` vs sharun »](../42-nix-bundle-vs-sharun/README.md)
