package cjcj::codegen

import std.collection.*
import cjcj::chir.Attribute
import cjcj::chir.Constant
import cjcj::chir.CustomType
import cjcj::chir.Box as ChirBox
import cjcj::chir.Expression
import cjcj::chir.GetElementByName
import cjcj::chir.GetElementRef
import cjcj::chir.LocalVar
import cjcj::chir.RawArrayLiteralInit
import cjcj::chir.RawArrayInitByValue
import cjcj::chir.RawArrayType
import cjcj::chir.StoreElementByName
import cjcj::chir.StoreElementRef
import cjcj::chir.Type
import cjcj::chir.Value
import cjcj::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG}

private let LLVM_STRUCT_TYPE_KIND: Int32 = 10
private let LLVM_ARRAY_TYPE_KIND: Int32 = 11
private let LLVM_VECTOR_TYPE_KIND: Int32 = 13
private let LLVM_SCALABLE_VECTOR_TYPE_KIND: Int32 = 17

public func GenerateRawArrayAllocate(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    CJC_ASSERT_WITH_MSG(chirExpr.GetNumOfOperands() == 1,
        "RawArrayAllocate's argument size is not equal to 1.")
    let rawArrayTy = FindRawArrayType(chirExpr.GetResultType().getOrThrow()).getOrThrow()
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
    irBuilder.CreateUnreachable()

    irBuilder.SetInsertPoint(bodyBlock)
    return irBuilder.AllocateArray(rawArrayTy, lengthValue)
}

public func GenerateRawArrayLiteralInit(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(arrayLiteralInit) <- (chirExpr as RawArrayLiteralInit)) {
        return CallArrayIntrinsicInitWithContent(irBuilder, arrayLiteralInit)
    }
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let rawArrayValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0))
    if (let Some(rawArrayTy) <- GetRawArrayType(rawArrayValue)) {
        let elementCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), rawArrayTy.GetElementType())
        var elementIdx: Int64 = 1
        while (elementIdx < chirExpr.GetNumOfOperands()) {
            let elementValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(elementIdx))
            let rawIndex = elementIdx - 1
            let elementPtr = irBuilder.CreateGEP(rawArrayValue, ArrayList<UInt64>([UInt64(rawIndex)]),
                name: "arr.idx${rawIndex}E").GetRawValue()
            StoreRawArrayElement(irBuilder, rawArrayValue.GetRawValue(), elementCGType, elementValue, elementPtr)
            elementIdx++
        }
        return rawArrayValue.GetRawValue()
    }
    return LLVMNullValue()
}

private func CallArrayIntrinsicInitWithContent(irBuilder: IRBuilder2,
    arrayLiteralInit: RawArrayLiteralInit): LLVMValueRef {
    let rawArrayValue = irBuilder.GetCGModule().GetMappedCGValue(arrayLiteralInit.GetRawArray())
    CJC_ASSERT(GetRawArrayType(rawArrayValue).isSome())
    if (let Some(rawArrayTy) <- GetRawArrayType(rawArrayValue)) {
        let constantArray = IsConstantArray(arrayLiteralInit)
        if (constantArray[0]) {
            let params = ArrayList<CGValue>()
            for (element in arrayLiteralInit.GetElements()) {
                params.add(irBuilder.GetCGModule().GetMappedCGValue(element))
            }
            return CallArrayIntrinsicAllocWithConstantContent(irBuilder, rawArrayValue.GetRawValue(), params,
                rawArrayTy, constantArray[1])
        }
        let elementCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), rawArrayTy.GetElementType())
        var elementIdx: Int64 = 0
        let elements = arrayLiteralInit.GetElements()
        while (elementIdx < elements.size) {
            let elementValue = irBuilder.GetCGModule().GetMappedCGValue(elements[elementIdx])
            let elementPtr = irBuilder.CreateGEP(rawArrayValue, ArrayList<UInt64>([UInt64(elementIdx)]),
                name: "arr.idx${elementIdx}E").GetRawValue()
            StoreRawArrayElement(irBuilder, rawArrayValue.GetRawValue(), elementCGType, elementValue, elementPtr)
            elementIdx++
        }
        return rawArrayValue.GetRawValue()
    }
    return LLVMNullValue()
}

private func CallArrayIntrinsicAllocWithConstantContent(irBuilder: IRBuilder2, array: LLVMValueRef,
    args: ArrayList<CGValue>, arrTy: RawArrayType, serialized: String): LLVMValueRef {
    CJC_ASSERT(IsAllConstantValue(args))
    let constants = ArrayList<LLVMValueRef>()
    for (arg in args) {
        let raw = arg.GetRawValue()
        if (!unsafe { LLVMIsAGlobalVariable(raw) }.isNull()) {
            constants.add(unsafe { LLVMGetInitializer(raw) })
        } else {
            constants.add(raw)
        }
    }
    return InitArrayFilledWithConstant(irBuilder, array, arrTy, constants, serialized)
}

private func InitArrayFilledWithConstant(irBuilder: IRBuilder2, array: LLVMValueRef, arrTy: RawArrayType,
    arrayConstantElems: ArrayList<LLVMValueRef>, serialized: String): LLVMValueRef {
    let cgMod = irBuilder.GetCGModule()
    let arrayType = CGArrayType.GenerateArrayLayoutType(cgMod, arrTy)
    let elementCGType = CGType.GetOrCreate(cgMod, arrTy.GetElementType())
    let elemType = if (elementCGType.IsStructPtrType()) {
        elementCGType.GetPointerElementType().getOrThrow()
    } else {
        elementCGType
    }
    let elemLLVMType = elemType.GetLLVMType()
    var constVal = LLVMNullValue()
    if (arrayConstantElems.isEmpty()) {
        constVal = unsafe { LLVMConstArray(elemLLVMType, CPointer<LLVMValueRef>(), 0u32) }
    } else {
        try (valuePtr = LibC.malloc<LLVMValueRef>(count: arrayConstantElems.size).asResource()) {
            var idx: Int64 = 0
            while (idx < arrayConstantElems.size) {
                unsafe { (valuePtr.value + idx).write(arrayConstantElems[idx]) }
                idx++
            }
            constVal = unsafe { LLVMConstArray(elemLLVMType, valuePtr.value, UInt32(arrayConstantElems.size)) }
        }
    }
    let arrayConstant = cgMod.GetOrCreateGlobalVariable(constVal, serialized, false)
    let arrPayloadPtr = irBuilder.GetPayloadFromObject(array)
    let arrPtr = irBuilder.CreateBitCast(arrPayloadPtr, unsafe { LLVMPointerType(arrayType, 1u32) },
        name: "arr.ptr")
    let arrDataPtr = irBuilder.CreateStructGEP(arrayType, arrPtr, 1u32, name: "arr.data")
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 1u32) }
    let srcArrI8Ptr = irBuilder.CreatePointerCast(arrayConstant, i8PtrType, name: "src.arr.i8")
    let dstArrI8Ptr = irBuilder.CreateBitCast(arrDataPtr, i8PtrType, name: "dst.arr.i8")
    let int64Type = unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
    let dataSize = unsafe { LLVMConstInt(int64Type, cgMod.GetTypeSize(LLVMGlobalGetValueType(arrayConstant)), 0) }
    let elemCnt = unsafe { LLVMConstInt(int64Type, UInt64(arrayConstantElems.size), 0) }
    irBuilder.CreateCopyTo(ArrayCopyToInfo(srcArrI8Ptr, array, srcArrI8Ptr, dstArrI8Ptr, dataSize,
        irBuilder.GetInt64(0), irBuilder.GetInt64(0), elemType, elemCnt))
    return array
}

public func GenerateRawArrayInitByValue(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let rawArrayInitByValue = (chirExpr as RawArrayInitByValue).getOrThrow()
    let cgMod = irBuilder.GetCGModule()
    let valueOperand = rawArrayInitByValue.GetInitValue()
    let elemValue = cgMod.GetMappedCGValue(valueOperand)
    let sizeVal = cgMod.GetMappedCGValue(rawArrayInitByValue.GetSize()).GetRawValue()
    let rawArrayType = rawArrayInitByValue.GetRawArray().GetType().getOrThrow().GetTypeArgs()[0]
    let arrTy = (rawArrayType as RawArrayType).getOrThrow()
    let array = cgMod.GetMappedCGValue(rawArrayInitByValue.GetRawArray()).GetRawValue()
    let isNullValue = if (let Some(localVar) <- (valueOperand as LocalVar)) {
        localVar.GetExpr().getOrThrow().IsConstantNull()
    } else {
        false
    }
    if (isNullValue) {
        return array
    }
    irBuilder.CallArrayInit(array, sizeVal, elemValue.GetRawValue(), arrTy)
    return array
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
    irBuilder.EmitLocation(CHIRExprWrapper(chirExpr), removable: true)
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
    let storedValue = StoreValueForAddress(irBuilder, value, addr)
    if (let Some(staticAggregateStore) <- TryStoreStaticAggregateValueForAddress(irBuilder, storedValue, addr)) {
        return staticAggregateStore
    }
    if (ShouldUseGCStaticWriteBarrier(irBuilder, addr) && ShouldUseGCStaticRefWriteBarrier(addr)) {
        return irBuilder.CallGCWriteStaticRef(storedValue, addr.GetRawValue())
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
                return irBuilder.CreatePointerCast(raw, destTy, name: "store.ptr.cast")
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
    if (fieldSize == 0) {
        return Some(LLVMNullValue())
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
    let sizeType = unsafe { LLVMTypeOf(size) }
    if (!sizeType.isNull() && unsafe { LLVMGetTypeKind(sizeType) } == 8 &&
        unsafe { LLVMIsAInstruction(size) }.isNull() && unsafe { LLVMIsAArgument(size) }.isNull() &&
        unsafe { LLVMConstIntGetZExtValue(size) } == 0u64) {
        return LLVMNullValue()
    }
    let moduleHandle = irBuilder.GetCGModule().GetLLVMModule() ?? return LLVMNullValue()
    irBuilder.CheckNoWriteBarrierRec()
    let call = unsafe {
        LLVMSelfhostCreateGCWriteStaticAgg(irBuilder.GetBuilder().raw, moduleHandle.raw, aggType, dest, source, size,
            irBuilder.GetSizetLLVMType())
    }
    let aggTypeName = LLVMCStringToString(unsafe { LLVMGetStructName(aggType) }) ?? ""
    let metadata = LLVMCreateMDTupleFromString(irBuilder.GetLLVMContext(), aggTypeName)
    LLVMSetInstructionMetadata(irBuilder.GetLLVMContext(), call, "AggType", metadata)
    return call
}

public func GenerateGetElementRef(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let baseValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0))
    if (let Some(staticElementRef) <- (chirExpr as GetElementRef)) {
        irBuilder.EmitLocation(CHIRExprWrapper(staticElementRef))
        let path = staticElementRef.GetPath()
        if (path.isEmpty()) {
            return LLVMNullValue()
        }
        return irBuilder.CreateGEP(baseValue, path, name: "gep").GetRawValue()
    }
    if (let Some(elementByName) <- (chirExpr as GetElementByName)) {
        if (let Some(locationTy) <- elementByName.GetLocation().GetType()) {
            if (let Some(path) <- ResolveElementPathByNames(
                irBuilder.GetCGModule(), locationTy, elementByName.GetNames())) {
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
                irBuilder.CallGCWriteAgg(srcCGType.GetLayoutType(), args)
            } else {
                irBuilder.CreateMemCpy(payloadPtr, 0u32, storeValue.GetRawValue(), 0u32, size)
            }
            let destAddr = irBuilder.CreateGEP(storePlace, path)
            let destElementType = destAddr.GetCGType().getOrThrow().GetPointerElementType().getOrThrow()
            return irBuilder.CreateStore(CGValue(tmp, destElementType), destAddr)
        }
        if (ShouldSkipNoOpStore(rhs, lhs)) {
            return LLVMNullValue()
        }
        irBuilder.EmitLocation(CHIRExprWrapper(storeElementRef))
        let storeAddr = irBuilder.CreateGEP(storePlace, path, name: "store.elem.addr")
        if (rhs.TestAttr(Attribute.FOREIGN)) {
            AddFnAttr(storeValue.GetRawValue(), CJ2C_ATTR)
        }
        return irBuilder.CreateStore(storeValue, storeAddr)
    }
    if (let Some(storeByName) <- (chirExpr as StoreElementByName)) {
        if (let Some(locationTy) <- storeByName.GetLocation().GetType()) {
            if (let Some(path) <- ResolveElementPathByNames(
                irBuilder.GetCGModule(), locationTy, storeByName.GetNames())) {
                if (ShouldSkipNoOpStore(storeByName.GetValue(), storeByName.GetLocation())) {
                    return LLVMNullValue()
                }
                let byNameValue = irBuilder.GetCGModule().GetMappedCGValue(storeByName.GetValue())
                let byNamePlace = irBuilder.GetCGModule().GetMappedCGValue(storeByName.GetLocation())
                let byNameAddr = irBuilder.CreateGEP(byNamePlace, path, name: "store.elem.addr")
                if (byNameAddr.GetRawValue().isNull()) {
                    return LLVMNullValue()
                }
                return irBuilder.CreateStore(byNameValue, byNameAddr)
            }
        }
    }
    return LLVMNullValue()
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
            if (let Some(path) <- ResolveElementPathByNames(
                irBuilder.GetCGModule(), locationTy, elementByName.GetNames())) {
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

private func ResolveElementPathByNames(cgMod: CGModule, baseTy: Type,
    names: ArrayList<String>): Option<ArrayList<UInt64>> {
    if (names.isEmpty()) {
        return None
    }
    let path = ArrayList<UInt64>()
    var currentTy = baseTy.StripAllRefs()
    for (name in names) {
        if (let Some(customTy) <- (currentTy as CustomType)) {
            let fields = customTy.GetCustomTypeDef().GetAllInstanceVars()
            let fieldTypes = customTy.GetInstantiatedMemberTys(cgMod.GetCGContext().GetCHIRBuilder())
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
