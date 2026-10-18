#include "mul.h"

int multiply(int a, int b) {
    int result = 0;
    for (int i = 0; i < b; i++)
        result = add(result, a);
    return result;
}
