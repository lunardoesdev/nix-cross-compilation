[« Previous: 32 — Rust and Go](../32-rust-go-cross/README.md) · [Index](../README.md) · [Next: 34 — Packaging an Android APK »](../34-android-apk/README.md)

# 33 — A bare-metal firmware image

> **Goal.** Stop producing *archives* and produce an actual **bootable firmware
> image**: a linker script, startup code, and `firmware.elf` / `.bin` / `.hex`
> that runs on a Cortex-M3 under QEMU — with no operating system and no C library.

Chapter [02](../02-first-cross-flake/README.md) built `libadd`/`libmul` as static
archives for `arm-none-eabi`. This chapter uses them to build a real image.

The complete flake is in [`flake.nix`](flake.nix); sources in [`src/`](src).

---

## 1. The missing pieces for a real image

A static archive is not runnable. To boot, you need three more things:

| piece | file | job |
|---|---|---|
| **startup code** | `startup.c` | the vector table (initial SP + reset vector), copy `.data`, zero `.bss`, call `main` |
| **linker script** | `linker.ld` | where flash/RAM are, which section goes where, where the stack starts |
| **entry/exit** | `semihosting.c` | output and clean shutdown under the emulator |

## 2. The toolchain (and a cost warning)

```nix
crossSystem = { config = "arm-none-eabi"; libc = "newlib"; };
```

We keep the **cached** newlib toolchain and link the firmware with `-nostdlib`,
so the image is freestanding regardless. (`libc = null` would ask Nix to build a
freestanding gcc **from source** — the cost warning from
[chapter 09](../09-replacing-libc/README.md). We hit exactly that while writing
this chapter; it is not worth it just to drop newlib from the *toolchain* when
`-nostdlib` already drops it from the *image*.)

## 3. The vector table

On reset the CPU does not "call a function" — it reads **word 0** of flash as the
initial stack pointer and **word 1** as the reset handler:

```c
__attribute__((section(".vectors"), used))
void (*const vectors[])(void) = {
    (void (*)(void))(&_estack),   /* word 0: initial SP */
    Reset_Handler,                /* word 1: entry      */
    Default_Handler,              /* NMI                */
    Default_Handler,              /* HardFault          */
};
```

`Reset_Handler` copies `.data` from its flash load address to RAM, zeroes `.bss`,
and calls `main`. This is the part that `-nostdlib` means you must write yourself.

## 4. The linker script

```ld
ENTRY(Reset_Handler)
MEMORY {
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 256K
    RAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}
SECTIONS {
    .text : { KEEP(*(.vectors)) *(.text*) *(.rodata*) } > FLASH
    .data : { _sdata = .; *(.data*) _edata = .; } > RAM AT > FLASH
    _sidata = LOADADDR(.data);
    .bss  : { _sbss = .; *(.bss*) *(COMMON) _ebss = .; } > RAM
    _estack = ORIGIN(RAM) + LENGTH(RAM);
}
```

The addresses match QEMU's `lm3s6965evb` machine (flash at `0x0`, 64 KiB RAM at
`0x20000000`). `KEEP(*(.vectors))` keeps the vector table even though nothing
references it, and forces it to the start of flash.

## 5. Semihosting instead of a UART

There is no console on a bare-metal chip. Under QEMU, **semihosting** (`bkpt
0xAB`) lets the firmware write to the host's stdout:

```c
register int r0 __asm__("r0") = op;
register void *r1 __asm__("r1") = arg;
__asm__ volatile ("bkpt 0xAB" : "+r"(r0) : "r"(r1) : "memory");
```

`SYS_WRITE0` (0x04) prints a NUL-terminated string; `SYS_EXIT` (0x18) stops the
emulator. On real hardware you would replace this with a UART driver.

## 6. Run it

```sh
nix build .#firmware --max-jobs 1 --cores 1
ls result/bin
# firmware.elf  firmware.bin  firmware.hex
```

## 7. Verify

The build runs the image under QEMU and greps the output:

```sh
$ file result/bin/firmware.elf
…: ELF 32-bit LSB executable, ARM, EABI5, statically linked

$ file result/bin/firmware.bin
…: data                       # 408 bytes: SP, reset, code, strings

$ od -A x -t x4 -N 16 result/bin/firmware.bin
000000 20010000 00000017 00000011 00000011
#      ^ SP=0x20010000 (top of RAM)  ^ reset handler (thumb address)
```

```sh
$ qemu-system-arm -M lm3s6965evb -nographic \
    -semihosting-config enable=on,target=native \
    -kernel result/bin/firmware.elf
firmware: bare-metal ARM (arm-none-eabi, freestanding)
firmware: mul(6, 7) = 42  (ok)
```

That last line is `libmul` (which uses `libadd`) executing on the emulated CPU.

## 8. Pitfalls

* **Vector table not first.** If `.vectors` is not at the start of flash, the CPU
  loads a garbage stack pointer and faults immediately.
* **`-nostdlib` without your own startup.** There is no `_start`/`crt0`; you get
  an entry point that does not initialise `.data`/`.bss`.
* **`libc = null` on a cross target.** It rebuilds gcc from source (section 2).
* **Wrong memory map.** `0x0`/`0x20000000` is the `lm3s6965evb` layout; a real
  board has its own — change `MEMORY` in `linker.ld`.
* **Forgetting `-ffreestanding`.** The compiler may emit calls to `memcpy`/`memset`
  that `-nostdlib` does not provide.
* **Semihosting on hardware.** `bkpt 0xAB` needs a debugger/emulator; it is not
  a UART.

## 9. What's next

[Chapter 34](../34-android-apk/README.md) goes the other direction: packaging the
cross-built arm64 artifacts into a real **Android APK** (and AAB), signed.

---

[« Previous: 32 — Rust and Go](../32-rust-go-cross/README.md) · [Index](../README.md) · [Next: 34 — Packaging an Android APK »](../34-android-apk/README.md)
