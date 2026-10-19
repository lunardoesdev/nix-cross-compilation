/*
 * Startup code for a Cortex-M target.
 *
 * On reset the CPU loads the initial stack pointer from the first word of the
 * vector table and jumps to the second word (the reset handler).  We copy
 * .data from flash to RAM, zero .bss, call main(), and stop.
 */
#include <stdint.h>

extern uint32_t _sidata;   /* .data load address (in flash)   */
extern uint32_t _sdata;    /* .data start (in RAM)            */
extern uint32_t _edata;    /* .data end                       */
extern uint32_t _sbss;     /* .bss start                      */
extern uint32_t _ebss;     /* .bss end                        */
extern uint32_t _estack;   /* top of RAM                      */

int main(void);

void Reset_Handler(void)
{
    uint32_t *src = &_sidata;
    uint32_t *dst = &_sdata;
    while (dst < &_edata)
        *dst++ = *src++;

    for (dst = &_sbss; dst < &_ebss; )
        *dst++ = 0;

    main();

    for (;;)
        ;   /* main() is not expected to return */
}

void Default_Handler(void)
{
    for (;;)
        ;
}

/* The vector table lives in its own section so the linker script can keep it
 * first in flash.  The first entry is the initial stack pointer. */
__attribute__((section(".vectors"), used))
void (*const vectors[])(void) = {
    (void (*)(void))(&_estack),
    Reset_Handler,
    Default_Handler,   /* NMI      */
    Default_Handler,   /* HardFault */
};
