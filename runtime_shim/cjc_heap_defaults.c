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

extern int CJCJ_CompilerHeapAboveSoftDefault(const char* hard);
extern void __real_CJ_MRT_CjRuntimeInitWithConfigV1(const RuntimeConfigEntryV1*, size_t);

void __wrap_CJ_MRT_CjRuntimeInitWithConfigV1(const RuntimeConfigEntryV1* entries, size_t count)
{
    const char* hard = getenv("cjHeapSize");
    if (getenv("cjSoftMaxHeapSize") != NULL || (entries == NULL && count != 0)) {
        __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        /* Leave malformed tables and explicit values to the runtime validator. */
        if (entries[i].name == NULL || entries[i].value == NULL ||
            strcmp(entries[i].name, "cjSoftMaxHeapSize") == 0) {
            __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
            return;
        }
        if (hard == NULL && strcmp(entries[i].name, "cjHeapSize") == 0) {
            hard = entries[i].value;
        }
    }
    if (!CJCJ_CompilerHeapAboveSoftDefault(hard) ||
        count >= SIZE_MAX / sizeof(RuntimeConfigEntryV1)) {
        __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
        return;
    }
    RuntimeConfigEntryV1* defaults = malloc((count + 1) * sizeof(*defaults));
    if (defaults == NULL) {
        /* Failure to allocate an optional pacing default preserves normal init. */
        __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
        return;
    }
    if (count != 0) memcpy(defaults, entries, count * sizeof(*defaults));
    defaults[count] = (RuntimeConfigEntryV1){"cjSoftMaxHeapSize", "8GB"};
    /* The runtime retains this table. Its storage lives until process exit;
     * neither an environment variable nor a child process inherits this table. */
    __real_CJ_MRT_CjRuntimeInitWithConfigV1(defaults, count + 1);
}

void __wrap_CJ_MRT_CjRuntimeInit(void)
{
    __wrap_CJ_MRT_CjRuntimeInitWithConfigV1(NULL, 0);
}
#endif
