package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.GetElementByName
import cangjie_compiler::chir.GetElementRef
import cangjie_compiler::chir.LocalVar
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.StoreElementByName
import cangjie_compiler::chir.StoreElementRef
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value

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
    // CHIR Store operands are (value, location): operand 0 is the value being stored, operand 1
    // is the destination address (a Ref). See chir Store.GetValue()/GetLocation().
    let valueOperand = chirExpr.GetOperand(0)
    let addrOperand = chirExpr.GetOperand(1)
    if (ShouldSkipNoOpStore(valueOperand, addrOperand)) {
        return LLVMNullValue()
    }
    let value = irBuilder.GetCGModule().MaterializeValue(irBuilder, valueOperand)
    let addr = irBuilder.GetCGModule().MaterializeValue(irBuilder, addrOperand)
    return irBuilder.CreateStore(value.GetRawValue(), addr.GetRawValue())
}

public func GenerateGetElementRef(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let baseValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
    let indices = BuildElementIndices(irBuilder, chirExpr)
    if (indices.isEmpty() &&
        (chirExpr.GetExprKind() == ExprKind.GET_ELEMENT_REF || chirExpr.GetExprKind() == ExprKind.GET_ELEMENT_BY_NAME)) {
        return LLVMNullValue()
    }
    return CreateElementAddress(irBuilder, baseValue, indices, "gep")
}

public func GenerateStoreElementRef(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(storeElementRef) <- (chirExpr as StoreElementRef)) {
        let path = storeElementRef.GetPath()
        if (path.isEmpty()) {
            return LLVMNullValue()
        }
        if (ShouldSkipNoOpStore(storeElementRef.GetValue(), storeElementRef.GetLocation())) {
            return LLVMNullValue()
        }
        let storeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, storeElementRef.GetValue())
        let storePlace = irBuilder.GetCGModule().MaterializeValue(irBuilder, storeElementRef.GetLocation())
        let storeIndices = BuildStaticElementIndices(irBuilder, path)
        let storeAddr = CreateElementAddress(irBuilder, storePlace, storeIndices, "store.elem.addr")
        if (storeAddr.isNull()) {
            return LLVMNullValue()
        }
        return irBuilder.CreateStore(storeValue.GetRawValue(), storeAddr)
    }
    if (let Some(storeByName) <- (chirExpr as StoreElementByName)) {
        if (let Some(locationTy) <- storeByName.GetLocation().GetType()) {
            if (let Some(path) <- ResolveElementPathByNames(locationTy, storeByName.GetNames())) {
                if (ShouldSkipNoOpStore(storeByName.GetValue(), storeByName.GetLocation())) {
                    return LLVMNullValue()
                }
                let byNameValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, storeByName.GetValue())
                let byNamePlace = irBuilder.GetCGModule().MaterializeValue(irBuilder, storeByName.GetLocation())
                let byNameIndices = BuildStaticElementIndices(irBuilder, path)
                let byNameAddr = CreateElementAddress(irBuilder, byNamePlace, byNameIndices, "store.elem.addr")
                if (byNameAddr.isNull()) {
                    return LLVMNullValue()
                }
                return irBuilder.CreateStore(byNameValue.GetRawValue(), byNameAddr)
            }
        }
    }
    return LLVMNullValue()
}

private func ShouldSkipNoOpStore(value: Value, location: Value): Bool {
    if (IsConstantNullClassValue(value)) {
        return true
    }
    if (let Some(localLocation) <- (location as LocalVar)) {
        if (localLocation.IsRetValue()) {
            if (let Some(valueTy) <- value.GetType()) {
                return valueTy.IsUnit()
            }
        }
    }
    return false
}

private func IsConstantNullClassValue(value: Value): Bool {
    if (let Some(localValue) <- (value as LocalVar)) {
        if (let Some(ownerExpr) <- localValue.GetExpr()) {
            if (ownerExpr.IsConstantNull()) {
                if (let Some(valueTy) <- value.GetType()) {
                    return valueTy.IsClass()
                }
            }
        }
    }
    return false
}

private func BuildElementIndices(irBuilder: IRBuilder2, chirExpr: Expression): ArrayList<LLVMValueRef> {
    if (let Some(staticElementRef) <- (chirExpr as GetElementRef)) {
        return BuildStaticElementIndices(irBuilder, staticElementRef.GetPath())
    }
    if (let Some(elementByName) <- (chirExpr as GetElementByName)) {
        if (let Some(locationTy) <- elementByName.GetLocation().GetType()) {
            if (let Some(path) <- ResolveElementPathByNames(locationTy, elementByName.GetNames())) {
                return BuildStaticElementIndices(irBuilder, path)
            }
        }
        return ArrayList<LLVMValueRef>()
    }
    let dynamicIndices = ArrayList<LLVMValueRef>()
    var idx: Int64 = 1
    while (idx < chirExpr.GetNumOfOperands()) {
        dynamicIndices.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(idx)).GetRawValue())
        idx++
    }
    return dynamicIndices
}

private func BuildStaticElementIndices(irBuilder: IRBuilder2, path: ArrayList<UInt64>): ArrayList<LLVMValueRef> {
    let indices = ArrayList<LLVMValueRef>()
    if (path.isEmpty()) {
        return indices
    }
    indices.add(LLVMConstI32(irBuilder, 0u64))
    for (pathItem in path) {
        indices.add(LLVMConstI32(irBuilder, pathItem))
    }
    return indices
}

private func LLVMConstI32(irBuilder: IRBuilder2, value: UInt64): LLVMValueRef {
    return unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), value, 0) }
}

private func CreateElementAddress(irBuilder: IRBuilder2, baseValue: CGValue, indices: ArrayList<LLVMValueRef>,
    name: String): LLVMValueRef {
    if (indices.isEmpty()) {
        return baseValue.GetRawValue()
    }
    if (let Some(baseType) <- baseValue.GetCGType()) {
        if (let Some(elementType) <- baseType.GetPointerElementType()) {
            return irBuilder.CreateGEP(elementType.GetLLVMType(), baseValue.GetRawValue(), indices, name: name)
        }
        return irBuilder.CreateGEP(baseType.GetLLVMType(), baseValue.GetRawValue(), indices, name: name)
    }
    return LLVMNullValue()
}

private func ResolveElementPathByNames(baseTy: Type, names: ArrayList<String>): Option<ArrayList<UInt64>> {
    if (names.isEmpty()) {
        return None
    }
    let path = ArrayList<UInt64>()
    var currentTy = baseTy.StripAllRefs()
    for (name in names) {
        if (let Some(customTy) <- (currentTy as CustomType)) {
            let fields = customTy.GetCustomTypeDef().GetAllInstanceVars()
            var fieldIdx: Int64 = 0
            var found = false
            while (fieldIdx < fields.size) {
                let fieldInfo = fields[fieldIdx]
                if (fieldInfo.name == name || fieldInfo.rawMangledName == name) {
                    path.add(UInt64(fieldIdx))
                    currentTy = fieldInfo.ty.StripAllRefs()
                    found = true
                    break
                }
                fieldIdx++
            }
            if (!found) {
                return None
            }
        } else {
            return None
        }
    }
    return Some(path)
}
