#include <stdio.h>

#include "add.h"

int main(void)
{
    int result = add(6, 7);
    printf("add(6, 7) = %d\n", result);
    return result == 13 ? 0 : 1;
}
