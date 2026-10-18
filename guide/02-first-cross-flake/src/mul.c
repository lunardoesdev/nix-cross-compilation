#include "mul.h"
#include "add.h"

/*
 * mul() deliberately calls add() in a loop instead of using the `*` operator,
 * so that libmul genuinely depends on libadd.  That dependency is what the Nix
 * code has to express, and it is the same pattern used on every platform in
 * this guide.
 */
int mul(int a, int b)
{
    int result = 0;
    int i;

    for (i = 0; i < b; i++)
        result = add(result, a);

    return result;
}
