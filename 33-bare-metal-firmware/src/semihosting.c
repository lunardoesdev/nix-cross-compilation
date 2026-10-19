#include "semihosting.h"

/* The ARM semihosting call: op in r0, argument in r1, result in r0, triggered
 * by `bkpt 0xAB`.  QEMU traps it and performs the I/O. */
static int semi_call(int op, void *arg)
{
    register int r0 __asm__("r0") = op;
    register void *r1 __asm__("r1") = arg;
    __asm__ volatile ("bkpt 0xAB" : "+r"(r0) : "r"(r1) : "memory");
    return r0;
}

void semi_write0(const char *s)
{
    semi_call(SYS_WRITE0, (void *)s);
}

void semi_exit(int code)
{
    /* 0x20026 == ADP_Stopped_ApplicationExit, 0x20023 == RunTimeError */
    semi_call(SYS_EXIT, (void *)(code == 0 ? 0x20026 : 0x20023));
}
