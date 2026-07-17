/*
 * The native compiler configures macro coroutine stacks in
 * InvokeRuntime::CallRuntime (InvokeUtilCJNative.cpp:151-168).  A self-hosted
 * compiler must apply the same default before its process runtime starts.
 */
#include <stdlib.h>

#ifdef _WIN32
static void __cdecl CallRuntime(void);
#pragma section(".CRT$XCU", read)
__declspec(allocate(".CRT$XCU")) void(__cdecl* CallRuntimeInitializer)(void) = CallRuntime;

static void __cdecl CallRuntime(void)
{
    if (getenv("CJSTACKSIZE") == NULL) {
        (void)_putenv_s("CJSTACKSIZE", "4mb");
    }
}
#else
__attribute__((constructor)) static void CallRuntime(void)
{
    if (getenv("cjStackSize") == NULL) {
        (void)setenv("cjStackSize", "4mb", 0);
    }
}
#endif
