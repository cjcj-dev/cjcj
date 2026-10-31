#include "llvm/Analysis/ValueTracking.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/raw_ostream.h"
#include <string>
#include <set>
#include <vector>
using namespace llvm;

// Read the actual compiler module and DataLayout. No hand-authored IR and no
// dependency on the name or instruction sequence of the coercion temporary.
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    LLVMContext context;
    SMDiagnostic diagnostic;
    auto module = parseIRFile(argv[1], diagnostic, context);
    if (!module) { diagnostic.print(argv[0], errs()); return 2; }
    if (module->getTargetTriple().find("aarch64") != 0) {
        errs() << "Expected backend AArch64 module, got " << module->getTargetTriple() << '\n';
        return 2;
    }
    const auto &layout = module->getDataLayout();
    unsigned functions = 0, accesses = 0, unknown = 0, violations = 0;
    const std::string prefix = argv[2];
    // Follow the public wrapper into its actual body and constructors. The
    // backend can represent calls as statepoints, whose callee is an operand.
    std::set<Function *> reachable;
    std::vector<Function *> pending;
    for (auto &function : *module)
        if (!function.isDeclaration() && function.getName().startswith(prefix)) pending.push_back(&function);
    while (!pending.empty()) {
        auto *function = pending.back(); pending.pop_back();
        if (!reachable.insert(function).second) continue;
        for (auto &block : *function) for (auto &instruction : block)
            for (auto &operand : instruction.operands())
                if (auto *callee = dyn_cast<Function>(operand->stripPointerCasts()))
                    if (!callee->isDeclaration()) pending.push_back(callee);
    }
    for (auto &function : *module) {
        if (!reachable.count(&function)) continue;
        ++functions;
        unsigned localAccesses = 0, localViolations = 0;
        auto check = [&](Value *pointer, uint64_t bytes, Instruction &instruction) {
            int64_t offset = 0;
            auto *base = GetPointerBaseWithConstantOffset(pointer, offset, layout);
            // Relocation preserves the designated object and its byte offset.
            // Ask LLVM for the original derived pointer; do not guess its size
            // from the relocated i8* result type.
            while (auto *relocation = dyn_cast<GCRelocateInst>(base)) {
                int64_t originalOffset = 0;
                base = GetPointerBaseWithConstantOffset(relocation->getDerivedPtr(), originalOffset, layout);
                offset += originalOffset;
            }
            uint64_t size = 0;
            bool known = false;
            if (auto *allocation = dyn_cast<AllocaInst>(base)) {
                if (auto *count = dyn_cast<ConstantInt>(allocation->getArraySize())) {
                    size = layout.getTypeAllocSize(allocation->getAllocatedType()).getFixedValue() * count->getZExtValue();
                    known = true;
                }
            } else if (auto *global = dyn_cast<GlobalVariable>(base)) {
                // Constant VArray initializers are real global objects too.
                size = layout.getTypeAllocSize(global->getValueType()).getFixedValue();
                known = true;
            } else if (auto *argument = dyn_cast<Argument>(base)) {
                auto *type = argument->getType()->getPointerElementType();
                if (type->isSized()) { size = layout.getTypeAllocSize(type).getFixedValue(); known = true; }
            }
            ++accesses; ++localAccesses;
            if (!known) { ++unknown; errs() << "UNKNOWN " << function.getName() << ": " << instruction << '\n'; return; }
            if (offset < 0 || uint64_t(offset) > size || bytes > size - uint64_t(offset)) {
                ++violations; ++localViolations;
                outs() << "OOB " << function.getName() << " object=" << size << " offset=" << offset << " access=" << bytes << " " << instruction << '\n';
            }
        };
        for (auto &block : function) for (auto &instruction : block) {
            if (auto *load = dyn_cast<LoadInst>(&instruction)) check(load->getPointerOperand(), layout.getTypeStoreSize(load->getType()).getFixedValue(), instruction);
            else if (auto *store = dyn_cast<StoreInst>(&instruction)) check(store->getPointerOperand(), layout.getTypeStoreSize(store->getValueOperand()->getType()).getFixedValue(), instruction);
            else if (auto *memory = dyn_cast<MemIntrinsic>(&instruction)) {
                auto *length = dyn_cast<ConstantInt>(memory->getLength());
                if (!length) { ++unknown; continue; }
                check(memory->getRawDest(), length->getZExtValue(), instruction);
                if (auto *copy = dyn_cast<MemTransferInst>(memory)) check(copy->getRawSource(), length->getZExtValue(), instruction);
            }
        }
        outs() << "FUNCTION " << function.getName() << " accesses=" << localAccesses << " violations=" << localViolations << '\n';
    }
    outs() << "SUMMARY functions=" << functions << " accesses=" << accesses << " unknown=" << unknown << " violations=" << violations << '\n';
    if (!functions || unknown) return 2;
    return violations ? 1 : 0;
}
