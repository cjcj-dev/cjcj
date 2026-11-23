// Native consumer: bind a symbol, observe dladdr, then exercise LLVM's C API.
#include <dlfcn.h>
#include <limits.h>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <initializer_list>
#include <string>

int main(int argc, char** argv)
{
    if (argc != 4) return 64;
    char expected[PATH_MAX];
    if (!realpath(argv[1], expected)) return 65;
    void* library = dlopen(expected, RTLD_NOW | RTLD_LOCAL);
    if (!library) { std::cerr << "DARWIN_DLOPEN_FAILED " << dlerror() << '\n'; return 66; }
    void* symbol = dlsym(library, argv[2]);
    Dl_info info{};
    char loaded[PATH_MAX];
    if (!symbol || !dladdr(symbol, &info) || !realpath(info.dli_fname, loaded)) {
        std::cerr << "DARWIN_LOADED_SYMBOL_MISSING " << argv[2] << '\n'; return 67;
    }
    std::cout << "DARWIN_LOADED_ORIGIN " << loaded << '\n';
    if (std::strcmp(expected, loaded) != 0) {
        std::cerr << "DARWIN_LOADED_PATH_MISMATCH expected=" << expected << " actual=" << loaded << '\n';
        return 68;
    }
    if (std::strcmp(argv[3], "llvm") == 0) {
        for (const char* target : {"X86", "ARM", "AArch64"}) {
            for (const char* part : {"TargetInfo", "Target", "TargetMC", "AsmPrinter", "AsmParser"}) {
                const std::string name = std::string("LLVMInitialize") + target + part;
                auto initialize = reinterpret_cast<void (*)()>(dlsym(library, name.c_str()));
                if (!initialize) { std::cerr << "DARWIN_LLVM_TARGET_MISSING " << name << '\n'; return 69; }
                initialize();
            }
        }
        std::cout << "DARWIN_LLVM_TARGETS_OK\n";
        auto create = reinterpret_cast<void* (*)()>(dlsym(library, "LLVMContextCreate"));
        auto dispose = reinterpret_cast<void (*)(void*)>(dlsym(library, "LLVMContextDispose"));
        if (!create || !dispose) return 69;
        void* context = create();
        if (!context) return 70;
        dispose(context);
        std::cout << "DARWIN_LLVM_CONTEXT_OK\n";
    }
    if (std::strcmp(argv[3], "boundscheck") == 0) {
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
