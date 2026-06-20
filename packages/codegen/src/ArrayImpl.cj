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
    if (let Some(rawArrayTy) <- GetRawArrayType(rawArrayValue)) {
        let elementCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), rawArrayTy.GetElementType())
        var elementIdx: Int64 = 1
        while (elementIdx < chirExpr.GetNumOfOperands()) {
            let elementValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(elementIdx))
            let indexValue = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(elementIdx - 1), 0)
            }
            let elementPtr = CreateRawArrayElementPointer(irBuilder, rawArrayValue, rawArrayTy, indexValue)
            StoreRawArrayElement(irBuilder, rawArrayValue.GetRawValue(), elementCGType, elementValue.GetRawValue(),
                elementPtr)
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
    if (let Some(rawArrayTy) <- GetRawArrayType(rawArrayValue)) {
        let sizeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(1)).GetRawValue()
        let initValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(2)).GetRawValue()
        GenerateRawArrayFillLoop(irBuilder, rawArrayValue, rawArrayTy, sizeValue, initValue)
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

private func GetRawArrayType(rawArrayValue: CGValue): Option<RawArrayType> {
    if (let Some(rawArrayCGType) <- rawArrayValue.GetCGType()) {
        return FindRawArrayType(rawArrayCGType.GetOriginal())
    }
    return None
}

private func CreateRawArrayElementPointer(irBuilder: IRBuilder2, rawArrayValue: CGValue,
    rawArrayTy: RawArrayType, elementIdx: LLVMValueRef): LLVMValueRef {
    let arrayLayoutType = CGArrayType.GenerateArrayLayoutType(irBuilder.GetCGModule(), rawArrayTy)
    let payload = irBuilder.GetPayloadFromObject(rawArrayValue.GetRawValue())
    let typedPayload = irBuilder.CreateBitCast(payload,
        unsafe { LLVMPointerType(arrayLayoutType, 1u32) }, name: "rawarray.payload")
    let indices = ArrayList<LLVMValueRef>()
    indices.add(LLVMConstI32(irBuilder, 0u64))
    indices.add(LLVMConstI32(irBuilder, 1u64))
    indices.add(elementIdx)
    return irBuilder.CreateGEP(arrayLayoutType, typedPayload, indices, name: "rawarray.elem")
}

private func GenerateRawArrayFillLoop(irBuilder: IRBuilder2, rawArrayValue: CGValue, rawArrayTy: RawArrayType,
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
    let elementPtr = CreateRawArrayElementPointer(irBuilder, rawArrayValue, rawArrayTy, currentIndex)
    let elementCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), rawArrayTy.GetElementType())
    StoreRawArrayElement(irBuilder, rawArrayValue.GetRawValue(), elementCGType, initValue, elementPtr)
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
    return irBuilder.CreateStore(StoreValueForAddress(irBuilder, value, addr), addr.GetRawValue())
}

private func IsPointerLLVMValue(value: LLVMValueRef): Bool {
    let rawTy = unsafe { LLVMTypeOf(value) }
    return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 12
}

private func IsPointerLLVMType(ty: LLVMTypeRef): Bool {
    return !ty.isNull() && unsafe { LLVMGetTypeKind(ty) } == 12
}

private func StoreValueForAddress(irBuilder: IRBuilder2, value: CGValue, addr: CGValue): LLVMValueRef {
    let raw = value.GetRawValue()
    if (!IsPointerLLVMValue(raw)) {
        return raw
    }
    if (let Some(valueCGType) <- value.GetCGType()) {
        if (!valueCGType.IsReference() && valueCGType.GetOriginal().StripAllRefs().IsStruct()) {
            return irBuilder.CreateLoad(valueCGType.GetLLVMType(), raw, name: "store.value")
        }
    }
    if (let Some(addrCGType) <- addr.GetCGType()) {
        if (let Some(destCGType) <- addrCGType.GetPointerElementType()) {
            let destTy = destCGType.GetLLVMType()
            if (IsPointerLLVMType(destTy)) {
                return irBuilder.CreateBitCast(raw, destTy, name: "store.ptr.cast")
            }
        }
    }
    return raw
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
        return StoreElementValue(irBuilder, storePlace, storeValue, storeAddr)
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
                return StoreElementValue(irBuilder, byNamePlace, byNameValue, byNameAddr)
            }
        }
    }
    return LLVMNullValue()
}

private func StoreElementValue(irBuilder: IRBuilder2, baseValue: CGValue, elementValue: CGValue,
    elementPtr: LLVMValueRef): LLVMValueRef {
    if (let Some(baseType) <- baseValue.GetCGType()) {
        if (let Some(rawArrayTy) <- FindRawArrayType(baseType.GetOriginal())) {
            let elementCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), rawArrayTy.GetElementType())
            return StoreRawArrayElement(irBuilder, baseValue.GetRawValue(), elementCGType, elementValue.GetRawValue(),
                elementPtr)
        }
    }
    return irBuilder.CreateStore(elementValue.GetRawValue(), elementPtr)
}

private func StoreRawArrayElement(irBuilder: IRBuilder2, rawArrayValue: LLVMValueRef, elementCGType: CGType,
    elementValue: LLVMValueRef, elementPtr: LLVMValueRef): LLVMValueRef {
    if (elementCGType.IsReference()) {
        return irBuilder.CallGCWrite(elementValue, rawArrayValue, elementPtr)
    }
    return irBuilder.CreateStore(elementValue, elementPtr)
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
            if (let Some(rawArrayTy) <- (baseType.GetOriginal().StripAllRefs() as RawArrayType)) {
                let layoutType = CGArrayType.GenerateArrayLayoutType(irBuilder.GetCGModule(), rawArrayTy)
                let payload = irBuilder.GetPayloadFromObject(baseValue.GetRawValue())
                let typedPayload = irBuilder.CreateBitCast(payload,
                    unsafe { LLVMPointerType(layoutType, 1u32) }, name: name + ".payload")
                let arrayIndices = ArrayList<LLVMValueRef>()
                arrayIndices.add(LLVMConstI32(irBuilder, 0u64))
                arrayIndices.add(LLVMConstI32(irBuilder, 1u64))
                let start = if (indices.size > 1) { 1 } else { 0 }
                var idx = start
                while (idx < indices.size) {
                    arrayIndices.add(indices[idx])
                    idx++
                }
                return irBuilder.CreateGEP(layoutType, typedPayload, arrayIndices, name: name)
            }
            if (baseType.GetOriginal().StripAllRefs().IsClass()) {
                let layoutType = elementType.GetLayoutType()
                let payload = irBuilder.GetPayloadFromObject(baseValue.GetRawValue())
                let typedPayload = irBuilder.CreateBitCast(payload,
                    unsafe { LLVMPointerType(layoutType, 1u32) }, name: name + ".payload")
                return irBuilder.CreateGEP(layoutType, typedPayload, indices, name: name)
            }
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
            let fieldTypes = customTy.GetInstantiatedMemberTys()
            var fieldIdx: Int64 = 0
            var found = false
            while (fieldIdx < fields.size) {
                let fieldInfo = fields[fieldIdx]
                if (fieldInfo.name == name || fieldInfo.rawMangledName == name) {
                    path.add(UInt64(fieldIdx))
                    currentTy = if (fieldIdx < fieldTypes.size) {
                        fieldTypes[fieldIdx].StripAllRefs()
                    } else {
                        fieldInfo.ty.StripAllRefs()
                    }
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
