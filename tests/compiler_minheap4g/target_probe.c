#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
extern size_t CJ_MCC_GetMaxHeapSize(void);
int CJCJ_CheckActualHeap(void)
{
    size_t actual = CJ_MCC_GetMaxHeapSize();
    const char* expected = getenv("CJCJ_TEST_HEAP_BYTES");
    const char* original = getenv("CJCJ_TEST_HEAP_ENV");
    const char* hard = getenv("cjHeapSize");
    int restored = original && !strcmp(original, hard ? hard : "<unset>");
    printf("TARGET_HEAP_ACTUAL bytes=%zu env=%s restored=%d\n", actual, hard ? hard : "<unset>", restored);
    return expected && actual == strtoull(expected, NULL, 10) && restored ? 0 : 4;
}
