// Exercises the cjcj LLVM shim against every LLVM AddrSpaceCastOperator form
// used by generic payload source dispatch: instruction, constant expression,
// direct native view, and managed-native-managed nesting.
#include <llvm-c/Core.h>

#include <cstdio>

extern "C" int LLVMSelfhostIsAddrSpaceCastOperator(LLVMValueRef);
extern "C" LLVMValueRef LLVMSelfhostAddrSpaceCastOperatorGetOperand(LLVMValueRef);

namespace {
int Check(bool condition, int code, const char *message)
{
    if (!condition) {
        std::fprintf(stderr, "ADDRSPACECAST_OPERATOR_FAIL code=%d reason=%s\n", code, message);
        return code;
    }
    return 0;
}
} // namespace

int main()
{
    LLVMContextRef context = LLVMContextCreate();
    LLVMModuleRef module = LLVMModuleCreateWithNameInContext("addrspacecast-operator", context);
    LLVMTypeRef i8 = LLVMInt8TypeInContext(context);
    LLVMTypeRef native = LLVMPointerType(i8, 0);
    LLVMTypeRef managed = LLVMPointerType(i8, 1);
    LLVMTypeRef params[] = {native, managed};
    LLVMTypeRef functionType = LLVMFunctionType(LLVMVoidTypeInContext(context), params, 2, 0);
    LLVMValueRef function = LLVMAddFunction(module, "operator_shapes", functionType);
    LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(context, function, "entry");
    LLVMBuilderRef builder = LLVMCreateBuilderInContext(context);
    LLVMPositionBuilderAtEnd(builder, entry);

    LLVMValueRef nativeArg = LLVMGetParam(function, 0);
    LLVMValueRef managedArg = LLVMGetParam(function, 1);
    LLVMValueRef directView = LLVMBuildAddrSpaceCast(builder, nativeArg, managed, "direct.view");
    if (int rc = Check(LLVMSelfhostIsAddrSpaceCastOperator(directView) == 1, 1,
            "instruction not recognized")) {
        return rc;
    }
    if (int rc = Check(LLVMSelfhostAddrSpaceCastOperatorGetOperand(directView) == nativeArg, 2,
            "instruction operand mismatch")) {
        return rc;
    }

    LLVMValueRef nativeGlobal = LLVMAddGlobal(module, i8, "native.global");
    LLVMValueRef constantView = LLVMConstAddrSpaceCast(nativeGlobal, managed);
    if (int rc = Check(LLVMSelfhostIsAddrSpaceCastOperator(constantView) == 1, 3,
            "constant expression not recognized")) {
        return rc;
    }
    if (int rc = Check(LLVMSelfhostAddrSpaceCastOperatorGetOperand(constantView) == nativeGlobal, 4,
            "constant expression operand mismatch")) {
        return rc;
    }

    LLVMValueRef nativeRoundTrip = LLVMBuildAddrSpaceCast(builder, managedArg, native, "native.roundtrip");
    LLVMValueRef managedRoundTrip =
        LLVMBuildAddrSpaceCast(builder, nativeRoundTrip, managed, "managed.roundtrip");
    LLVMValueRef nested = LLVMSelfhostAddrSpaceCastOperatorGetOperand(managedRoundTrip);
    if (int rc = Check(LLVMSelfhostIsAddrSpaceCastOperator(nested) == 1, 5,
            "nested operator not recognized")) {
        return rc;
    }
    if (int rc = Check(LLVMSelfhostAddrSpaceCastOperatorGetOperand(nested) == managedArg, 6,
            "nested managed origin mismatch")) {
        return rc;
    }

    LLVMBuildRetVoid(builder);
    LLVMDisposeBuilder(builder);
    LLVMDisposeModule(module);
    LLVMContextDispose(context);
    std::puts("ADDRSPACECAST_OPERATOR_OK instruction=1 constant_expr=1 direct_native=1 nested_managed=1");
    return 0;
}
