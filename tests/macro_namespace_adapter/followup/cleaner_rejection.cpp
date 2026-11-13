// Installed-runtime controls for default ownership and failed registration.
#include "Cangjie.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <pthread.h>
using Registrar = int (*)(void (*)(void*), void*, void*);
using Setter = int (*)(Registrar);
using Allocate = void* (*)(size_t);
using Free = void (*)(void*, size_t);
static Setter setOwner;
static Allocate allocate;
static Free deallocate;
static Registrar defaultOwner;
static bool failRegistration;
static int failures;
static int rejectedCalls;
static void Check(bool ok, const char* name) {
    std::printf("ASSERT %s %s\n", name, ok ? "PASS" : "FAIL");
    std::fflush(stdout);
    if (!ok) ++failures;
}
static int Reject(void (*)(void*), void*, void* dso) {
    ++rejectedCalls;
    Dl_info info{};
    Check(dladdr(dso, &info) != 0 && std::strstr(info.dli_fname, "libcangjie-runtime.so"), "registrar-reached-original-dso");
    std::puts("REGISTRAR_RETURN_NONZERO=17"); std::fflush(stdout);
    return 17;
}
static void* Worker(void*) {
    if (failRegistration) {
        Check(setOwner(Reject) == 0, "failing-registrar-set-before-allocation");
        allocate(32);
        Check(false, "fatal-registration-must-not-return");
        return nullptr;
    }
    // This physical thread never calls the setter before NativeAlloc.
    void* p = allocate(32);
    Check(p != nullptr, "default-cleaner-produced");
    if (p) deallocate(p, 32);
    Check(setOwner(defaultOwner) == 0, "default-owner-confirmed-after-producer");
    Check(setOwner(Reject) == 2, "different-owner-rejected-after-default");
    Check(rejectedCalls == 0, "rejected-owner-not-invoked");
    p = allocate(64);
    Check(p != nullptr, "default-path-remains-usable");
    if (p) deallocate(p, 64);
    return nullptr;
}
template<class T> static T Symbol(void* handle, const char* name) {
    void* p = dlsym(handle, name);
    if (!p) { std::fprintf(stderr, "MISSING %s %s\n", name, dlerror()); std::exit(2); }
    return reinterpret_cast<T>(p);
}
int main(int argc, char** argv) {
    if (argc != 3) return 2;
    failRegistration = std::strcmp(argv[2], "registrar-error") == 0;
    void* runtime = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!runtime) { std::fprintf(stderr, "%s\n", dlerror()); return 2; }
    setOwner = Symbol<Setter>(runtime, "CJ_MRT_SetForeignThreadCleanerRegistrarV1");
    allocate = Symbol<Allocate>(runtime, "_ZN12MapleRuntime15NativeAllocator11NativeAllocEm");
    deallocate = Symbol<Free>(runtime, "_ZN12MapleRuntime15NativeAllocator10NativeFreeEPvm");
    defaultOwner = Symbol<Registrar>(RTLD_DEFAULT, "__cxa_thread_atexit_impl");
    auto init = Symbol<decltype(&InitCJRuntime)>(runtime, "InitCJRuntime");
    auto fini = Symbol<decltype(&FiniCJRuntime)>(runtime, "FiniCJRuntime");
    RuntimeParam param{}; param.coParam.processorNum = 2;
    Check(init(&param) == E_OK, "runtime-init");
    pthread_t worker{};
    if (pthread_create(&worker, nullptr, Worker, nullptr) != 0) return 2;
    Check(pthread_join(worker, nullptr) == 0, "default-worker-exit");
    Check(fini() == E_OK, "original-fini-retained");
    // Match product retention: no dlclose of a runtime with registered TLS.
    return failures == 0 ? 0 : 1;
}
