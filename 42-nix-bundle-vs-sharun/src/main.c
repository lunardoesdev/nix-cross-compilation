#include <stdio.h>

#include "add.h"
#include "mul.h"

int main(void)
{
    printf("uselib2: add(6, 7) = %d\n", add(6, 7));
    printf("uselib2: mul(6, 7) = %d\n", mul(6, 7));
    return mul(6, 7) == 42 ? 0 : 1;
}
