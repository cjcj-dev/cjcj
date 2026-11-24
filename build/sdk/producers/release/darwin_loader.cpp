// Native consumer: bind a symbol, observe the loaded module's own path, then
// exercise LLVM's C API. POSIX uses dlopen/dladdr; Windows uses LoadLibraryEx,
// GetProcAddress and the module that owns the resolved address.
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <initializer_list>
#include <string>
#ifdef _WIN32
#include <windows.h>
#define NATIVE_PATH_MAX MAX_PATH
static void* lookup(void* library, const char* name)
{
    return reinterpret_cast<void*>(GetProcAddress(static_cast<HMODULE>(library), name));
}
static bool same_path(const char* left, const char* right) { return _stricmp(left, right) == 0; }
#else
#include <dlfcn.h>
#include <limits.h>
#define NATIVE_PATH_MAX PATH_MAX
static void* lookup(void* library, const char* name) { return dlsym(library, name); }
static bool same_path(const char* left, const char* right) { return std::strcmp(left, right) == 0; }
#endif

int main(int argc, char** argv)
{
    if (argc != 4) return 64;
    char expected[NATIVE_PATH_MAX];
    char loaded[NATIVE_PATH_MAX];
#ifdef _WIN32
    if (!GetFullPathNameA(argv[1], NATIVE_PATH_MAX, expected, nullptr)) return 65;
    void* library = LoadLibraryExA(expected, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!library) { std::cerr << "WINDOWS_LOADLIBRARY_FAILED " << GetLastError() << '\n'; return 66; }
    void* symbol = lookup(library, argv[2]);
    HMODULE owner = nullptr;
    char module[NATIVE_PATH_MAX];
    if (!symbol || !GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            static_cast<LPCSTR>(symbol), &owner) || !GetModuleFileNameA(owner, module, NATIVE_PATH_MAX)
        || !GetFullPathNameA(module, NATIVE_PATH_MAX, loaded, nullptr)) {
        std::cerr << "WINDOWS_LOADED_SYMBOL_MISSING " << argv[2] << '\n'; return 67;
    }
    std::cout << "WINDOWS_LOADED_ORIGIN " << loaded << '\n';
#else
    if (!realpath(argv[1], expected)) return 65;
    void* library = dlopen(expected, RTLD_NOW | RTLD_LOCAL);
    if (!library) { std::cerr << "DARWIN_DLOPEN_FAILED " << dlerror() << '\n'; return 66; }
    void* symbol = dlsym(library, argv[2]);
    Dl_info info{};
    if (!symbol || !dladdr(symbol, &info) || !realpath(info.dli_fname, loaded)) {
        std::cerr << "DARWIN_LOADED_SYMBOL_MISSING " << argv[2] << '\n'; return 67;
    }
    std::cout << "DARWIN_LOADED_ORIGIN " << loaded << '\n';
#endif
    if (!same_path(expected, loaded)) {
        std::cerr << "DARWIN_LOADED_PATH_MISMATCH expected=" << expected << " actual=" << loaded << '\n';
        return 68;
    }
    if (std::strcmp(argv[3], "llvm") == 0) {
        for (const char* target : {"X86", "ARM", "AArch64"}) {
            for (const char* part : {"TargetInfo", "Target", "TargetMC", "AsmPrinter", "AsmParser"}) {
                const std::string name = std::string("LLVMInitialize") + target + part;
                auto initialize = reinterpret_cast<void (*)()>(lookup(library, name.c_str()));
                if (!initialize) { std::cerr << "DARWIN_LLVM_TARGET_MISSING " << name << '\n'; return 69; }
                initialize();
            }
        }
        std::cout << "DARWIN_LLVM_TARGETS_OK\n";
        auto create = reinterpret_cast<void* (*)()>(lookup(library, "LLVMContextCreate"));
        auto dispose = reinterpret_cast<void (*)(void*)>(lookup(library, "LLVMContextDispose"));
        if (!create || !dispose) return 69;
        void* context = create();
        if (!context) return 70;
        dispose(context);
        std::cout << "DARWIN_LLVM_CONTEXT_OK\n";
    }
    if (std::strcmp(argv[3], "boundscheck") == 0 && std::strcmp(argv[2], "memset_s") == 0) {
        // Windows libboundscheck.dll exports memset_s, not memcpy_s (the C
        // runtime supplies that one). A valid call must succeed and fill every
        // byte; a call whose count exceeds destMax must be refused without
        // writing past destMax.
        auto fill = reinterpret_cast<int (*)(void*, size_t, int, size_t)>(symbol);
        constexpr size_t capacity = 24;
        constexpr unsigned char pattern = 0x5a, guard = 0xc3;
        unsigned char output[capacity * 2];
        std::memset(output, guard, sizeof(output));
        if (fill(output, capacity, pattern, capacity) != 0) return 71;
        for (size_t i = 0; i < sizeof(output); ++i) {
            if (output[i] != (i < capacity ? pattern : guard)) return 71;
        }
        if (fill(output, capacity, 0, capacity + 1) == 0) return 71;
        for (size_t i = capacity; i < sizeof(output); ++i) {
            if (output[i] != guard) return 71;
        }
        std::cout << "NATIVE_BOUNDS_CALL_OK\n";
    } else if (std::strcmp(argv[3], "boundscheck") == 0) {
        auto copy = reinterpret_cast<int (*)(void*, size_t, const void*, size_t)>(symbol);
        const char input[] = "native installed bounds";
        char output[sizeof(input)]{};
        if (copy(output, sizeof(output), input, sizeof(input)) != 0 ||
            std::memcmp(input, output, sizeof(input)) != 0) return 71;
        std::cout << "NATIVE_BOUNDS_CALL_OK\n";
    }
    // Runtime teardown is process-owned. Loading/looking up the ABI symbol does
    // not execute a safepoint without a managed caller or waive the ABI hold.
    return 0;
}
