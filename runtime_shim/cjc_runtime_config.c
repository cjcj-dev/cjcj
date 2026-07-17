/*
 * The native compiler configures macro coroutine stacks in
 * InvokeRuntime::CallRuntime (InvokeUtilCJNative.cpp:151-168).  A self-hosted
 * compiler must apply the same default before its process runtime starts.
 */
#include <stdlib.h>
#include <ctype.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define UNIT_LEN 2
#define KB 1024
#define MB (KB * KB)
#define CO_STACK_SIZE (4 * KB)
#define G_MIN_STACK_SIZE 64
#define G_MAX_STACK_SIZE (1UL * MB)

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
}
#endif
