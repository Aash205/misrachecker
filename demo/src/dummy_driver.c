/* Deliberately violates MISRA C:2012 Rule 15.1 (no goto) to prove the
 * lint pipeline actually catches real violations. */
#include <stdint.h>

int32_t dummy_driver_init(int32_t flag)
{
    int32_t result = 0;

    if (flag == 0)
    {
        goto fail;
    }

    result = 1;
    return result;

fail:
    return -1;
}
