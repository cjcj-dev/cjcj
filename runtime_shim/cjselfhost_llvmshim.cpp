// Self-host LLVM FFI C-shim.
//
// Bridges LLVM C++ APIs that have NO LLVM-C (C ABI) equivalent, so the
// self-hosted Cangjie CodeGen can faithfully mirror the C++ compiler.
// Linked statically into the `cjc` executable (see packages/cjc/cjpm.toml
// link-option). Undefined LLVM symbols resolve against libLLVM-15.so, which
// cjc already links at runtime.
//
// Build: runtime_shim/build_shim.sh
//
// Entries (grow as more LLVM-C gaps surface during the port):
//   R-A': GlobalVariable::addAttribute(StringRef,StringRef)  -- no LLVM-C ABI.
//         C++ use: src/CodeGen/CJNative/EmitPackageIR.cpp:701  gv->addAttribute(GC_KLASS_ATTR)
//         GC_KLASS_ATTR = "CFileKlass"  (src/CodeGen/Utils/Constants.h:35)

#include <llvm-c/Core.h>
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Value.h"
#include "llvm/ADT/StringRef.h"

using namespace llvm;

// Mirror C++ `gv->addAttribute(Kind, Val)` (llvm/IR/GlobalVariable.h:239).
// Val may be empty (KLen/VLen are explicit lengths; no NUL assumption).
extern "C" void LLVMGlobalObjectAddStringAttribute(
        LLVMValueRef GV, const char *K, unsigned KLen, const char *V, unsigned VLen) {
    unwrap<GlobalVariable>(GV)->addAttribute(StringRef(K, KLen), StringRef(V, VLen));
}
