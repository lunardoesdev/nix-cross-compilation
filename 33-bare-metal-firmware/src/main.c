#include "semihosting.h"
#include "add.h"
#include "mul.h"

int main(void)
{
    /* Uses libmul, which uses libadd -- the same dependency chain as everywhere
     * else, now running on a bare-metal Cortex-M with no operating system. */
    int score = mul(6, 7);

    semi_write0("firmware: bare-metal ARM (arm-none-eabi, freestanding)\n");

    if (score == 42)
        semi_write0("firmware: mul(6, 7) = 42  (ok)\n");
    else
        semi_write0("firmware: mul(6, 7) != 42 (FAIL)\n");

    semi_exit(score == 42 ? 0 : 1);
    return 0;
}
