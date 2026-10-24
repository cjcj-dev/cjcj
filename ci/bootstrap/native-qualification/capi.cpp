#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif
namespace fs = std::filesystem;
static std::string json(const std::string& value) {
    std::string result = "\"";
    for (unsigned char c : value) {
        if (c == '\\' || c == '"') result += '\\';
        if (c < 0x20) throw std::runtime_error("invalid library path");
        result += static_cast<char>(c);
    }
    return result + "\"";
}
int main(int argc, char** argv) {
    try {
        if (argc != 2) throw std::runtime_error("usage: cjcj-llvm-capi LIBRARY");
        const auto library = fs::canonical(fs::u8path(argv[1]));
#ifdef _WIN32
        // Load dependent DLLs from this authenticated library's directory and
        // the system directory, rather than the caller's working directory.
        auto handle = LoadLibraryExW(library.c_str(), nullptr,
            LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (!handle) throw std::runtime_error("LLVM_DYLIB_LOAD_FAILED error=" + std::to_string(GetLastError()));
        auto symbol = [&](const std::string& name) -> void* {
            auto address = GetProcAddress(handle, name.c_str());
            if (!address) throw std::runtime_error("LLVM_DYLIB_TARGETS_MISSING " + name);
            return reinterpret_cast<void*>(address);
        };
        HMODULE origin = nullptr;
        auto address = symbol("LLVMContextCreate");
        if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                reinterpret_cast<LPCWSTR>(address), &origin)) throw std::runtime_error("LLVM_DYLIB_ORIGIN_UNRESOLVED");
        std::wstring filename(32768, L'\0');
        auto size = GetModuleFileNameW(origin, filename.data(), static_cast<DWORD>(filename.size()));
        if (!size || size == filename.size()) throw std::runtime_error("LLVM_DYLIB_ORIGIN_UNRESOLVED");
        filename.resize(size);
        const auto loaded = fs::canonical(filename);
#else
        auto handle = dlopen(library.c_str(), RTLD_NOW | RTLD_LOCAL);
        if (!handle) throw std::runtime_error(std::string("LLVM_DYLIB_LOAD_FAILED ") + dlerror());
        auto symbol = [&](const std::string& name) -> void* {
            dlerror();
            auto address = dlsym(handle, name.c_str());
            if (!address) throw std::runtime_error("LLVM_DYLIB_TARGETS_MISSING " + name);
            return address;
        };
        Dl_info info{};
        if (!dladdr(symbol("LLVMContextCreate"), &info) || !info.dli_fname)
            throw std::runtime_error("LLVM_DYLIB_ORIGIN_UNRESOLVED");
        const auto loaded = fs::canonical(info.dli_fname);
#endif
        if (loaded != library) throw std::runtime_error("LLVM_DYLIB_LOADED_PATH_MISMATCH " + loaded.u8string());
        int targets = 0;
        for (const auto* target : {"X86", "ARM", "AArch64"}) {
            for (const auto* part : {"TargetInfo", "Target", "TargetMC", "AsmPrinter", "AsmParser"}) {
                reinterpret_cast<void (*)()>(symbol(std::string("LLVMInitialize") + target + part))();
                ++targets;
            }
        }
        auto context = reinterpret_cast<void* (*)()>(symbol("LLVMContextCreate"))();
        if (!context) throw std::runtime_error("LLVM_DYLIB_CONTEXT_FAILED");
        reinterpret_cast<void (*)(void*)>(symbol("LLVMContextDispose"))(context);
        std::string lookups = "[";
        for (const auto* triple : {"x86_64-unknown-linux-gnu", "arm-unknown-linux-gnueabi", "aarch64-unknown-linux-gnu"}) {
            void* target = nullptr;
            char* error = nullptr;
            const auto rc = reinterpret_cast<int (*)(const char*, void**, char**)>(symbol("LLVMGetTargetFromTriple"))(triple, &target, &error);
            const auto* name = target ? reinterpret_cast<const char* (*)(void*)>(symbol("LLVMGetTargetName"))(target) : "";
            if (lookups.size() > 1) lookups += ',';
            lookups += "{\"triple\":" + json(triple) + ",\"rc\":" + std::to_string(rc)
                + ",\"name\":" + json(name) + ",\"error\":" + json(error ? error : "") + "}";
            if (error) reinterpret_cast<void (*)(char*)>(symbol("LLVMDisposeMessage"))(error);
        }
        lookups += ']';
        std::cout << "{\"loaded\":" << json(loaded.u8string())
                  << ",\"targets\":" << targets << ",\"context_call\":\"ok\",\"lookups\":" << lookups << "}\n";
#ifdef _WIN32
        FreeLibrary(handle);
#else
        dlclose(handle);
#endif
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
