/* Direct real-runtime coverage of the same compiler-only init adapter. */
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
extern int CJ_ScheduleManagerInit(void);
extern void CJ_MRT_CjRuntimeInit(void);
extern void CJ_MRT_CjRuntimeFini(void);
extern size_t CJ_MCC_GetMaxHeapSize(void);
int main(int argc, char** argv)
{
    if (argc != 2) return 2;
    const char* hard = getenv("cjHeapSize");
    char* saved = hard ? strdup(hard) : NULL;
    if (CJ_ScheduleManagerInit() != 0) return 3;
    CJ_MRT_CjRuntimeInit();
    size_t actual = CJ_MCC_GetMaxHeapSize();
    hard = getenv("cjHeapSize");
    int restored = (!hard && !saved) || (hard && saved && !strcmp(hard, saved));
    printf("REAL_RUNTIME_HEAP bytes=%zu restored=%d\n", actual, restored);
    fflush(stdout);
    int rc = actual == strtoull(argv[1], NULL, 10) && restored ? 0 : 4;
    CJ_MRT_CjRuntimeFini();
    free(saved);
    return rc;
}
