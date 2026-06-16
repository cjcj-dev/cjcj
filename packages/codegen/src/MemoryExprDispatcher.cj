package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprKind

public func HandleMemoryExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let kind = chirExpr.GetExprKind()
    if (kind == ExprKind.ALLOCATE || kind == ExprKind.ALLOCATE_WITH_EXCEPTION) {
        if (let Some(resultTy) <- chirExpr.GetResultType()) {
            let cgType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
            return irBuilder.CreateEntryAlloca(cgType, name: "alloca")
        }
        return LLVMNullValue()
    }
    if (kind == ExprKind.LOAD) {
        if (chirExpr.GetNumOfOperands() == 0) {
            return LLVMNullValue()
        }
        let addr = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
        if (let Some(addrType) <- addr.GetCGType()) {
            if (let Some(pointerElementType) <- addrType.GetPointerElementType()) {
                return irBuilder.CreateLoad(pointerElementType.GetLLVMType(), addr.GetRawValue(), name: "load")
            }
        }
        if (let Some(resultTy) <- chirExpr.GetResultType()) {
            return irBuilder.CreateLoad(CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType(),
                addr.GetRawValue(), name: "load")
        }
        return LLVMNullValue()
    }
    if (kind == ExprKind.STORE) {
        if (chirExpr.GetNumOfOperands() < 2) {
            return LLVMNullValue()
        }
        let addr = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
        let value = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(1))
        return irBuilder.CreateStore(value.GetRawValue(), addr.GetRawValue())
    }
    if (kind == ExprKind.GET_ELEMENT_REF || kind == ExprKind.GET_ELEMENT_BY_NAME) {
        if (chirExpr.GetNumOfOperands() == 0) {
            return LLVMNullValue()
        }
        let baseValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
        let indices = ArrayList<LLVMValueRef>()
        var idx: Int64 = 1
        while (idx < chirExpr.GetNumOfOperands()) {
            indices.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(idx)).GetRawValue())
            idx++
        }
        if (let Some(baseType) <- baseValue.GetCGType()) {
            if (let Some(elementType) <- baseType.GetPointerElementType()) {
                return irBuilder.CreateGEP(elementType.GetLLVMType(), baseValue.GetRawValue(), indices, name: "gep")
            }
            return irBuilder.CreateGEP(baseType.GetLLVMType(), baseValue.GetRawValue(), indices, name: "gep")
        }
    }
    return LLVMNullValue()
}
