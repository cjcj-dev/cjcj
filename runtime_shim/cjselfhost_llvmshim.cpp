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
//   CGFunction::AddZeroInitForStructWithRefField support:
//         src/CodeGen/CGFunction.cpp:262-274, 329-350.

#include <llvm-c/Core.h>

#include "llvm/ADT/StringRef.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/CFG.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Instruction.h"
#include "llvm/IR/Use.h"
#include "llvm/IR/User.h"
#include "llvm/IR/Value.h"

using namespace llvm;

namespace {
struct LLVMSelfhostLoopInfoState {
    DominatorTree domTree;
    LoopInfoBase<BasicBlock, Loop> loopInfo;

    explicit LLVMSelfhostLoopInfoState(Function& function) : domTree(function), loopInfo()
    {
        loopInfo.analyze(domTree);
    }
};
} // namespace

using LLVMSelfhostLoopInfoRef = LLVMSelfhostLoopInfoState*;
using LLVMSelfhostLoopRef = Loop*;

// Mirror C++ `gv->addAttribute(Kind, Val)` (llvm/IR/GlobalVariable.h:239).
// Val may be empty (KLen/VLen are explicit lengths; no NUL assumption).
extern "C" void LLVMGlobalObjectAddStringAttribute(
        LLVMValueRef GV, const char *K, unsigned KLen, const char *V, unsigned VLen) {
    unwrap<GlobalVariable>(GV)->addAttribute(StringRef(K, KLen), StringRef(V, VLen));
}

extern "C" LLVMBasicBlockRef LLVMSelfhostGetNearestCommonAncestorOfBasicBlocks(
        LLVMBasicBlockRef *BBs, unsigned Count)
{
    if (Count == 0) {
        return nullptr;
    }
    auto *pre = unwrap(BBs[0]);
    auto *function = pre->getParent();
    DominatorTree dt(*function);
    for (unsigned idx = 1; idx < Count; ++idx) {
        auto *cur = unwrap(BBs[idx]);
        pre = dt.findNearestCommonDominator(pre, cur);
    }
    return wrap(pre);
}

extern "C" LLVMSelfhostLoopInfoRef LLVMSelfhostCreateLoopInfo(LLVMValueRef Fn)
{
    return new LLVMSelfhostLoopInfoState(*unwrap<Function>(Fn));
}

extern "C" void LLVMSelfhostDisposeLoopInfo(LLVMSelfhostLoopInfoRef Info)
{
    delete Info;
}

extern "C" LLVMSelfhostLoopRef LLVMSelfhostLoopInfoGetLoopFor(
        LLVMSelfhostLoopInfoRef Info, LLVMBasicBlockRef BB)
{
    return Info->loopInfo.getLoopFor(unwrap(BB));
}

extern "C" LLVMSelfhostLoopRef LLVMSelfhostLoopGetOutermostLoop(LLVMSelfhostLoopRef LoopRef)
{
    return LoopRef->getOutermostLoop();
}

extern "C" LLVMBasicBlockRef LLVMSelfhostLoopGetHeader(LLVMSelfhostLoopRef LoopRef)
{
    return wrap(LoopRef->getHeader());
}

extern "C" int LLVMSelfhostLoopContainsBasicBlock(LLVMSelfhostLoopRef LoopRef, LLVMBasicBlockRef BB)
{
    return LoopRef->contains(unwrap(BB)) ? 1 : 0;
}

extern "C" unsigned LLVMSelfhostGetBasicBlockPredecessorCount(LLVMBasicBlockRef BB)
{
    return pred_size(unwrap(BB));
}

extern "C" void LLVMSelfhostGetBasicBlockPredecessors(LLVMBasicBlockRef BB, LLVMBasicBlockRef *Preds)
{
    unsigned idx = 0;
    for (auto *pred : predecessors(unwrap(BB))) {
        Preds[idx++] = wrap(pred);
    }
}

extern "C" int LLVMSelfhostInstructionComesBefore(LLVMValueRef Inst, LLVMValueRef Other)
{
    return unwrap<Instruction>(Inst)->comesBefore(unwrap<Instruction>(Other)) ? 1 : 0;
}

extern "C" LLVMUseRef LLVMSelfhostGetFirstUse(LLVMValueRef Val)
{
    auto *value = unwrap(Val);
    auto iter = value->use_begin();
    if (iter == value->use_end()) {
        return nullptr;
    }
    return wrap(&*iter);
}

extern "C" LLVMUseRef LLVMSelfhostGetNextUse(LLVMUseRef UseRef)
{
    auto *next = unwrap(UseRef)->getNext();
    if (next) {
        return wrap(next);
    }
    return nullptr;
}

extern "C" LLVMValueRef LLVMSelfhostGetUserInstruction(LLVMUseRef UseRef)
{
    return wrap(dyn_cast<Instruction>(unwrap(UseRef)->getUser()));
}
