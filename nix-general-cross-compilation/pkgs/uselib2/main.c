#include <stdio.h>

#include "add.h"
#include "mul.h"

int main(void)
{
    int a = 6;
    int b = 7;

    printf("uselib2: add(%d, %d) = %d\n", a, b, add(a, b));
    printf("uselib2: mul(%d, %d) = %d\n", a, b, mul(a, b));

    return 0;
}
