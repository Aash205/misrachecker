/* Same violation pattern as dummy_driver.c, on purpose. This file lives
 * under generated/ and MUST produce ZERO lint findings -- proves
 * exclude-paths.txt actually works. */
#include <stdint.h>

int32_t dummy_generated_init(int32_t flag)
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
