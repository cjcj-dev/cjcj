#include <llvm-c/Core.h>

#include <cstdio>

#include "llvm/IR/Instruction.h"
#include "llvm/IR/Operator.h"

extern "C" LLVMContextRef LLVMGetValueContext(LLVMValueRef Val);
extern "C" int LLVMCanValueUseFastMathFlags(LLVMValueRef V);
extern "C" void LLVMSetFastMathFlags(LLVMValueRef FPMathInst, unsigned FMF);

enum {
    LLVMFastMathAllowReassoc = (1 << 0),
    LLVMFastMathNoNaNs = (1 << 1),
};

static int gFails = 0;

static void check(const char *name, int ok, const char *detail)
{
    if (ok) {
        std::printf("CHECK %s PASS\n", name);
        return;
    }
    std::printf("CHECK %s FAIL %s\n", name, detail);
    gFails++;
}

int main()
{
    LLVMContextRef ctx = LLVMContextCreate();
    LLVMModuleRef module = LLVMModuleCreateWithNameInContext("gap", ctx);
    LLVMBuilderRef builder = LLVMCreateBuilderInContext(ctx);
    LLVMTypeRef f32 = LLVMFloatTypeInContext(ctx);
    LLVMTypeRef i32 = LLVMInt32TypeInContext(ctx);
    LLVMTypeRef fnTy = LLVMFunctionType(f32, nullptr, 0, 0);
    LLVMValueRef fn = LLVMAddFunction(module, "f", fnTy);
    LLVMBasicBlockRef block = LLVMAppendBasicBlockInContext(ctx, fn, "entry");
    LLVMPositionBuilderAtEnd(builder, block);
    LLVMValueRef one = LLVMConstReal(f32, 1.0);
    LLVMValueRef fadd = LLVMBuildFAdd(builder, one, one, "fa");
    LLVMValueRef iadd = LLVMBuildAdd(builder, LLVMConstInt(i32, 1, 0), LLVMConstInt(i32, 2, 0), "ia");

    LLVMContextRef got = LLVMGetValueContext(fadd);
    char ctxDetail[96];
    std::snprintf(ctxDetail, sizeof(ctxDetail), "got=%p ctx=%p", static_cast<void *>(got), static_cast<void *>(ctx));
    check("LLVMGetValueContext", got == ctx, ctxDetail);

    int canFadd = LLVMCanValueUseFastMathFlags(fadd);
    int canIadd = LLVMCanValueUseFastMathFlags(iadd);
    char canDetail[96];
    std::snprintf(canDetail, sizeof(canDetail), "fadd=%d iadd=%d", canFadd, canIadd);
    check("LLVMCanValueUseFastMathFlags", canFadd != 0 && canIadd == 0, canDetail);

    LLVMSetFastMathFlags(fadd, LLVMFastMathAllowReassoc | LLVMFastMathNoNaNs);
    llvm::FastMathFlags flags = llvm::unwrap<llvm::Instruction>(fadd)->getFastMathFlags();
    int setOk = flags.allowReassoc() && flags.noNaNs() && !flags.noInfs() && !flags.noSignedZeros() &&
        !flags.allowReciprocal() && !flags.allowContract() && !flags.approxFunc();
    char setDetail[160];
    std::snprintf(setDetail, sizeof(setDetail), "reassoc=%d nnan=%d ninf=%d nsz=%d arcp=%d contract=%d afn=%d",
        flags.allowReassoc(), flags.noNaNs(), flags.noInfs(), flags.noSignedZeros(), flags.allowReciprocal(),
        flags.allowContract(), flags.approxFunc());
    check("LLVMSetFastMathFlags", setOk, setDetail);

    std::printf("FAILS=%d\n", gFails);
    LLVMDisposeBuilder(builder);
    LLVMDisposeModule(module);
    LLVMContextDispose(ctx);
    return gFails == 0 ? 0 : 1;
}
