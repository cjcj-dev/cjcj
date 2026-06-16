package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.Type

public func GenerateLoad(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
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

public func GenerateRawArrayAllocate(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() != 1) {
        return LLVMNullValue()
    }
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        if (let Some(rawArrayTy) <- FindRawArrayType(resultTy)) {
            let lengthValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0)).GetRawValue()
            return GenerateCheckedRawArrayAllocate(irBuilder, rawArrayTy, lengthValue)
        }
    }
    return LLVMNullValue()
}

private func GenerateCheckedRawArrayAllocate(irBuilder: IRBuilder2, rawArrayTy: RawArrayType,
    lengthValue: LLVMValueRef): LLVMValueRef {
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        return irBuilder.AllocateArray(rawArrayTy, lengthValue)
    }
    let parentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
    if (parentFunction.isNull()) {
        return irBuilder.AllocateArray(rawArrayTy, lengthValue)
    }
    let throwBlock = irBuilder.CreateEntryBasicBlock(parentFunction, "arr.alloc.throw")
    unsafe { LLVMMoveBasicBlockAfter(throwBlock, currentBlock) }
    let bodyBlock = irBuilder.CreateEntryBasicBlock(parentFunction, "arr.alloc.body")
    unsafe { LLVMMoveBasicBlockAfter(bodyBlock, throwBlock) }
    let zeroValue = unsafe { LLVMConstInt(LLVMTypeOf(lengthValue), 0u64, 1) }
    let isValidLength = irBuilder.CreateICmp(LLVMIntPredicate.SGE, lengthValue, zeroValue,
        name: "arr.alloc.size.valid")
    irBuilder.CreateCondBr(isValidLength, bodyBlock, throwBlock)

    irBuilder.SetInsertPoint(throwBlock)
    irBuilder.CreateNegativeArraySizeException()

    irBuilder.SetInsertPoint(bodyBlock)
    return irBuilder.AllocateArray(rawArrayTy, lengthValue)
}

private func FindRawArrayType(ty: Type): Option<RawArrayType> {
    if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
        return rawArrayTy
    }
    let stripped = ty.StripAllRefs()
    if (let Some(rawArrayTy) <- (stripped as RawArrayType)) {
        return rawArrayTy
    }
    return None
}

public func GenerateStore(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() < 2) {
        return LLVMNullValue()
    }
    let addr = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
    let value = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(1))
    return irBuilder.CreateStore(value.GetRawValue(), addr.GetRawValue())
}

public func GenerateGetElementRef(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
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
    return LLVMNullValue()
}
