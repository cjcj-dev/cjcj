// Exercise the installed runtime's actual NativeAlloc -> cleaner -> complete
// destructor path with libc-owned threads in both namespace directions.
#include "Cangjie.h"
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <link.h>
#include <pthread.h>

using Registrar = int (*)(void (*)(void*), void*, void*);
using Setter = int (*)(Registrar);
using Allocate = void* (*)(size_t);
using Free = void (*)(void*, size_t);
static Registrar owner;
static Setter setOwner;
static Allocate allocate;
static Free deallocate;
static void (*savedDtor)(void*);
static void* savedObject;
static std::atomic<int> registrations{0};
static std::atomic<int> destructors{0};
static std::atomic<int> failures{0};

static bool Check(bool ok, const char* name)
{
    std::printf("ASSERT %s %s\n", name, ok ? "PASS" : "FAIL");
    std::fflush(stdout);
    if (!ok) { ++failures; }
    return ok;
}
static void CompleteDtor(void* object)
{
    Check(object == savedObject, "original-cleaner-object");
    // Invoke the complete runtime destructor received at registration, not a
    // test unlink/replacement. Count only after that destructor returns.
    savedDtor(object);
    ++destructors;
}
static int RecordRegistration(void (*dtor)(void*), void* object, void* dso)
{
    savedDtor = dtor;
    savedObject = object;
    Dl_info info{};
    Check(dladdr(dso, &info) != 0 && std::strstr(info.dli_fname, "libcangjie-runtime.so"), "original-runtime-dso");
    std::printf("DTOR_DSO %s\n", info.dli_fname);
    ++registrations;
    return owner(CompleteDtor, object, dso);
}
static void* Worker(void*)
{
    Check(setOwner(nullptr) == 1, "null-owner-rejected");
    Check(setOwner(RecordRegistration) == 0, "native-owner-before-producer");
    void* first = allocate(32);
    Check(first != nullptr, "native-allocation-reached");
    if (first != nullptr) { deallocate(first, 32); }
    Check(setOwner(RecordRegistration) == 0, "same-owner-reentry");
    Check(setOwner(owner) == 2, "late-owner-change-rejected");
    void* second = allocate(48);
    if (second != nullptr) { deallocate(second, 48); }
    Check(registrations == 1 && destructors == 0, "one-registration-before-exit");
    return nullptr;
}
template<class T> static T Symbol(void* handle, const char* name)
{
    void* symbol = dlsym(handle, name);
    if (!symbol) { std::fprintf(stderr, "MISSING %s: %s\n", name, dlerror()); std::exit(2); }
    return reinterpret_cast<T>(symbol);
}
int main(int argc, char** argv)
{
    if (argc != 3) { return 2; }
    const bool reverse = std::strcmp(argv[2], "reverse") == 0;
    const bool base = std::strcmp(argv[2], "base") == 0;
    const bool cut = std::strcmp(argv[2], "cut") == 0;
    void* runtime = reverse ? dlmopen(LM_ID_NEWLM, argv[1], RTLD_NOW | RTLD_LOCAL)
                            : dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!runtime) { std::fprintf(stderr, "RUNTIME_LOAD %s\n", dlerror()); return 2; }
    void* baseLibc = dlopen("libc.so.6", RTLD_NOW | RTLD_LOCAL);
    void* carrierLibc = (base || reverse) ? baseLibc : dlmopen(LM_ID_NEWLM, "libc.so.6", RTLD_NOW | RTLD_LOCAL);
    if (!carrierLibc) { std::fprintf(stderr, "CARRIER_LOAD %s\n", dlerror()); return 2; }
    owner = Symbol<Registrar>(cut ? baseLibc : carrierLibc, "__cxa_thread_atexit_impl");
    setOwner = Symbol<Setter>(runtime, "CJ_MRT_SetForeignThreadCleanerRegistrarV1");
    allocate = Symbol<Allocate>(runtime, "_ZN12MapleRuntime15NativeAllocator11NativeAllocEm");
    deallocate = Symbol<Free>(runtime, "_ZN12MapleRuntime15NativeAllocator10NativeFreeEPvm");
    auto init = Symbol<decltype(&InitCJRuntime)>(runtime, "InitCJRuntime");
    auto fini = Symbol<decltype(&FiniCJRuntime)>(runtime, "FiniCJRuntime");
    // Runtime initialization executes on the base main thread, even when the
    // initialized runtime is in a new map. Establish the reverse owner first.
    Check(setOwner(Symbol<Registrar>(baseLibc, "__cxa_thread_atexit_impl")) == 0, "initializer-carrier-owner");
    RuntimeParam param{};
    param.coParam.processorNum = 2;
    if (!Check(init(&param) == E_OK, "runtime-init")) { return 2; }
    auto create = Symbol<decltype(&pthread_create)>(carrierLibc, "pthread_create");
    auto join = Symbol<decltype(&pthread_join)>(carrierLibc, "pthread_join");
    pthread_t thread{};
    if (!Check(create(&thread, nullptr, Worker, nullptr) == 0, "carrier-create")) { return 2; }
    Check(join(thread, nullptr) == 0, "carrier-joined");
    const bool destroyed = Check(registrations == 1 && destructors == 1, "complete-dtor-before-tls-unmap");
    if (!destroyed) {
        // The intentional wrong-libc arm has proved the lifecycle violation.
        // Do not obscure that assertion with the later known dangling-list crash.
        std::fflush(nullptr);
        _Exit(1);
    }
    Check(fini() == E_OK, "runtime-fini-retained");
    return failures == 0 ? 0 : 1;
}
