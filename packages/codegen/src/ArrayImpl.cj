package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.Constant
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Box as ChirBox
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
import cangjie_compiler::utils.CJC_ASSERT

private let LLVM_STRUCT_TYPE_KIND: Int32 = 10
private let LLVM_ARRAY_TYPE_KIND: Int32 = 11
private let LLVM_VECTOR_TYPE_KIND: Int32 = 13
private let LLVM_SCALABLE_VECTOR_TYPE_KIND: Int32 = 17

public func GenerateLoad(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    if (let Some(genericFieldLoad) <- TryLoadGenericClassFieldWithReadBarrier(irBuilder, chirExpr)) {
        return genericFieldLoad
    }
    let addr = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0))
    if (let Some(addrType) <- addr.GetCGType()) {
        if (let Some(pointerElementType) <- addrType.GetPointerElementType()) {
            if (let Some(readBarrier) <- TryGenerateGCReadForLoad(irBuilder, chirExpr, pointerElementType, addr)) {
                return readBarrier
            }
            if (let Some(loaded) <- TryLoadClassFieldWithReadBarrier(irBuilder, chirExpr, addr, pointerElementType)) {
                return loaded
            }
            if (let Some(staticRead) <- TryGenerateGCStaticReadForLoad(irBuilder, pointerElementType, addr)) {
                return staticRead
            }
            return irBuilder.CreateLoad(pointerElementType.GetLLVMType(), addr.GetRawValue(), name: "load")
        }
    }
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        return irBuilder.CreateLoad(CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType(),
            addr.GetRawValue(), name: "load")
    }
    return LLVMNullValue()
}

private func TryLoadGenericClassFieldWithReadBarrier(irBuilder: IRBuilder2,
    loadExpr: Expression): Option<LLVMValueRef> {
    let local = (loadExpr.GetOperand(0) as LocalVar) ?? return None
    let ownerExpr = local.GetExpr() ?? return None
    let (base, fieldTy, fieldPath) = if (let Some(elementRef) <- (ownerExpr as GetElementRef)) {
        let path = elementRef.GetPath()
        let (resolvedBase, resolvedTy) = ResolveLoadBaseAndFieldType(elementRef.GetLocation(), Some(path))
        (resolvedBase, resolvedTy, Some(path))
    } else if (let Some(elementByName) <- (ownerExpr as GetElementByName)) {
        let path = ResolveLoadElementPathByNames(elementByName.GetLocation(), elementByName.GetNames())
        let (resolvedBase, resolvedTy) = ResolveLoadBaseAndFieldType(elementByName.GetLocation(), path)
        (resolvedBase, resolvedTy, path)
    } else {
        return None
    }
    if (!IsGenericField(fieldTy)) {
        return None
    }
    let baseValue = irBuilder.GetCGModule().GetMappedCGValue(base)
    let baseCGType = baseValue.GetCGType() ?? return None
    if (!baseCGType.GetOriginal().StripAllRefs().IsClass() ||
        !IsAddressSpacePointer(baseValue.GetRawValue(), 1u32)) {
        return None
    }
    let resultTy = loadExpr.GetResultType() ?? (fieldTy ?? return None)
    let elementType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
    let actualPath = fieldPath ?? return None
    if (actualPath.isEmpty()) {
        return None
    }
    let fieldAddr = irBuilder.CreateGEP(baseValue, actualPath, name: "field.addr").GetRawValue()
    return Some(irBuilder.LoadGenericFieldValue(baseValue.GetRawValue(), fieldAddr, elementType,
        baseCGType.GetOriginal(), fieldTy))
}

private func TryLoadClassFieldWithReadBarrier(irBuilder: IRBuilder2, loadExpr: Expression, addr: CGValue,
    elementType: CGType): Option<LLVMValueRef> {
    if (!ShouldUseClassFieldReadBarrier(irBuilder, elementType) || !IsAddressSpacePointer(addr.GetRawValue(), 1u32)) {
        return None
    }
    let local = (loadExpr.GetOperand(0) as LocalVar) ?? return None
    let ownerExpr = local.GetExpr() ?? return None
    let (base, fieldTy, fieldPath) = if (let Some(elementRef) <- (ownerExpr as GetElementRef)) {
        let path = elementRef.GetPath()
        let (resolvedBase, resolvedTy) = ResolveLoadBaseAndFieldType(elementRef.GetLocation(), Some(path))
        (resolvedBase, resolvedTy, Some(path))
    } else if (let Some(elementByName) <- (ownerExpr as GetElementByName)) {
        let path = ResolveLoadElementPathByNames(elementByName.GetLocation(), elementByName.GetNames())
        let (resolvedBase, resolvedTy) = ResolveLoadBaseAndFieldType(elementByName.GetLocation(), path)
        (resolvedBase, resolvedTy, path)
    } else {
        return None
    }
    let baseValue = irBuilder.GetCGModule().GetMappedCGValue(base)
    let baseCGType = baseValue.GetCGType() ?? return None
    if (!baseCGType.GetOriginal().StripAllRefs().IsClass()) {
        return None
    }
    if (!IsAddressSpacePointer(baseValue.GetRawValue(), 1u32)) {
        return None
    }
    if (IsGenericField(fieldTy)) {
        let actualPath = fieldPath ?? return None
        if (actualPath.isEmpty()) {
            return None
        }
        let genericAddr = irBuilder.CreateGEP(baseValue, actualPath, name: "field.addr").GetRawValue()
        return Some(irBuilder.LoadGenericFieldValue(baseValue.GetRawValue(), genericAddr, elementType,
            baseCGType.GetOriginal(), fieldTy))
    }
    let raw = irBuilder.CallGCReadRef(baseValue.GetRawValue(), addr.GetRawValue())
    return Some(irBuilder.CreateBitCast(raw, elementType.GetLLVMType(), name: "load.gcread.cast"))
}

private func ResolveLoadBaseAndFieldType(base: Value, path: Option<ArrayList<UInt64>>): (Value, Option<Type>) {
    let fieldTy = if (let Some(elementPath) <- path) {
        if (let Some(locationTy) <- base.GetType()) {
            ResolveElementTypeByPath(locationTy, elementPath)
        } else {
            Option<Type>.None
        }
    } else {
        Option<Type>.None
    }
    return (base, fieldTy)
}

private func ResolveLoadElementPathByNames(base: Value, names: ArrayList<String>): Option<ArrayList<UInt64>> {
    if (let Some(locationTy) <- base.GetType()) {
        return ResolveElementPathByNames(locationTy, names)
    }
    return None
}

private func ShouldUseClassFieldReadBarrier(irBuilder: IRBuilder2, elementType: CGType): Bool {
    let stripped = elementType.GetOriginal().StripAllRefs()
    if (stripped.IsGeneric() || stripped.IsReferenceType() || elementType.GetSize().isNone()) {
        return true
    }
    if (let Some(enumCGType) <- (CGType.GetOrCreate(irBuilder.GetCGModule(), stripped) as CGEnumType)) {
        return enumCGType.IsOptionLikeRef()
    }
    return false
}

private func TryGenerateGCReadForLoad(irBuilder: IRBuilder2, chirExpr: Expression, elementType: CGType,
    addr: CGValue): Option<LLVMValueRef> {
    if (!elementType.IsReference()) {
        return None
    }
    let addrOperand = chirExpr.GetOperand(0)
    if (let Some(local) <- addrOperand.AsLocalVar()) {
        if (let Some(ownerExpr) <- local.GetExpr()) {
            if (let Some(getElementRef) <- (ownerExpr as GetElementRef)) {
                let base = getElementRef.GetLocation()
                if (let Some(baseTy) <- base.GetType()) {
                    if (IsManagedObjectElementBase(baseTy) &&
                        IsManagedReferenceField(irBuilder, ResolveElementTypeByPath(baseTy, getElementRef.GetPath()))) {
                        let baseValue = irBuilder.GetCGModule().GetMappedCGValue(base)
                        return Some(irBuilder.CallGCReadRef(baseValue.GetRawValue(), addr.GetRawValue()))
                    }
                }
            }
        }
    }
    return None
}

private func TryGenerateGCStaticReadForLoad(irBuilder: IRBuilder2, elementType: CGType,
    addr: CGValue): Option<LLVMValueRef> {
    if (!irBuilder.IsGlobalVariableBasePtr(addr.GetRawValue()) || !IsBareGCRefLLVMType(elementType.GetLLVMType())) {
        return None
    }
    return Some(irBuilder.CallGCReadStaticRef(addr.GetRawValue()))
}

private func IsManagedObjectElementBase(ty: Type): Bool {
    let strippedTy = ty.StripAllRefs()
    return strippedTy.IsClass() || strippedTy.IsBox()
}

public func GenerateRawArrayAllocate(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() != 1) {
        return LLVMNullValue()
    }
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        if (let Some(rawArrayTy) <- FindRawArrayType(resultTy)) {
            let length = chirExpr.GetOperand(0)
            let lengthValue = irBuilder.GetCGModule().GetMappedCGValue(length).GetRawValue()
            if (let Some(lengthLocal) <- (length as LocalVar)) {
                if (let Some(lengthExpr) <- lengthLocal.GetExpr()) {
                    if (lengthExpr.IsConstant()) {
                        let constExpr = (lengthExpr as Constant).getOrThrow()
                        if (constExpr.GetSignedIntLitVal() >= 0) {
                            return irBuilder.AllocateArray(rawArrayTy, lengthValue)
                        }
                    }
                }
            }
            return GenerateCheckedRawArrayAllocate(irBuilder, rawArrayTy, lengthValue)
        }
    }
    return LLVMNullValue()
}

public func GenerateRawArrayLiteralInit(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let rawArrayValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0))
    if (let Some(rawArrayTy) <- GetRawArrayType(rawArrayValue)) {
        let elementCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), rawArrayTy.GetElementType())
        var elementIdx: Int64 = 1
        while (elementIdx < chirExpr.GetNumOfOperands()) {
            let elementValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(elementIdx))
            let indexValue = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(elementIdx - 1), 0)
            }
            let elementPtr = CreateRawArrayElementPointer(irBuilder, rawArrayValue, rawArrayTy, indexValue)
            StoreRawArrayElement(irBuilder, rawArrayValue.GetRawValue(), elementCGType, elementValue, elementPtr)
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
    let rawArrayValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0))
    if (let Some(rawArrayTy) <- GetRawArrayType(rawArrayValue)) {
        let sizeValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(1)).GetRawValue()
        let initValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(2)).GetRawValue()
        GenerateRawArrayFillLoop(irBuilder, rawArrayValue, rawArrayTy, sizeValue, initValue)
        return rawArrayValue.GetRawValue()
    }
    return LLVMNullValue()
}

private func GenerateCheckedRawArrayAllocate(irBuilder: IRBuilder2, rawArrayTy: RawArrayType,
    lengthValue: LLVMValueRef): LLVMValueRef {
    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>(
        [GenNameForBB("arr.alloc.throw"), GenNameForBB("arr.alloc.body")]))
    CJC_ASSERT(blocks.size == 2)
    let throwBlock = blocks[0]
    let bodyBlock = blocks[1]
    let zeroValue = unsafe { LLVMConstInt(LLVMTypeOf(lengthValue), 0u64, 0) }
    let isValidLength = irBuilder.CreateICmp(LLVMIntPredicate.SGE, lengthValue, zeroValue,
        name: "arr.alloc.size.valid")
    let expectedValidLength = irBuilder.GenerateCallExpectFunction(isValidLength, irBuilder.GetTrue())
    irBuilder.CreateCondBr(expectedValidLength, bodyBlock, throwBlock)

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
    StoreRawArrayElement(irBuilder, rawArrayValue.GetRawValue(), elementCGType, CGValue(initValue, elementCGType),
        elementPtr)
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
    let value = irBuilder.GetCGModule().GetMappedCGValue(valueOperand)
    let addr = irBuilder.GetCGModule().GetMappedCGValue(addrOperand)
    if (let Some(boxRetStore) <- TryGenerateBoxRetValueStore(irBuilder, chirExpr, valueOperand, addrOperand, value, addr)) {
        return boxRetStore
    }
    return CreateTypedStoreForAddress(irBuilder, value, addr)
}

private func TryGenerateBoxRetValueStore(irBuilder: IRBuilder2, chirExpr: Expression, valueOperand: Value,
    addrOperand: Value, value: CGValue, addr: CGValue): Option<LLVMValueRef> {
    let addrLocal = (addrOperand as LocalVar) ?? return None
    if (!addrLocal.IsRetValue()) {
        return None
    }
    let topLevelFunc = chirExpr.GetTopLevelFunc() ?? return None
    let overrideSrcFuncType = topLevelFunc.GetOverrideSrcFuncType() ?? return None
    let addrTy = addrOperand.GetType() ?? return None
    let addrDerefTy = addrTy.StripAllRefs()
    if (!addrDerefTy.IsBox()) {
        return None
    }
    let typeArgs = addrDerefTy.GetTypeArgs()
    if (typeArgs.isEmpty()) {
        return None
    }

    let overrideSrcRetType = overrideSrcFuncType.GetReturnType()
    let retAddrType = irBuilder.GetCGContext().GetCHIRBuilder().context.GetRefTy(overrideSrcRetType)
    let retAddrCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), retAddrType)
    let retValueCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), overrideSrcRetType)
    let needBoxExpr = overrideSrcRetType.IsGeneric() || retValueCGType.GetSize().isNone()
    let storeValCGType = if (overrideSrcRetType.IsGeneric()) { retValueCGType } else { retAddrCGType }
    var valueToStore = value.GetRawValue()
    if (!needBoxExpr) {
        if (let Some(valueLocal) <- (valueOperand as LocalVar)) {
            if (let Some(ownerExpr) <- valueLocal.GetExpr()) {
                if (let Some(boxExpr) <- (ownerExpr as ChirBox)) {
                    valueToStore = irBuilder.GetCGModule().GetMappedCGValue(boxExpr.GetSourceValue()).GetRawValue()
                }
            }
        }
    }

    let typedValue = CGValue(valueToStore, storeValCGType, isSRetArg: value.IsSRetArg())
    let typedAddr = CGValue(addr.GetRawValue(), retAddrCGType, isSRetArg: addr.IsSRetArg())
    return Some(irBuilder.CreateStore(typedValue, typedAddr, typeArgs[0]))
}

public func CreateTypedStoreForAddress(irBuilder: IRBuilder2, value: CGValue, addr: CGValue,
    boxType!: Option<Type> = None): LLVMValueRef {
    if (let Some(genericStore) <- irBuilder.TryCreateGenericStore(value, addr, boxType: boxType)) {
        return genericStore
    }
    if (let Some(memberStore) <- irBuilder.TryCreateManagedMemberStore(value, addr)) {
        return memberStore
    }
    if (let Some(valueCGType) <- value.GetCGType()) {
        let addrCGType = addr.GetCGType().getOrThrow()
        let destCGType = addrCGType.GetPointerElementType().getOrThrow()
        if (!destCGType.GetOriginal().IsRef() && valueCGType.GetOriginal().IsRef()) {
            let valueElementCGType = valueCGType.GetPointerElementType().getOrThrow()
            if (valueElementCGType.GetSize().isSome()) {
                if (destCGType.GetSize().isNone()) {
                    let dataPtr = irBuilder.GetPayloadFromObject(addr.GetRawValue())
                    let size = irBuilder.GetLayoutSize32(valueCGType.GetOriginal(), valueCGType)
                    let args = ArrayList<LLVMValueRef>()
                    args.add(addr.GetRawValue())
                    args.add(dataPtr)
                    args.add(value.GetRawValue())
                    args.add(size)
                    return irBuilder.CallGCWriteAgg(valueCGType.GetLayoutType(), args)
                }
            } else {
                CJC_ASSERT(destCGType.GetSize().isNone())
                if (IsAddressSpacePointer(addr.GetRawValue(), 1u32) &&
                    IsAddressSpacePointer(value.GetRawValue(), 0u32)) {
                    let size = irBuilder.GetSize32(valueCGType.GetOriginal(), valueCGType)
                    return irBuilder.CallGCWriteGenericPayload(addr.GetRawValue(), value.GetRawValue(), size)
                }
                let typeInfo = irBuilder.CreateTypeInfo(boxType ?? valueCGType.GetOriginal())
                return irBuilder.CallAssignGeneric(addr.GetRawValue(), value.GetRawValue(), typeInfo)
            }
        }
    }
    if (let Some(structPtrStore) <- TryStoreStructPtrValueForAddress(irBuilder, value, addr)) {
        return structPtrStore
    }
    let storedValue = StoreValueForAddress(irBuilder, value, addr)
    if (let Some(staticAggregateStore) <- TryStoreStaticAggregateValueForAddress(irBuilder, storedValue, addr)) {
        return staticAggregateStore
    }
    if (ShouldUseGCStaticWriteBarrier(irBuilder, addr) && ShouldUseGCStaticRefWriteBarrier(addr)) {
        return irBuilder.CallGCWriteStaticRef(storedValue, addr.GetRawValue())
    }
    if (let Some(valueCGType) <- value.GetCGType()) {
        if (let Some(addrCGType) <- addr.GetCGType()) {
            if (valueCGType.IsVArrayPtrType() && addrCGType.IsVArrayPtrType()) {
                let valueType = valueCGType.GetPointerElementType().getOrThrow().GetLLVMType()
                let size = unsafe {
                    LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw),
                        irBuilder.GetCGModule().GetTypeSize(valueType), 0)
                }
                let align = irBuilder.GetCGModule().GetABITypeAlignment(valueType)
                return irBuilder.CreateMemCpy(addr.GetRawValue(), align, value.GetRawValue(), align, size)
            }
        }
    }
    return irBuilder.CreateStore(storedValue, addr.GetRawValue())
}

private func IsPointerLLVMValue(value: LLVMValueRef): Bool {
    let rawTy = unsafe { LLVMTypeOf(value) }
    return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 12
}

private func IsPointerLLVMType(ty: LLVMTypeRef): Bool {
    return !ty.isNull() && unsafe { LLVMGetTypeKind(ty) } == 12
}

private func IsBareGCRefLLVMType(ty: LLVMTypeRef): Bool {
    return IsPointerLLVMType(ty) && unsafe { LLVMGetPointerAddressSpace(ty) } == 1u32
}

private func ShouldUseGCStaticWriteBarrier(irBuilder: IRBuilder2, addr: CGValue): Bool {
    if (!irBuilder.IsGlobalVariableBasePtr(addr.GetRawValue())) {
        return false
    }
    let addrCGType = addr.GetCGType() ?? return false
    let destCGType = addrCGType.GetPointerElementType() ?? return false
    return irBuilder.IsLLVMTypeContainsRef(destCGType.GetLLVMType())
}

private func ShouldUseGCStaticRefWriteBarrier(addr: CGValue): Bool {
    let addrCGType = addr.GetCGType() ?? return false
    let destCGType = addrCGType.GetPointerElementType() ?? return false
    return IsBareGCRefLLVMType(destCGType.GetLLVMType())
}

private func StoreValueForAddress(irBuilder: IRBuilder2, value: CGValue, addr: CGValue): LLVMValueRef {
    let raw = value.GetRawValue()
    if (!IsPointerLLVMValue(raw)) {
        return raw
    }
    if (let Some(valueCGType) <- value.GetCGType()) {
        let valueTy = valueCGType.GetOriginal().StripAllRefs()
        if (!valueCGType.GetOriginal().IsRef() && (valueTy.IsStruct() || valueTy.IsTuple() || valueTy.IsVArray())) {
            return irBuilder.CreateLoad(valueCGType.GetLLVMType(), raw, name: "store.value")
        }
    }
    if (let Some(addrCGType) <- addr.GetCGType()) {
        if (let Some(destCGType) <- addrCGType.GetPointerElementType()) {
            let destTy = destCGType.GetLLVMType()
            let valueCGType = value.GetCGType() ?? return raw
            if (ShouldLoadInlineValueForAddressStore(valueCGType, destCGType)) {
                if (ShouldLoadInlineObjectPayloadForAddressStore(valueCGType)) {
                    let payload = irBuilder.GetPayloadFromObject(raw)
                    let payloadPtr = irBuilder.CreateBitCast(payload,
                        unsafe { LLVMPointerType(destCGType.GetLLVMType(), 1u32) }, name: "store.ref.payload")
                    if (IsBareGCRefLLVMType(destCGType.GetLLVMType())) {
                        return irBuilder.CallGCReadRef(raw, payloadPtr)
                    }
                    return irBuilder.CreateLoad(destCGType.GetLLVMType(), payloadPtr, name: "store.ref.payload.value")
                }
                return irBuilder.CreateLoad(destCGType.GetLLVMType(), raw, name: "store.ref.value")
            }
            if (destCGType.IsVArrayType()) {
                return irBuilder.CreateLoad(destTy, raw, name: "store.value")
            }
            if (IsPointerLLVMType(destTy)) {
                return irBuilder.CreateBitCast(raw, destTy, name: "store.ptr.cast")
            }
        }
    }
    return raw
}

private func ShouldLoadInlineValueForAddressStore(valueCGType: CGType, destCGType: CGType): Bool {
    if (!valueCGType.GetOriginal().IsRef() || destCGType.GetOriginal().IsRef() || destCGType.GetSize().isNone()) {
        return false
    }
    if (IsBareGCRefLLVMType(destCGType.GetLLVMType())) {
        return false
    }
    let destTy = destCGType.GetOriginal().StripAllRefs()
    if (destTy.IsCPointer() || destTy.IsCString() || destTy.IsCFunc()) {
        return false
    }
    let valueElementCGType = valueCGType.GetPointerElementType() ?? return false
    let valueElementTy = valueElementCGType.GetOriginal().StripAllRefs()
    if (valueElementTy.IsCPointer() || valueElementTy.IsCString() || valueElementTy.IsCFunc()) {
        return false
    }
    return valueElementTy.IsEqual(destTy)
}

private func ShouldLoadInlineObjectPayloadForAddressStore(valueCGType: CGType): Bool {
    let valueTy = valueCGType.GetOriginal().StripAllRefs()
    if (valueTy.IsRawArray() || valueTy.IsClass() || valueTy.IsBox() || valueTy.IsString()) {
        return true
    }
    let valueElementCGType = valueCGType.GetPointerElementType() ?? return false
    return !(valueElementCGType.IsStructType() || valueElementCGType.IsVArrayType())
}

private func TryStoreStructPtrValueForAddress(irBuilder: IRBuilder2, value: CGValue,
    addr: CGValue): Option<LLVMValueRef> {
    let raw = value.GetRawValue()
    if (!IsPointerLLVMValue(raw)) {
        return None
    }
    let valueCGType = value.GetCGType() ?? return None
    let addrCGType = addr.GetCGType() ?? return None
    let destCGType = addrCGType.GetPointerElementType() ?? return None
    if (!destCGType.IsStructType()) {
        return None
    }
    let valueTy = valueCGType.GetOriginal().StripAllRefs()
    let pointerBackedEnumValue = if (let Some(enumCGType) <- (valueCGType as CGEnumType)) {
        enumCGType.IsOptionLikeNonRef()
    } else {
        false
    }
    if (!(valueCGType.IsStructPtrType() || valueTy.IsString() ||
        (!valueCGType.IsReference() && (valueTy.IsStruct() || valueTy.IsTuple() || valueTy.IsVArray())) ||
        pointerBackedEnumValue)) {
        return None
    }
    let fieldSize = if (let Some(size) <- destCGType.GetSize()) { size } else { 0 }
    let fieldSizeValue = unsafe {
        LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(fieldSize), 0)
    }
    let align = irBuilder.GetCGModule().GetABITypeAlignment(destCGType.GetLLVMType())
    let source = ReadManagedAggregateSourceIfNeeded(irBuilder, raw, destCGType, fieldSizeValue)
    if (irBuilder.IsGlobalVariableBasePtr(addr.GetRawValue()) &&
        irBuilder.IsLLVMTypeContainsRef(destCGType.GetLLVMType())) {
        return Some(CallGCWriteStaticStruct(irBuilder, addr.GetRawValue(), source, fieldSizeValue,
            destCGType.GetLLVMType()))
    }
    if (IsAddressSpacePointer(addr.GetRawValue(), 1u32) && irBuilder.IsLLVMTypeContainsRef(destCGType.GetLLVMType())) {
        return Some(irBuilder.CallGCWriteStruct(addr.GetRawValue(), addr.GetRawValue(), source, fieldSizeValue,
            destCGType.GetOriginal().ToString()))
    }
    return Some(irBuilder.CreateMemCpy(addr.GetRawValue(), align, source, align, fieldSizeValue))
}

private func TryStoreStaticAggregateValueForAddress(irBuilder: IRBuilder2, storedValue: LLVMValueRef,
    addr: CGValue): Option<LLVMValueRef> {
    if (!ShouldUseGCStaticWriteBarrier(irBuilder, addr) || ShouldUseGCStaticRefWriteBarrier(addr)) {
        return None
    }
    let addrCGType = addr.GetCGType() ?? return None
    let destCGType = addrCGType.GetPointerElementType() ?? return None
    let storedType = unsafe { LLVMTypeOf(storedValue) }
    var source = storedValue
    if (!IsPointerLLVMType(storedType)) {
        let kind = unsafe { LLVMGetTypeKind(storedType) }
        if (kind != LLVM_STRUCT_TYPE_KIND && kind != LLVM_ARRAY_TYPE_KIND && kind != LLVM_VECTOR_TYPE_KIND &&
            kind != LLVM_SCALABLE_VECTOR_TYPE_KIND) {
            return None
        }
        source = irBuilder.CreateEntryAlloca(destCGType.GetLLVMType(), name: "gcwrite.static.agg.tmp")
        let _ = irBuilder.CreateStore(storedValue, source)
    }
    let fieldSize = if (let Some(size) <- destCGType.GetSize()) { size } else { 0 }
    let fieldSizeValue = unsafe {
        LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(fieldSize), 0)
    }
    return Some(CallGCWriteStaticStruct(irBuilder, addr.GetRawValue(), source, fieldSizeValue, destCGType.GetLLVMType()))
}

private func CallGCWriteStaticStruct(irBuilder: IRBuilder2, dest: LLVMValueRef, source: LLVMValueRef,
    size: LLVMValueRef, aggType: LLVMTypeRef): LLVMValueRef {
    CJC_ASSERT(!aggType.isNull() && unsafe { LLVMGetTypeKind(aggType) } == LLVM_STRUCT_TYPE_KIND)
    let i64Type = unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
    let moduleHandle = irBuilder.GetCGModule().GetLLVMModule() ?? return LLVMNullValue()
    return unsafe {
        LLVMSelfhostCreateGCWriteStaticAgg(irBuilder.GetBuilder().raw, moduleHandle.raw, aggType, dest, source, size,
            i64Type)
    }
}

public func GenerateGetElementRef(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let baseValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0))
    if (let Some(staticElementRef) <- (chirExpr as GetElementRef)) {
        let path = staticElementRef.GetPath()
        if (path.isEmpty()) {
            return LLVMNullValue()
        }
        return irBuilder.CreateGEP(baseValue, path, name: "gep").GetRawValue()
    }
    if (let Some(elementByName) <- (chirExpr as GetElementByName)) {
        if (let Some(locationTy) <- elementByName.GetLocation().GetType()) {
            if (let Some(path) <- ResolveElementPathByNames(locationTy, elementByName.GetNames())) {
                if (path.isEmpty()) {
                    return LLVMNullValue()
                }
                return irBuilder.CreateGEP(baseValue, path, name: "gep").GetRawValue()
            }
        }
        return LLVMNullValue()
    }
    let indices = BuildElementIndices(irBuilder, chirExpr)
    if (indices.isEmpty()) {
        return LLVMNullValue()
    }
    return CreateElementAddress(irBuilder, baseValue, indices, "gep")
}

public func GenerateStoreElementRef(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(storeElementRef) <- (chirExpr as StoreElementRef)) {
        let path = storeElementRef.GetPath()
        let rhs = storeElementRef.GetValue()
        let lhs = storeElementRef.GetLocation()
        let locationTy = lhs.GetType().getOrThrow()
        CJC_ASSERT(locationTy.IsRef() && !path.isEmpty())
        let storeValue = irBuilder.GetCGModule().GetMappedCGValue(rhs)
        let storePlace = irBuilder.GetCGModule().GetMappedCGValue(lhs)
        let srcCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), rhs.GetType().getOrThrow())
        if (srcCGType.GetSize().isNone() && IsThisArgOfStructMethod(rhs)) {
            let typeInfoOfSrc = irBuilder.CreateTypeInfo(srcCGType.GetOriginal())
            let size = irBuilder.GetLayoutSize32(srcCGType.GetOriginal(), srcCGType)
            let parameters = ArrayList<LLVMValueRef>()
            parameters.add(typeInfoOfSrc)
            parameters.add(size)
            let tmp = irBuilder.CallClassIntrinsicAlloc(parameters)
            let payloadPtr = irBuilder.GetPayloadFromObject(tmp)
            if (irBuilder.IsLLVMTypeContainsRef(srcCGType.GetLLVMType())) {
                let args = ArrayList<LLVMValueRef>()
                args.add(tmp)
                args.add(payloadPtr)
                args.add(storeValue.GetRawValue())
                args.add(size)
                return irBuilder.CallGCWriteAgg(srcCGType.GetLayoutType(), args)
            }
            return irBuilder.CreateMemCpy(payloadPtr, 0u32, storeValue.GetRawValue(), 0u32, size)
        }
        if (ShouldSkipNoOpStore(rhs, lhs)) {
            return LLVMNullValue()
        }
        let storeAddr = irBuilder.CreateGEP(storePlace, path, name: "store.elem.addr").GetRawValue()
        if (rhs.TestAttr(Attribute.FOREIGN)) {
            AddFnAttr(storeValue.GetRawValue(), CJ2C_ATTR)
        }
        let fieldTy = ResolveElementTypeByPath(locationTy, path)
        return StoreElementValue(irBuilder, storePlace, storeValue, storeAddr, fieldTy)
    }
    if (let Some(storeByName) <- (chirExpr as StoreElementByName)) {
        if (let Some(locationTy) <- storeByName.GetLocation().GetType()) {
            if (let Some(path) <- ResolveElementPathByNames(locationTy, storeByName.GetNames())) {
                if (ShouldSkipNoOpStore(storeByName.GetValue(), storeByName.GetLocation())) {
                    return LLVMNullValue()
                }
                let byNameValue = irBuilder.GetCGModule().GetMappedCGValue(storeByName.GetValue())
                let byNamePlace = irBuilder.GetCGModule().GetMappedCGValue(storeByName.GetLocation())
                let byNameAddr = irBuilder.CreateGEP(byNamePlace, path, name: "store.elem.addr").GetRawValue()
                if (byNameAddr.isNull()) {
                    return LLVMNullValue()
                }
                return StoreElementValue(irBuilder, byNamePlace, byNameValue, byNameAddr,
                    ResolveElementTypeByPath(locationTy, path))
            }
        }
    }
    return LLVMNullValue()
}

private func StoreElementValue(irBuilder: IRBuilder2, baseValue: CGValue, elementValue: CGValue,
    elementPtr: LLVMValueRef, fieldTy: Option<Type>): LLVMValueRef {
    let baseObject = irBuilder.GetTrackedManagedBase(elementPtr) ?? baseValue.GetRawValue()
    if (let Some(baseType) <- baseValue.GetCGType()) {
        if (IsManagedObjectElementBase(baseType.GetOriginal()) && IsGenericField(fieldTy)) {
            return irBuilder.StoreGenericMemberValue(baseObject, elementPtr, elementValue,
                baseType.GetOriginal(), fieldTy)
        }
    }
    if (let Some(genericStore) <- TryStoreGenericElementValue(irBuilder, elementValue, elementPtr, fieldTy)) {
        return genericStore
    }
    if (let Some(fieldType) <- fieldTy) {
        if (IsAggregateFieldType(irBuilder, fieldType)) {
            return StoreAggregateElementValue(irBuilder, baseValue, elementValue, elementPtr, fieldType)
        }
    }
    let rawElementValue = StoreElementRawValue(irBuilder, elementValue)
    if (let Some(baseType) <- baseValue.GetCGType()) {
        if (let Some(rawArrayTy) <- FindRawArrayType(baseType.GetOriginal())) {
            let elementCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), rawArrayTy.GetElementType())
            return StoreRawArrayElement(irBuilder, baseValue.GetRawValue(), elementCGType, elementValue, elementPtr)
        }
        if (IsManagedObjectElementBase(baseType.GetOriginal())) {
            if (IsManagedReferenceField(irBuilder, fieldTy)) {
                return irBuilder.CallGCWrite(rawElementValue, baseObject, elementPtr)
            }
        }
    }
    if (ShouldUseObjectFieldWriteBarrier(irBuilder, baseValue, elementValue, elementPtr)) {
        return irBuilder.CallGCWrite(rawElementValue, baseObject, elementPtr)
    }
    return irBuilder.CreateStore(rawElementValue, elementPtr)
}

private func TryStoreGenericElementValue(irBuilder: IRBuilder2, elementValue: CGValue, elementPtr: LLVMValueRef,
    fieldTy: Option<Type>): Option<LLVMValueRef> {
    let genericFieldTy = (fieldTy ?? return None).StripAllRefs()
    if (!genericFieldTy.IsGeneric()) {
        return None
    }
    let refTy = irBuilder.GetCGContext().GetCHIRBuilder().context.GetRefTy(genericFieldTy)
    let dest = CGValue(elementPtr, CGType.GetOrCreate(irBuilder.GetCGModule(), refTy))
    return irBuilder.TryCreateGenericStore(elementValue, dest)
}

private func IsGenericField(fieldTy: Option<Type>): Bool {
    if (let Some(ty) <- fieldTy) {
        return ty.StripAllRefs().IsGeneric()
    }
    return false
}

private func IsAggregateFieldType(irBuilder: IRBuilder2, fieldTy: Type): Bool {
    let stripped = fieldTy.StripAllRefs()
    let fieldCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), stripped)
    if (fieldCGType.IsStructType() || fieldCGType.IsVArrayType()) {
        return true
    }
    return false
}

private func StoreAggregateElementValue(irBuilder: IRBuilder2, baseValue: CGValue, elementValue: CGValue,
    elementPtr: LLVMValueRef, fieldTy: Type): LLVMValueRef {
    let fieldCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), fieldTy.StripAllRefs())
    let rawElementValue = elementValue.GetRawValue()
    let fieldSize = if (let Some(size) <- fieldCGType.GetSize()) { size } else { 0 }
    let fieldSizeValue = unsafe {
        LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(fieldSize), 0)
    }
    let align = irBuilder.GetCGModule().GetABITypeAlignment(fieldCGType.GetLLVMType())
    var source = rawElementValue
    if (!IsPointerLLVMValue(rawElementValue)) {
        if (irBuilder.IsLLVMTypeContainsRef(fieldCGType.GetLLVMType()) &&
            (irBuilder.IsGlobalVariableBasePtr(elementPtr) || IsAddressSpacePointer(elementPtr, 1u32))) {
            source = irBuilder.CreateEntryAlloca(fieldCGType, name: "store.elem.agg")
            irBuilder.CreateStore(rawElementValue, source)
        } else {
            return irBuilder.CreateStore(rawElementValue, elementPtr)
        }
    } else {
        source = ReadManagedAggregateSourceIfNeeded(irBuilder, rawElementValue, fieldCGType, fieldSizeValue)
    }
    if (irBuilder.IsGlobalVariableBasePtr(elementPtr) && irBuilder.IsLLVMTypeContainsRef(fieldCGType.GetLLVMType())) {
        return CallGCWriteStaticStruct(irBuilder, elementPtr, source, fieldSizeValue, fieldCGType.GetLLVMType())
    }
    if (IsAddressSpacePointer(elementPtr, 1u32) && irBuilder.IsLLVMTypeContainsRef(fieldCGType.GetLLVMType())) {
        let baseObject = irBuilder.GetTrackedManagedBase(elementPtr) ?? baseValue.GetRawValue()
        return irBuilder.CallGCWriteStruct(baseObject, elementPtr, source, fieldSizeValue,
            fieldCGType.GetOriginal().ToString())
    }
    return irBuilder.CreateMemCpy(elementPtr, align, source, align, fieldSizeValue)
}

private func StoreElementRawValue(irBuilder: IRBuilder2, value: CGValue): LLVMValueRef {
    let raw = value.GetRawValue()
    if (!IsPointerLLVMValue(raw)) {
        return raw
    }
    if (let Some(valueCGType) <- value.GetCGType()) {
        let valueTy = valueCGType.GetOriginal().StripAllRefs()
        if (!valueCGType.IsReference() && (valueTy.IsStruct() || valueTy.IsTuple() || valueTy.IsVArray())) {
            return irBuilder.CreateLoad(valueCGType.GetLLVMType(), raw, name: "store.elem.value")
        }
    }
    return raw
}

private func ShouldUseObjectFieldWriteBarrier(irBuilder: IRBuilder2, baseValue: CGValue, elementValue: CGValue,
    elementPtr: LLVMValueRef): Bool {
    if (!IsAddressSpacePointer(baseValue.GetRawValue(), 1u32) || !IsAddressSpacePointer(elementPtr, 1u32)) {
        return false
    }
    if (let Some(elementCGType) <- elementValue.GetCGType()) {
        if (elementCGType.IsReference() || IsOptionLikeRefValue(irBuilder, elementCGType)) {
            return true
        }
        if (elementCGType.GetSize().isNone()) {
            return true
        }
    }
    return false
}

private func IsOptionLikeRefValue(irBuilder: IRBuilder2, elementCGType: CGType): Bool {
    if (let Some(enumCGType) <- (CGType.GetOrCreate(irBuilder.GetCGModule(),
        elementCGType.GetOriginal().StripAllRefs()) as CGEnumType)) {
        return enumCGType.IsOptionLikeRef()
    }
    return false
}

private func IsAddressSpacePointer(value: LLVMValueRef, addressSpace: UInt32): Bool {
    let rawTy = unsafe { LLVMTypeOf(value) }
    return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 12 &&
        unsafe { LLVMGetPointerAddressSpace(rawTy) } == addressSpace
}

private func StoreRawArrayElement(irBuilder: IRBuilder2, rawArrayValue: LLVMValueRef, elementCGType: CGType,
    elementValue: CGValue, elementPtr: LLVMValueRef): LLVMValueRef {
    let rawElementValue = elementValue.GetRawValue()
    if (elementCGType.IsStructType() || elementCGType.IsVArrayType()) {
        return StoreRawArrayAggregateElement(irBuilder, rawArrayValue, elementCGType, elementValue, elementPtr)
    }
    if (elementCGType.IsReference()) {
        return irBuilder.CallGCWrite(rawElementValue, rawArrayValue, elementPtr)
    }
    return irBuilder.CreateStore(rawElementValue, elementPtr)
}

private func StoreRawArrayAggregateElement(irBuilder: IRBuilder2, rawArrayValue: LLVMValueRef,
    elementCGType: CGType, elementValue: CGValue, elementPtr: LLVMValueRef): LLVMValueRef {
    let rawElementValue = elementValue.GetRawValue()
    let valueCGType = elementValue.GetCGType() ?? return irBuilder.CreateStore(rawElementValue, elementPtr)
    if (!IsPointerBackedRawArrayAggregateValue(valueCGType, elementCGType)) {
        return irBuilder.CreateStore(rawElementValue, elementPtr)
    }
    let size = if (let Some(elementSize) <- elementCGType.GetSize()) { elementSize } else { 0 }
    let sizeValue = unsafe {
        LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(size), 0)
    }
    if (irBuilder.IsLLVMTypeContainsRef(elementCGType.GetLLVMType())) {
        let source = ReadManagedAggregateSourceIfNeeded(irBuilder, rawElementValue, elementCGType, sizeValue)
        return irBuilder.CallGCWriteStruct(rawArrayValue, elementPtr, source, sizeValue,
            elementCGType.GetOriginal().ToString())
    }
    let align = irBuilder.GetCGModule().GetABITypeAlignment(elementCGType.GetLLVMType())
    let source = ReadManagedAggregateSourceIfNeeded(irBuilder, rawElementValue, elementCGType, sizeValue)
    return irBuilder.CreateMemCpy(elementPtr, align, source, align, sizeValue)
}

private func ReadManagedAggregateSourceIfNeeded(irBuilder: IRBuilder2, source: LLVMValueRef,
    sourceCGType: CGType, size: LLVMValueRef): LLVMValueRef {
    if (!IsAddressSpacePointer(source, 1u32) || !irBuilder.IsLLVMTypeContainsRef(sourceCGType.GetLLVMType())) {
        return source
    }
    let sourceBase = irBuilder.GetTrackedManagedBase(source) ?? source
    let temp = irBuilder.CreateEntryAlloca(sourceCGType.GetLLVMType(), name: "rawarray.store.tmp")
    irBuilder.CallGCReadStruct(temp, sourceBase, source, size, sourceCGType.GetOriginal().ToString())
    return temp
}

private func IsPointerBackedRawArrayAggregateValue(valueCGType: CGType, elementCGType: CGType): Bool {
    if (valueCGType.IsStructPtrType() && elementCGType.IsStructType()) {
        return true
    }
    if (IsVArrayPtrValue(valueCGType) && elementCGType.IsVArrayType()) {
        return true
    }
    if (valueCGType.GetOriginal().StripAllRefs().IsString() && elementCGType.IsStructType()) {
        return true
    }
    if (!valueCGType.IsReference()) {
        return false
    }
    let valueElementCGType = valueCGType.GetPointerElementType() ?? return false
    return valueElementCGType.GetOriginal().StripAllRefs().IsEqual(elementCGType.GetOriginal().StripAllRefs())
}

private func IsVArrayPtrValue(cgType: CGType): Bool {
    if (!cgType.IsPointerType()) {
        return false
    }
    let elementType = cgType.GetPointerElementType() ?? return false
    return elementType.IsVArrayType()
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
        dynamicIndices.add(irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(idx)).GetRawValue())
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
                return irBuilder.CreateGEP(layoutType, typedPayload,
                    AdjustAutoEnvClassFieldIndices(baseType.GetOriginal(), indices), name: name)
            }
            return irBuilder.CreateGEP(elementType.GetLLVMType(), baseValue.GetRawValue(), indices, name: name)
        }
        if (baseType.IsStructType() || baseType.IsVArrayType()) {
            let baseSlot = irBuilder.CreateEntryAlloca(baseType, name: name + ".base")
            irBuilder.CreateStore(baseValue.GetRawValue(), baseSlot)
            return irBuilder.CreateGEP(baseType.GetLLVMType(), baseSlot, indices, name: name)
        }
        return irBuilder.CreateGEP(baseType.GetLLVMType(), baseValue.GetRawValue(), indices, name: name)
    }
    return LLVMNullValue()
}

private func AdjustAutoEnvClassFieldIndices(baseTy: Type, indices: ArrayList<LLVMValueRef>): ArrayList<LLVMValueRef> {
    let prefix = AutoEnvCallableAbiFieldCount(baseTy)
    if (prefix == 0u64 || indices.size < 2) {
        return indices
    }
    let adjusted = ArrayList<LLVMValueRef>()
    var idx: Int64 = 0
    while (idx < indices.size) {
        if (idx == 1) {
            let rawIndex = unsafe { LLVMConstIntGetZExtValue(indices[idx]) }
            adjusted.add(unsafe { LLVMConstInt(LLVMTypeOf(indices[idx]), rawIndex + prefix, 0) })
        } else {
            adjusted.add(indices[idx])
        }
        idx++
    }
    return adjusted
}

private func AutoEnvCallableAbiFieldCount(baseTy: Type): UInt64 {
    return if (IsAutoEnvType(baseTy)) { 2u64 } else { 0u64 }
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

private func ResolveElementTypeByPath(baseTy: Type, path: ArrayList<UInt64>): Option<Type> {
    if (path.isEmpty()) {
        return None
    }
    var currentTy = baseTy.StripAllRefs()
    for (pathItem in path) {
        if (let Some(rawArrayTy) <- (currentTy as RawArrayType)) {
            currentTy = rawArrayTy.GetElementType().StripAllRefs()
            continue
        }
        if (currentTy.IsTuple()) {
            let fields = currentTy.GetTypeArgs()
            let fieldIdx = Int64(pathItem)
            if (fieldIdx < 0 || fieldIdx >= fields.size) {
                return None
            }
            currentTy = fields[fieldIdx].StripAllRefs()
            continue
        }
        if (let Some(customTy) <- (currentTy as CustomType)) {
            let fields = customTy.GetInstantiatedMemberTys()
            let fieldIdx = Int64(pathItem)
            if (fieldIdx < 0 || fieldIdx >= fields.size) {
                return None
            }
            currentTy = fields[fieldIdx].StripAllRefs()
            continue
        }
        return None
    }
    return Some(currentTy)
}

private func IsManagedReferenceField(irBuilder: IRBuilder2, fieldTy: Option<Type>): Bool {
    if (let Some(ty) <- fieldTy) {
        let fieldCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), ty)
        if (fieldCGType.IsReference()) {
            return true
        }
        if (let Some(enumCGType) <- (CGType.GetOrCreate(irBuilder.GetCGModule(),
            ty.StripAllRefs()) as CGEnumType)) {
            return enumCGType.IsOptionLikeRef()
        }
    }
    return false
}
