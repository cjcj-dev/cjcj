package cangjie_compiler::codegen

import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprKind

public func HandleMemoryExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let kind = chirExpr.GetExprKind()
    if (kind == ExprKind.ALLOCATE || kind == ExprKind.ALLOCATE_WITH_EXCEPTION) {
        return GenerateAllocate(irBuilder, chirExpr)
    }
    if (kind == ExprKind.LOAD) {
        return GenerateLoad(irBuilder, chirExpr)
    }
    if (kind == ExprKind.STORE) {
        return GenerateStore(irBuilder, chirExpr)
    }
    if (kind == ExprKind.GET_ELEMENT_REF || kind == ExprKind.GET_ELEMENT_BY_NAME) {
        return GenerateGetElementRef(irBuilder, chirExpr)
    }
    if (kind == ExprKind.STORE_ELEMENT_REF || kind == ExprKind.STORE_ELEMENT_BY_NAME) {
        return GenerateStoreElementRef(irBuilder, chirExpr)
    }
    return LLVMNullValue()
}
