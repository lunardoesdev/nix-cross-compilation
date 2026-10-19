/* Minimal semihosting: talk to the debugger/emulator (QEMU) over the
 * "bkpt 0xAB" interface.  No libc needed. */
#ifndef SEMIHOSTING_H
#define SEMIHOSTING_H

/* ARM semihosting operation numbers we use. */
#define SYS_WRITE0 0x04   /* write a NUL-terminated string (arg = pointer) */
#define SYS_EXIT   0x18   /* stop the target (arg = reason)                */

void semi_write0(const char *s);
void semi_exit(int code);

#endif /* SEMIHOSTING_H */
