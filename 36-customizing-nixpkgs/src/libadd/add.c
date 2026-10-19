#include "add.h"

int add(int a, int b)
{
    return a + b;
}

#ifdef LIBADD_EXTRA
/* Only present when the package is built with -DLIBADD_EXTRA. */
int add_extra(void)
{
    return 1;
}
#endif
