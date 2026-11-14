#include <llvm-c/Core.h>
#include <cassert>
#include <cstdint>
#include <cstdio>
extern "C" LLVMTypeRef LLVMSelfhostArrayType64(LLVMTypeRef, uint64_t);
int main() {
    auto context = LLVMContextCreate();
    auto element = LLVMInt64TypeInContext(context);
    auto array = LLVMSelfhostArrayType64(element, 7);
    assert(LLVMGetTypeKind(array) == LLVMArrayTypeKind);
    assert(LLVMGetElementType(array) == element);
    assert(LLVMGetArrayLength(array) == 7);
    LLVMContextDispose(context);
    puts("SHIM_ARRAY_CONSUMER_REACHED");
}
