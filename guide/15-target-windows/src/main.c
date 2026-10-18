#include <stdio.h>

#include "add.h"
#include "mul.h"

/*
 * A console program that depends on BOTH libraries.  libmul already depends on
 * libadd, so `mul()` pulls `add()` in transitively -- but we call `add()`
 * directly too, so we name both libraries.
 */
int main(void)
{
    int a = 6;
    int b = 7;

    printf("uselib2: add(%d, %d) = %d\n", a, b, add(a, b));
    printf("uselib2: mul(%d, %d) = %d\n", a, b, mul(a, b));

    return mul(a, b) == 42 ? 0 : 1;
}
