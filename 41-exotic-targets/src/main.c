/*
 * A minimal UEFI application built with gnu-efi.
 *
 * UEFI is a freestanding environment: no libc, no standard startup.  gnu-efi
 * supplies the entry point (crt0-efi-x86_64.o) and the boot-services wrappers
 * (`InitializeLib`, `Print`).
 */
#include <efi.h>
#include <efilib.h>

#include "mul.h"

EFI_STATUS efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    InitializeLib(image, systab);

    Print(L"uefi-demo: hello from a Nix-built UEFI application\n");
    Print(L"uefi-demo: mul(6, 7) = %d\n", mul(6, 7));

    return EFI_SUCCESS;
}
