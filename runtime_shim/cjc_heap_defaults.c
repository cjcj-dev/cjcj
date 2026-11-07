/* Linux compiler-only startup adapter. Linked by packages/cjc, never by utils
 * consumers. Both generated init entry points use the existing runtime V1 ABI.
 * GNU --wrap changes calls in this executable, not runtime/library definitions. */
#if defined(__linux__)
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char* name;
    const char* value;
} RuntimeConfigEntryV1;

/* Compiler policy only; the runtime default and child environment stay intact. */
#define CJC_DEFAULT_HARD "4GB"

extern int CJCJ_CompilerHeapAboveSoftDefault(const char* hard);
extern void __real_CJ_MRT_CjRuntimeInitWithConfigV1(const RuntimeConfigEntryV1*, size_t);

void __wrap_CJ_MRT_CjRuntimeInitWithConfigV1(const RuntimeConfigEntryV1* entries, size_t count)
{
    if (entries == NULL && count != 0) {
        __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
        return;
    }

    const char* envHard = getenv("cjHeapSize");
    int envSoft = getenv("cjSoftMaxHeapSize") != NULL;

    const char* tableHard = NULL;
    int tableSoft = 0;
    int tableMalformed = 0;

    for (size_t i = 0; i < count; ++i) {
        if (entries[i].name == NULL || entries[i].value == NULL) {
            tableMalformed = 1;
            break;
        }
        if (strcmp(entries[i].name, "cjHeapSize") == 0)
            tableHard = entries[i].value;
        if (strcmp(entries[i].name, "cjSoftMaxHeapSize") == 0)
            tableSoft = 1;
    }

    /* Leave malformed tables to the runtime validator. */
    if (tableMalformed) {
        __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
        return;
    }

    /* env hard > explicit table hard > compiler default */
    int needHard = (envHard == NULL && tableHard == NULL);

    /* Soft pacing only when no explicit soft and effective hard > 8GiB. */
    int needSoft = 0;
    if (!envSoft && !tableSoft) {
        const char* effectiveHard = envHard ? envHard : (tableHard ? tableHard : CJC_DEFAULT_HARD);
        needSoft = CJCJ_CompilerHeapAboveSoftDefault(effectiveHard);
    }

    if (!needHard && !needSoft) {
        __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
        return;
    }

    size_t extra = (needHard ? 1 : 0) + (needSoft ? 1 : 0);
    if (count > SIZE_MAX / sizeof(RuntimeConfigEntryV1) - extra) {
        __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
        return;
    }

    RuntimeConfigEntryV1* defaults = malloc((count + extra) * sizeof(*defaults));
    if (defaults == NULL) {
        __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
        return;
    }

    if (count != 0) memcpy(defaults, entries, count * sizeof(*defaults));
    size_t n = count;
    if (needHard)
        defaults[n++] = (RuntimeConfigEntryV1){"cjHeapSize", CJC_DEFAULT_HARD};
    if (needSoft)
        defaults[n++] = (RuntimeConfigEntryV1){"cjSoftMaxHeapSize", "8GB"};

    /* The runtime retains this table until process exit. */
    __real_CJ_MRT_CjRuntimeInitWithConfigV1(defaults, n);
}

void __wrap_CJ_MRT_CjRuntimeInit(void)
{
    __wrap_CJ_MRT_CjRuntimeInitWithConfigV1(NULL, 0);
}
#endif
