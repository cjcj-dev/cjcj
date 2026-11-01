/*
 * The native compiler configures macro coroutine stacks in
 * InvokeRuntime::CallRuntime (InvokeUtilCJNative.cpp:151-168).  A self-hosted
 * compiler must apply the same default before its process runtime starts.
 */
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 700
#endif

#include <stdlib.h>
#include <ctype.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef _WIN32
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>

/* This state belongs to a pthread, not a movable Cangjie coroutine. */
typedef struct {
    stack_t previous;
    void* memory;
    size_t size;
} CompilerSignalStack;

static pthread_key_t signalStackKey;
static pthread_once_t signalStackOnce = PTHREAD_ONCE_INIT;
static int signalStackKeyError;

static void ReleaseCompilerSignalStack(void* value)
{
    CompilerSignalStack* owned = value;
    stack_t current;
    if (sigaltstack(NULL, &current) != 0) {
        /* An unverified registration must never be left pointing to freed memory. */
        fprintf(stderr, "cjc: cannot query signal stack at thread exit; retaining memory (errno=%d)\n", errno);
        return;
    }
    if (current.ss_sp == owned->memory && !(current.ss_flags & SS_DISABLE)) {
        if (sigaltstack(&owned->previous, NULL) != 0) {
            fprintf(stderr, "cjc: cannot restore signal stack at thread exit; retaining memory (errno=%d)\n", errno);
            return;
        }
    }
    /* A replacement installed by somebody else is left intact. */
    free(owned->memory);
    free(owned);
}

static void InitializeCompilerSignalStackKey(void)
{
    signalStackKeyError = pthread_key_create(&signalStackKey, ReleaseCompilerSignalStack);
}

/* One C2N call covers the whole decision: no CJ safepoint/migration between
 * querying this pthread's registration and installing its private buffer.
 * Returns an errno/pthread error number; it never calls back into Cangjie. */
int CJCJ_EnsureAltSignalStack(void)
{
    stack_t current;
    if (sigaltstack(NULL, &current) != 0) {
        return errno;
    }
    if (current.ss_flags & SS_ONSTACK) {
        return 0;
    }
    size_t minimum = MINSIGSTKSZ > 8192 ? MINSIGSTKSZ : 8192;
#ifdef _SC_MINSIGSTKSZ
    long kernelMinimum = sysconf(_SC_MINSIGSTKSZ);
    if (kernelMinimum > 0 && (size_t)kernelMinimum > minimum) {
        minimum = (size_t)kernelMinimum;
    }
#endif
    if (!(current.ss_flags & SS_DISABLE) && current.ss_sp != NULL && current.ss_size >= minimum) {
        return 0;
    }
    int error = pthread_once(&signalStackOnce, InitializeCompilerSignalStackKey);
    if (error != 0 || signalStackKeyError != 0) {
        return error != 0 ? error : signalStackKeyError;
    }
    CompilerSignalStack* owned = pthread_getspecific(signalStackKey);
    if (owned == NULL) {
        owned = calloc(1, sizeof(*owned));
        if (owned == NULL) {
            return ENOMEM;
        }
        owned->size = SIGSTKSZ > minimum ? SIGSTKSZ : minimum;
        owned->memory = malloc(owned->size);
        if (owned->memory == NULL) {
            free(owned);
            return ENOMEM;
        }
        error = pthread_setspecific(signalStackKey, owned);
        if (error != 0) {
            free(owned->memory);
            free(owned);
            return error;
        }
    }
    owned->previous = current;
    stack_t replacement = {.ss_sp = owned->memory, .ss_flags = 0, .ss_size = owned->size};
    if (sigaltstack(&replacement, NULL) != 0) {
        /* Keep ownership in the pthread key even on failure, for retry/exit. */
        return errno;
    }
    return 0;
}
#endif

#define UNIT_LEN 2
#define KB 1024
#define MB (KB * KB)
#define CO_STACK_SIZE (4 * KB)
#define G_MIN_STACK_SIZE 64
#define G_MAX_STACK_SIZE (1UL * MB)

#ifndef CJCJ_COMMIT
#define CJCJ_COMMIT "unknown"
#endif

#ifdef _WIN32
#if defined(__GNUC__)
__declspec(dllexport) __attribute__((used))
#else
__declspec(dllexport)
#endif
const char g_cjcjProvenance[] = "CJCJ-COMMIT:" CJCJ_COMMIT;
#else
__attribute__((used, visibility("default")))
const char g_cjcjProvenance[] = "CJCJ-COMMIT:" CJCJ_COMMIT;
#endif

static size_t GetSizeFromEnv(const char* value)
{
    char* compact = malloc(strlen(value) + 1);
    size_t src = 0;
    size_t dst = 0;
    while (value[src] != '\0') {
        if (value[src] != ' ') {
            compact[dst++] = value[src];
        }
        ++src;
    }
    compact[dst] = '\0';
    if (dst <= UNIT_LEN) {
        free(compact);
        return SIZE_MAX;
    }

    char* unit = compact + dst - UNIT_LEN;
    unit[0] = (char)tolower((unsigned char)unit[0]);
    unit[1] = (char)tolower((unsigned char)unit[1]);
    if (strcmp(unit, "kb") != 0 && strcmp(unit, "mb") != 0 && strcmp(unit, "gb") != 0) {
        free(compact);
        return SIZE_MAX;
    }
    char unitKind = unit[0];
    *unit = '\0';

    char* end = NULL;
    long number = strtol(compact, &end, 10);
    if (end == compact || *end != '\0' || number < INT32_MIN || number > INT32_MAX) {
        free(compact);
        return SIZE_MAX;
    }
    if (number <= 0) {
        free(compact);
        return 0;
    }
    if (unitKind == 'm') {
        size_t size = (size_t)number * KB;
        free(compact);
        return size;
    }
    if (unitKind == 'g') {
        size_t size = (size_t)number * MB;
        free(compact);
        return size;
    }
    size_t size = (size_t)number;
    free(compact);
    return size;
}

static size_t GetStackSizeFromEnv(const char* name)
{
    const char* value = getenv(name);
    if (value == NULL) {
        return CO_STACK_SIZE;
    }
    size_t stackSize = GetSizeFromEnv(value);
    if (stackSize == SIZE_MAX) {
        return CO_STACK_SIZE;
    }
    if (stackSize < G_MIN_STACK_SIZE || stackSize > G_MAX_STACK_SIZE) {
        return CO_STACK_SIZE;
    }
    return stackSize;
}

#if defined(__linux__)
/* In KB, matching GetSizeFromEnv. */
#define COMPILER_SOFT_MAX_HEAP_SIZE (8 * MB)

static int IsCompilerExecutable(void)
{
    char path[4096];
    ssize_t length = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (length <= 0) {
        return 0;
    }
    path[length] = '\0';
    const char* slash = strrchr(path, '/');
    const char* name = slash == NULL ? path : slash + 1;
    return strcmp(name, "cjc") == 0 || strcmp(name, "cjcj::cjc") == 0;
}

/*
 * An explicit cjHeapSize also becomes the GC pacing target, so a compile keeps
 * far more heap committed than it needs. Compiling packages/chir with
 * cjHeapSize=16GB peaked at 17.9GiB; cjSoftMaxHeapSize=8GB peaked at 12.5GiB
 * with the same wall and CPU time.
 *
 * Only the compiler sets this. The object is linked into every product using
 * packages/utils, the variable is inherited, and the runtime refuses to start
 * a process whose soft limit exceeds its cjHeapSize, so a tool setting it could
 * break a program it starts with a smaller heap. At or below the default the
 * soft limit already follows cjHeapSize, so nothing needs setting.
 */
static void SetCompilerSoftMaxHeapSize(void)
{
    const char* hard = getenv("cjHeapSize");
    if (hard == NULL || getenv("cjSoftMaxHeapSize") != NULL) {
        return;
    }
    size_t hardSize = GetSizeFromEnv(hard);
    if (hardSize == SIZE_MAX || hardSize <= COMPILER_SOFT_MAX_HEAP_SIZE || !IsCompilerExecutable()) {
        return;
    }
    (void)setenv("cjSoftMaxHeapSize", "8GB", 0);
}
#endif

#ifdef _WIN32
static void __cdecl CallRuntime(void);
#pragma section(".CRT$XCU", read)
__declspec(allocate(".CRT$XCU")) void(__cdecl* CallRuntimeInitializer)(void) = CallRuntime;

static void __cdecl CallRuntime(void)
{
    char stackSize[32];
    (void)snprintf(stackSize, sizeof(stackSize), "%zukb", GetStackSizeFromEnv("CJSTACKSIZE"));
    (void)_putenv_s("CJSTACKSIZE", stackSize);
}
#else
__attribute__((constructor)) static void CallRuntime(void)
{
    char stackSize[32];
    (void)snprintf(stackSize, sizeof(stackSize), "%zukb", GetStackSizeFromEnv("cjStackSize"));
    (void)setenv("cjStackSize", stackSize, 1);
#if defined(__linux__)
    SetCompilerSoftMaxHeapSize();
#endif
}
#endif
