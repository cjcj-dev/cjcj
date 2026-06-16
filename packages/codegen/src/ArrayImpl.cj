package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprKind
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

public func GenerateRawArrayLiteralInit(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let rawArrayValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
    if (let Some(elementCGType) <- GetRawArrayElementCGType(rawArrayValue)) {
        var elementIdx: Int64 = 1
        while (elementIdx < chirExpr.GetNumOfOperands()) {
            let elementValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(elementIdx))
            let elementPtr = CreateRawArrayElementPointer(irBuilder, rawArrayValue, elementCGType, elementIdx - 1)
            irBuilder.CreateStore(elementValue.GetRawValue(), elementPtr)
            elementIdx++
        }
        return rawArrayValue.GetRawValue()
    }
    return LLVMNullValue()
}

public func GenerateRawArrayInitByValue(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() < 3) {
        return LLVMNullValue()
    }
    let rawArrayValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
    if (let Some(elementCGType) <- GetRawArrayElementCGType(rawArrayValue)) {
        let sizeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(1)).GetRawValue()
        let initValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(2)).GetRawValue()
        GenerateRawArrayFillLoop(irBuilder, rawArrayValue, elementCGType, sizeValue, initValue)
        return rawArrayValue.GetRawValue()
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

private func GetRawArrayElementCGType(rawArrayValue: CGValue): Option<CGType> {
    if (let Some(rawArrayCGType) <- rawArrayValue.GetCGType()) {
        return rawArrayCGType.GetPointerElementType()
    }
    return None
}

private func CreateRawArrayElementPointer(irBuilder: IRBuilder2, rawArrayValue: CGValue,
    elementCGType: CGType, elementIdx: Int64): LLVMValueRef {
    let indices = ArrayList<LLVMValueRef>()
    indices.add(unsafe { LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(elementIdx), 0) })
    return irBuilder.CreateGEP(elementCGType.GetLLVMType(), rawArrayValue.GetRawValue(), indices, name: "rawarray.elem")
}

private func GenerateRawArrayFillLoop(irBuilder: IRBuilder2, rawArrayValue: CGValue, elementCGType: CGType,
    sizeValue: LLVMValueRef, initValue: LLVMValueRef): Unit {
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        return
    }
    let parentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
    if (parentFunction.isNull()) {
        return
    }
    let loopCondBlock = irBuilder.CreateEntryBasicBlock(parentFunction, "arr.init.start")
    unsafe { LLVMMoveBasicBlockAfter(loopCondBlock, currentBlock) }
    let loopBodyBlock = irBuilder.CreateEntryBasicBlock(parentFunction, "arr.init.body")
    unsafe { LLVMMoveBasicBlockAfter(loopBodyBlock, loopCondBlock) }
    let loopEndBlock = irBuilder.CreateEntryBasicBlock(parentFunction, "arr.init.end")
    unsafe { LLVMMoveBasicBlockAfter(loopEndBlock, loopBodyBlock) }

    let indexSlot = irBuilder.CreateEntryAlloca(unsafe { LLVMTypeOf(sizeValue) }, name: "iterator")
    let zeroValue = unsafe { LLVMConstInt(LLVMTypeOf(sizeValue), 0u64, 0) }
    let oneValue = unsafe { LLVMConstInt(LLVMTypeOf(sizeValue), 1u64, 0) }
    irBuilder.CreateStore(zeroValue, indexSlot)
    irBuilder.CreateBr(loopCondBlock)

    irBuilder.SetInsertPoint(loopCondBlock)
    let currentIndex = irBuilder.CreateLoad(unsafe { LLVMTypeOf(sizeValue) }, indexSlot, name: "iterator")
    let hasElement = irBuilder.CreateICmp(LLVMIntPredicate.SLT, currentIndex, sizeValue, name: "iterator.size.cmp")
    irBuilder.CreateCondBr(hasElement, loopBodyBlock, loopEndBlock)

    irBuilder.SetInsertPoint(loopBodyBlock)
    let elementIndices = ArrayList<LLVMValueRef>()
    elementIndices.add(currentIndex)
    let elementPtr = irBuilder.CreateGEP(elementCGType.GetLLVMType(), rawArrayValue.GetRawValue(), elementIndices,
        name: "rawarray.elem")
    irBuilder.CreateStore(initValue, elementPtr)
    let nextIndex = irBuilder.CreateBinary(ExprKind.ADD, currentIndex, oneValue, name: "iterator.next")
    irBuilder.CreateStore(nextIndex, indexSlot)
    irBuilder.CreateBr(loopCondBlock)

    irBuilder.SetInsertPoint(loopEndBlock)
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
