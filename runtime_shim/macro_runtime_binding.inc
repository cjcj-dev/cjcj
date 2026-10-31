// Validate the existing ELF producer's dynamic search path before dlmopen can
// run constructors. Use LLVM's ELF reader; no private link_map access, ELF
// rewriting, sidecar identity, or process-wide loader environment changes.
#include <cstring>
#include <string>
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Object/Binary.h"
#include "llvm/Object/ELFObjectFile.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/FileSystem.h"

static bool MacroSameDirectory(llvm::StringRef path, llvm::StringRef expected)
{
    llvm::SmallString<256> actual;
    return !llvm::sys::fs::real_path(path, actual) && actual == expected;
}

template <class ELFT>
static int CheckMacroRPath(const llvm::object::ELFObjectFile<ELFT> &object,
    llvm::StringRef image, llvm::StringRef runtime)
{
    const auto &elf = object.getELFFile();
    auto entries = elf.dynamicEntries();
    if (!entries) { llvm::consumeError(entries.takeError()); return -1; }
    uint64_t strings = 0, size = 0, offset = 0;
    bool found = false;
    for (const auto &entry : *entries) {
        if (entry.d_tag == llvm::ELF::DT_NULL) break;
        // RUNPATH cannot provide the inherited target dependency search that
        // this macro namespace requires. Do not accept RPATH+RUNPATH either.
        if (entry.d_tag == llvm::ELF::DT_RUNPATH) return -1;
        if (entry.d_tag == llvm::ELF::DT_STRTAB) strings = entry.d_un.d_ptr;
        if (entry.d_tag == llvm::ELF::DT_STRSZ) size = entry.d_un.d_val;
        if (entry.d_tag == llvm::ELF::DT_RPATH) {
            if (found) return -1;
            found = true;
            offset = entry.d_un.d_val;
        }
    }
    if (!found || !strings || !size || offset >= size) return -1;
    auto mapped = elf.toMappedAddr(strings);
    if (!mapped) { llvm::consumeError(mapped.takeError()); return -1; }
    if (size > static_cast<uint64_t>(elf.end() - *mapped)) return -1;
    const char *start = reinterpret_cast<const char *>(*mapped) + offset;
    const char *end = static_cast<const char *>(std::memchr(start, 0, size - offset));
    if (!end) return -1;
    llvm::StringRef rpath(start, end - start);
    llvm::SmallVector<llvm::StringRef, 4> paths;
    rpath.split(paths, ':', -1, true);
    if (paths.empty()) return -1;
    // The first entry must bind the current logical SDK. This also accepts a
    // normally linked $ORIGIN path after relocation of the macro with its SDK.
    std::string first = paths.front().str();
    for (llvm::StringRef token : {llvm::StringRef("${ORIGIN}"), llvm::StringRef("$ORIGIN")}) {
        if (llvm::StringRef(first).startswith(token)) {
            first = (llvm::sys::path::parent_path(image) + llvm::StringRef(first).drop_front(token.size())).str();
            break;
        }
    }
    return MacroSameDirectory(first, runtime) ? 0 : -1;
}

extern "C" int CJSelfhostCheckMacroRuntimeBinding(const char *image, const char *runtimeDirectory)
{
    if (!image || !runtimeDirectory) return -1;
    llvm::SmallString<256> realImage, realRuntime;
    if (llvm::sys::fs::real_path(image, realImage) ||
        llvm::sys::fs::real_path(runtimeDirectory, realRuntime)) return -1;
    // Standard macro DSOs are selected from the current SDK runtime directory,
    // not the imported user-macro cache. Their normal std producer uses ORIGIN.
    if (llvm::sys::path::parent_path(realImage) == realRuntime &&
        llvm::sys::path::filename(realImage).startswith("libcangjie-std-")) return 0;
    auto binary = llvm::object::createBinary(realImage);
    if (!binary) { llvm::consumeError(binary.takeError()); return -1; }
    auto *raw = binary->getBinary();
#define CHECK_MACRO_ELF(TYPE) \
    if (auto *elf = llvm::dyn_cast<llvm::object::ELFObjectFile<llvm::object::TYPE>>(raw)) \
        return CheckMacroRPath(*elf, realImage, realRuntime)
    CHECK_MACRO_ELF(ELF64LE);
    CHECK_MACRO_ELF(ELF32LE);
    CHECK_MACRO_ELF(ELF64BE);
    CHECK_MACRO_ELF(ELF32BE);
#undef CHECK_MACRO_ELF
    return -1;
}
