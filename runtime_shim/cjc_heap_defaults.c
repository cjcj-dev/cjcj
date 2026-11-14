/* Linux compiler-only startup adapter. Linked by packages/cjc, never by utils
 * consumers. Target init uses V1; the legacy H1 build uses the host init ABI.
 * GNU --wrap changes calls in this executable, not runtime/library definitions. */
#if defined(__linux__)
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char* name;
    const char* value;
} RuntimeConfigEntryV1;

/* Compiler policy only; the runtime default and child environment stay intact. */
#define CJC_DEFAULT_HARD "4GB"

extern int CJCJ_CompilerHeapBelowMinimum(const char* hard);
extern int CJCJ_CompilerHeapAboveSoftDefault(const char* hard);
/* Runtime heap arguments are consumed synchronously during init. Restore the
 * environment before any compiler work/child process starts; applications do
 * not inherit a compiler-injected minimum. Invalid requests retain runtime
 * validation, rather than silently turning a spelling error into 4 GiB. */
static char* RaiseEnvironment(void)
{
    const char* hard = getenv("cjHeapSize");
    char* saved = hard ? strdup(hard) : NULL;
    if (hard && !saved) abort();
    if (setenv("cjHeapSize", CJC_DEFAULT_HARD, 1) != 0) abort();
    return saved;
}

static void RestoreEnvironment(char* saved)
{
    int rc = saved ? setenv("cjHeapSize", saved, 1) : unsetenv("cjHeapSize");
    free(saved);
    if (rc != 0) abort();
}

#ifdef CJCJ_LEGACY_HOST_RUNTIME
extern void __real_CJ_MRT_CjRuntimeInit(void);
void __wrap_CJ_MRT_CjRuntimeInit(void)
{
    int raise = CJCJ_CompilerHeapBelowMinimum(getenv("cjHeapSize"));
    char* saved = raise ? RaiseEnvironment() : NULL;
    __real_CJ_MRT_CjRuntimeInit();
    if (raise) RestoreEnvironment(saved);
}
#else
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
    const char* hard = envHard ? envHard : tableHard;
    int minimum = CJCJ_CompilerHeapBelowMinimum(hard);
    int needHard = tableHard == NULL && minimum;
    int raiseEnv = envHard != NULL && minimum;

    /* Soft pacing only when no explicit soft and effective hard > 8GiB. */
    int needSoft = 0;
    if (!envSoft && !tableSoft) {
        const char* effectiveHard = minimum ? CJC_DEFAULT_HARD : hard;
        needSoft = CJCJ_CompilerHeapAboveSoftDefault(effectiveHard);
    }

    if (!minimum && !needSoft) {
        __real_CJ_MRT_CjRuntimeInitWithConfigV1(entries, count);
        return;
    }

    size_t extra = (needHard ? 1 : 0) + (needSoft ? 1 : 0);
    if (count > SIZE_MAX / sizeof(RuntimeConfigEntryV1) - extra) {
        abort();
    }

    RuntimeConfigEntryV1* defaults = malloc((count + extra) * sizeof(*defaults));
    if (defaults == NULL) abort();
    for (size_t i = 0; i < count; ++i) {
        defaults[i] = entries[i];
        if (minimum && strcmp(defaults[i].name, "cjHeapSize") == 0)
            defaults[i].value = CJC_DEFAULT_HARD;
    }
    size_t n = count;
    if (needHard)
        defaults[n++] = (RuntimeConfigEntryV1){"cjHeapSize", CJC_DEFAULT_HARD};
    if (needSoft)
        defaults[n++] = (RuntimeConfigEntryV1){"cjSoftMaxHeapSize", "8GB"};

    /* The runtime retains this table until process exit. */
    char* saved = raiseEnv ? RaiseEnvironment() : NULL;
    __real_CJ_MRT_CjRuntimeInitWithConfigV1(defaults, n);
    if (raiseEnv) RestoreEnvironment(saved);
}

void __wrap_CJ_MRT_CjRuntimeInit(void)
{
    __wrap_CJ_MRT_CjRuntimeInitWithConfigV1(NULL, 0);
}
#endif
#endif /* legacy / ConfigV1 */
