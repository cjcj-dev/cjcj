// Authentication of this binary and its entry recipe happens before installation.
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cwchar>
#include <filesystem>
#include <algorithm>
#include <fstream>
#include <string>
#include <type_traits>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#else
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#endif
namespace fs = std::filesystem;
static fs::path self() {
#ifdef _WIN32
    std::vector<wchar_t> b(32768);
    const auto n = GetModuleFileNameW(nullptr, b.data(), static_cast<DWORD>(b.size()));
    if (!n || n == b.size()) throw std::runtime_error("entry executable path");
    return fs::canonical(fs::path(std::wstring(b.data(), n)));
#elif defined(__APPLE__)
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    std::vector<char> b(size);
    if (_NSGetExecutablePath(b.data(), &size)) throw std::runtime_error("entry executable path");
    return fs::canonical(b.data());
#else
    return fs::canonical("/proc/self/exe");
#endif
}
static fs::path member(const fs::path &root, const std::string &rel) {
    fs::path p = fs::u8path(rel);
    if (p.is_absolute()) throw std::runtime_error("absolute recipe member");
    for (const auto &part : p) if (part == "..") throw std::runtime_error("recipe member escape");
    return root / p;
}
// HLE's fixed component defaults are cwd-relative. Its installed public entry
// supplies the same inputs from this SDK without changing cwd or user paths.
// Match std.argopt's complete long-name lookup before short-option clusters,
// with either one or two dashes. Skip values even when they look like options.
template<class Text>
static std::vector<Text> hleArguments(const std::vector<Text> &args, const fs::path &root) {
    bool binding = false, parser = false, typescript = false;
    for (size_t i = 1; i < args.size(); ++i) {
        const auto &arg = args[i];
        if (arg.size() < 2 || arg[0] != '-') continue;
        if (arg.size() == 2 && arg[1] == '-') break;
        const auto narrow = fs::path(arg).u8string();
        const auto start = arg[1] == '-' ? 2u : 1u;
        const auto equal = narrow.find('=', start);
        const auto name = narrow.substr(start, equal == std::string::npos ? equal : equal - start);
        if (name == "clang-args" || name == "module-name") {
            if (equal == std::string::npos) ++i;
            continue;
        }
        if (name == "help" && equal == std::string::npos) return args;
        if (name == "help" || name == "lib" || name == "no-detect-include-path") continue;
        // Unknown double-dash names are rejected by the component, never clusters.
        if (arg[1] == '-') continue;
        for (size_t j = 1; j < arg.size(); ++j) {
            const auto option = arg[j];
            if (option == 'h') return args;
            if (option == 'b') binding = true;
            if (option == 'j') parser = true;
            if (option == 'r') typescript = true;
            if (option == 'b' || option == 'j' || option == 'r' ||
                option == 'i' || option == 'o' || option == 'd') {
                if (j + 1 == arg.size()) ++i;
                break;
            }
            // Only c/h are valueless short options. Leave an invalid cluster to
            // std.argopt instead of finding a later h/b/j/r inside its spelling.
            if (option != 'c') return args;
        }
    }
    std::vector<Text> result;
    if (!args.empty()) result.push_back(args[0]);
    const auto add = [&](char option, const fs::path &value) {
        result.push_back(Text{static_cast<typename Text::value_type>('-'),
                              static_cast<typename Text::value_type>(option)});
        if constexpr (std::is_same_v<typename Text::value_type, wchar_t>) result.push_back(value.wstring());
        else result.push_back(value.u8string());
    };
#ifdef _WIN32
    if (!binding) add('b', root / "tools/dtsparser/node_modules/.bin/cjbind.exe");
#else
    if (!binding) add('b', root / "tools/dtsparser/node_modules/.bin/cjbind");
#endif
    if (!parser) add('j', root / "tools/dtsparser/analysis.js");
    if (!typescript) add('r', root / "tools/dtsparser/node_modules/typescript");
    if (args.size() > 1) result.insert(result.end(), args.begin() + 1, args.end());
    return result;
}
#ifdef _WIN32
static std::wstring quote(const std::wstring &s) {
    std::wstring out = L"\"";
    size_t slashes = 0;
    for (wchar_t c : s) {
        if (c == L'\\') { ++slashes; continue; }
        out.append(c == L'"' ? slashes * 2 + 1 : slashes, L'\\');
        slashes = 0; out += c;
    }
    out.append(slashes * 2, L'\\'); return out + L'"';
}
static void env(const wchar_t *key, const fs::path &value) {
    if (!SetEnvironmentVariableW(key, value.c_str())) throw std::runtime_error("entry environment");
}
#endif
int main(int argc, char **argv) {
    try {
        const auto binary = self();
        auto recipePath = binary; recipePath += ".entry";
        std::ifstream recipe(recipePath, std::ios::binary);
        std::vector<std::string> lines;
        for (std::string line; std::getline(recipe, line);) lines.push_back(line);
        if (!recipe.eof() || lines.size() < 6 || lines[0] != "cjcj-sdk-entry-v1")
            throw std::runtime_error("entry recipe format");
        size_t used = 0; const auto ascent = std::stoul(lines[1], &used);
        if (used != lines[1].size() || ascent > 32) throw std::runtime_error("entry recipe ascent");
        auto root = binary.parent_path();
        for (size_t i = 0; i < ascent; ++i) root = root.parent_path();
        const auto real = member(root, lines[2]);
#if defined(__aarch64__) || defined(_M_ARM64)
        const char *targetRole = "native-target:arm64";
#elif defined(__x86_64__) || defined(_M_X64)
        const char *targetRole = "native-target:x64";
#else
#error Unsupported SDK entry architecture
#endif
        if (lines[4] != targetRole) throw std::runtime_error("entry architecture mismatch");
        // Preserve ordinary build inputs; only the runtime loader is selected here.

        std::string libraries;
        for (size_t i = 5; i < lines.size(); ++i) {
            if (i > 5) libraries +=
#ifdef _WIN32
                ';';
#else
                ':';
#endif
            libraries += member(root, lines[i]).u8string();
        }
#ifdef _WIN32
        if (lines[3] != "windows") throw std::runtime_error("entry platform mismatch");
        env(L"CANGJIE_HOME", root);
        std::wstring oldPath;
        const DWORD size = GetEnvironmentVariableW(L"PATH", nullptr, 0);
        if (size) { std::vector<wchar_t> b(size); GetEnvironmentVariableW(L"PATH", b.data(), size); oldPath = b.data(); }
        // Windows resolves the executable directory first; retained DLLs stay
        // beside the retained executable. PATH then supplies its declared domain.
        auto wideLib = fs::u8path(libraries).wstring();
        const auto search = wideLib + L";" + (root / L"bin").wstring() + L";" +
            (root / L"tools/bin").wstring() + L";" + (root / L"third_party/llvm/bin").wstring() + L";" + oldPath;
        SetEnvironmentVariableW(L"PATH", search.c_str());
        int count = 0; auto args = CommandLineToArgvW(GetCommandLineW(), &count);
        if (!args) throw std::runtime_error("entry arguments");
        std::wstring reportedArgv0;
        const auto realDir = real.parent_path();
        if (count > 0 && args[0] && realDir.filename() == L"compiler" &&
            realDir.parent_path().filename() == L"libexec") {
            reportedArgv0 = (root / L"bin" / fs::path(args[0]).filename()).wstring();
            args[0] = reportedArgv0.data();
        }
        std::wstring command;
        std::vector<std::wstring> selectedArgs(args, args + count);
        if (lines[2] == ".target-tools/tools/bin/hle.exe") selectedArgs = hleArguments(selectedArgs, root);
        for (size_t i = 0; i < selectedArgs.size(); ++i) { if (i) command += L' '; command += quote(selectedArgs[i]); }
        LocalFree(args);
        STARTUPINFOW startup{}; startup.cb = sizeof(startup); PROCESS_INFORMATION child{};
        if (!CreateProcessW(real.c_str(), command.data(), nullptr, nullptr, TRUE, 0, nullptr, nullptr, &startup, &child))
            throw std::runtime_error("entry CreateProcess");
        CloseHandle(child.hThread); WaitForSingleObject(child.hProcess, INFINITE);
        DWORD rc = 1; GetExitCodeProcess(child.hProcess, &rc); CloseHandle(child.hProcess);
        return static_cast<int>(rc);
#else
#ifdef __APPLE__
        if (lines[3] != "darwin") throw std::runtime_error("entry platform mismatch");
        const char *loader = "DYLD_LIBRARY_PATH";
#else
        if (lines[3] != "linux") throw std::runtime_error("entry platform mismatch");
        const char *loader = "LD_LIBRARY_PATH";
#endif
        if (setenv(loader, libraries.c_str(), 1) || setenv("CANGJIE_HOME", root.c_str(), 1))
            throw std::runtime_error("entry environment");
        unsetenv("LD_PRELOAD"); unsetenv("LD_AUDIT"); unsetenv("DYLD_INSERT_LIBRARIES");
        const char *inheritedPath = getenv("PATH");
        const auto search = (root / "bin").string() + ":" + (root / "tools/bin").string() + ":" +
            (root / "third_party/llvm/bin").string() + ":" + (inheritedPath ? inheritedPath : "/usr/bin:/bin");
        if (setenv("PATH", search.c_str(), 1)) throw std::runtime_error("entry PATH");
        // Compiler-relative resources belong to the public SDK. Preserve the
        // invoked basename, while exec and the loader still select the retained
        // compiler and its separate execution libraries above.
        std::vector<char *> execArgs;
        std::string reportedArgv0;
        char **childArgv = argv;
        std::vector<std::string> selectedArgs;
        const auto realDir = real.parent_path();
        if (argc > 0 && argv[0] && realDir.filename() == "compiler" &&
            realDir.parent_path().filename() == "libexec") {
            reportedArgv0 = (root / "bin" / fs::path(argv[0]).filename()).string();
            execArgs.assign(argv, argv + argc);
            execArgs[0] = reportedArgv0.data();
            execArgs.push_back(nullptr);
            childArgv = execArgs.data();
        }
        if (lines[2] == ".target-tools/tools/bin/hle") {
            selectedArgs = hleArguments(std::vector<std::string>(argv, argv + argc), root);
            execArgs.clear();
            for (auto &arg : selectedArgs) execArgs.push_back(arg.data());
            execArgs.push_back(nullptr);
            childArgv = execArgs.data();
        }
        execv(real.c_str(), childArgv);
        const int error = errno; std::perror("cjcj-sdk-entry exec"); return error == ENOENT ? 127 : 126;
#endif
    } catch (const std::exception &e) {
        std::fprintf(stderr, "cjcj-sdk-entry: %s\n", e.what()); return 126;
    }
}
