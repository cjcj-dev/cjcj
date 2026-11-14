/* Test link observer: invoked after real runtime init and before runtime start.
 * It only reads the public runtime heap capacity; production links omit it. */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern size_t CJ_MCC_GetMaxHeapSize(void);
extern void __real_CJ_MRT_CjRuntimeStart(void*);
void __wrap_CJ_MRT_CjRuntimeStart(void* execute)
{
    size_t actual = CJ_MCC_GetMaxHeapSize();
    const char* expected = getenv("CJCJ_TEST_HEAP_BYTES");
    const char* hard = getenv("cjHeapSize");
    fprintf(stderr, "COMPILER_HEAP_ACTUAL bytes=%zu env=%s\n", actual, hard ? hard : "<unset>");
    fflush(stderr);
    if (!expected || actual != strtoull(expected, NULL, 10)) abort();
    __real_CJ_MRT_CjRuntimeStart(execute);
}
