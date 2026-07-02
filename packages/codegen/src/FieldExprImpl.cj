package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Field
import cangjie_compiler::chir.FieldByName
import cangjie_compiler::chir.LocalVar
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeCast
import cangjie_compiler::chir.Value

public func GenerateFieldExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(fieldExpr) <- (chirExpr as Field)) {
        return GenerateFieldByPath(irBuilder, fieldExpr.GetBase(), fieldExpr.GetPath(), "field",
            chirExpr.GetResultType())
    }
    if (let Some(fieldByNameExpr) <- (chirExpr as FieldByName)) {
        return GenerateFieldByName(irBuilder, fieldByNameExpr)
    }
    return LLVMNullValue()
}

private func GenerateFieldByName(irBuilder: IRBuilder2, fieldExpr: FieldByName): LLVMValueRef {
    let base = fieldExpr.GetBase()
    if (let Some(baseTy) <- base.GetType()) {
        if (let Some(path) <- BuildFieldPathByNames(baseTy, fieldExpr.GetNames())) {
            return GenerateFieldByPath(irBuilder, base, path, "field", fieldExpr.GetResultType())
        }
    }
    return LLVMNullValue()
}

private func GenerateFieldByPath(irBuilder: IRBuilder2, base: Value,
    path: ArrayList<UInt64>, name: String, expectedTy: Option<Type>): LLVMValueRef {
    if (let Some(enumField) <- GenerateEnumFieldByPath(irBuilder, base, path, name, expectedTy)) {
        return enumField
    }
    let baseValue = irBuilder.GetCGModule().GetMappedCGValue(base)
    if (let Some(baseCGType) <- baseValue.GetCGType()) {
        if (baseCGType.IsPointerType()) {
            if (let Some(elementType) <- baseCGType.GetPointerElementType()) {
                let fieldAddr = irBuilder.CreateGEP(baseValue, path, name: name + ".addr").GetRawValue()
                if (let Some(fieldType) <- GetFieldCGTypeAtPath(elementType, path)) {
                    if (ShouldLoadGenericClassField(baseCGType, fieldType)) {
                        return irBuilder.LoadGenericFieldValue(baseValue.GetRawValue(), fieldAddr, fieldType,
                            baseCGType.GetOriginal(), Some(fieldType.GetOriginal()))
                    }
                    let typedFieldAddr = RetypeFieldAddressForLoad(irBuilder, fieldAddr, fieldType, name)
                    let loaded = LoadClassFieldWithBarrierIfNeeded(irBuilder, baseCGType, baseValue.GetRawValue(),
                        typedFieldAddr, fieldType, name)
                    return CastExtractedFieldIfNeeded(irBuilder, loaded, fieldType.GetOriginal(), expectedTy)
                }
                return fieldAddr
            }
        }
        if (!path.isEmpty()) {
            var extracted = baseValue.GetRawValue()
            for (item in path) {
                extracted = irBuilder.CreateExtractValue(extracted, UInt32(item), name: name)
            }
            if (let Some(fieldType) <- GetFieldCGTypeAtPath(baseCGType, path)) {
                return CastExtractedFieldIfNeeded(irBuilder, extracted, fieldType.GetOriginal(), expectedTy)
            }
            return extracted
        }
    }
    return LLVMNullValue()
}

private func GenerateEnumFieldByPath(irBuilder: IRBuilder2, base: Value,
    path: ArrayList<UInt64>, name: String, expectedTy: Option<Type>): Option<LLVMValueRef> {
    if (path.isEmpty()) {
        return None
    }
    if (let Some(enumTupleField) <- GenerateEnumTupleCastField(irBuilder, base, path, name, expectedTy)) {
        return Some(enumTupleField)
    }
    if (let Some(enumField) <- GenerateDirectEnumField(irBuilder, base, path, name, expectedTy)) {
        return Some(enumField)
    }
    return None
}

private func GenerateEnumTupleCastField(irBuilder: IRBuilder2, base: Value,
    path: ArrayList<UInt64>, name: String, expectedTy: Option<Type>): Option<LLVMValueRef> {
    let local = (base as LocalVar) ?? return None
    let ownerExpr = local.GetExpr() ?? return None
    let castExpr = (ownerExpr as TypeCast) ?? return None
    let sourceTy = castExpr.GetSourceTy() ?? return None
    let targetTy = castExpr.GetTargetTy() ?? return None
    if (!sourceTy.StripAllRefs().IsEnum() || !targetTy.IsTuple()) {
        return None
    }
    let baseValue = irBuilder.GetCGModule().GetMappedCGValue(base).GetRawValue()
    if (let Some(enumCGType) <- (CGType.GetOrCreate(irBuilder.GetCGModule(), sourceTy.StripAllRefs()) as CGEnumType)) {
        if (enumCGType.IsAllAssociatedValuesAreNonRef() || enumCGType.IsOptionLikeNonRef()) {
            var extracted = LoadPointerBackedEnumAggregateIfNeeded(irBuilder, baseValue, enumCGType)
            for (item in path) {
                extracted = irBuilder.CreateExtractValue(extracted, UInt32(item), name: name)
            }
            if (let Some(fieldType) <- GetFieldCGTypeAtPath(enumCGType, path)) {
                return Some(CastExtractedFieldIfNeeded(irBuilder, extracted, fieldType.GetOriginal(), expectedTy))
            }
            return Some(extracted)
        }
    }
    return Some(LoadObjectPayloadField(irBuilder, baseValue, targetTy, path, name, expectedTy))
}

private func LoadPointerBackedEnumAggregateIfNeeded(irBuilder: IRBuilder2, rawValue: LLVMValueRef,
    enumCGType: CGEnumType): LLVMValueRef {
    let rawTy = unsafe { LLVMTypeOf(rawValue) }
    if (!rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 12) {
        return irBuilder.CreateLoad(enumCGType.GetLLVMType(), rawValue, name: "enum.value")
    }
    return rawValue
}

private func GenerateDirectEnumField(irBuilder: IRBuilder2, base: Value,
    path: ArrayList<UInt64>, name: String, expectedTy: Option<Type>): Option<LLVMValueRef> {
    let baseTy = base.GetType() ?? return None
    let enumTy = (baseTy.StripAllRefs() as EnumType) ?? return None
    let enumCGType = (CGType.GetOrCreate(irBuilder.GetCGModule(), enumTy) as CGEnumType) ?? return None
    let baseValue = irBuilder.GetCGModule().GetMappedCGValue(base).GetRawValue()
    if (enumCGType.IsOptionLikeRef()) {
        if (path[0] == 0u64) {
            let nullValue = unsafe { LLVMConstNull(unsafe { LLVMTypeOf(baseValue) }) }
            let predicate = if (enumCGType.IsAntiOptionLike()) { LLVMIntPredicate.NE } else { LLVMIntPredicate.EQ }
            return Some(irBuilder.CreateICmp(predicate, baseValue, nullValue, name: name + ".tag"))
        }
        if (path[0] == 1u64) {
            if (let Some(fieldTy) <- expectedTy) {
                return Some(irBuilder.CreatePointerCast(baseValue,
                    CGType.GetOrCreate(irBuilder.GetCGModule(), fieldTy).GetLLVMType(), name: name + ".payload"))
            }
            return Some(baseValue)
        }
    }
    if (enumCGType.IsOptionLikeT() && path[0] == 0u64) {
        return Some(GenerateOptionLikeTTag(irBuilder, enumTy, enumCGType, baseValue, name))
    }
    if (enumCGType.IsOptionLikeT() && path[0] == 1u64) {
        let associatedValueType = expectedTy ?? (if (!enumTy.GetTypeArgs().isEmpty()) {
            enumTy.GetTypeArgs()[0]
        } else {
            return Some(LLVMNullValue())
        })
        return Some(GenerateOptionLikeTAssociatedValue(irBuilder, enumTy, enumCGType, baseValue, associatedValueType))
    }
    if (enumCGType.IsCommonEnum() && path[0] == 0u64) {
        let fieldTy = expectedTy ?? irBuilder.GetCGModule().GetCGContext().GetCHIRBuilder().context.GetUInt32Ty()
        let fieldLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), fieldTy).GetLLVMType()
        let payload = irBuilder.GetPayloadFromObject(baseValue)
        let typedPayload = irBuilder.CreateBitCast(payload, unsafe { LLVMPointerType(fieldLLVMType, 1u32) },
            name: name + ".tag.addr")
        return Some(irBuilder.CreateLoad(fieldLLVMType, typedPayload, name: name))
    }
    return None
}

private func GenerateOptionLikeTTag(irBuilder: IRBuilder2, enumTy: EnumType, enumCGType: CGEnumType,
    enumValue: LLVMValueRef, name: String): LLVMValueRef {
    let i1Ty = unsafe { LLVMInt1TypeInContext(irBuilder.GetLLVMContext().raw) }
    let payload = irBuilder.GetPayloadFromObject(enumValue)
    let blockNames = ArrayList<String>()
    blockNames.add("ref")
    blockNames.add("nonRef")
    blockNames.add("end")
    let blocks = irBuilder.CreateAndInsertBasicBlocks(blockNames)
    if (blocks.size < 3) {
        return LLVMNullValue()
    }
    let typeArgs = enumTy.GetTypeArgs()
    if (typeArgs.isEmpty()) {
        return LLVMNullValue()
    }
    let isRef = irBuilder.CreateTypeInfoIsReferenceCall(typeArgs[0])
    irBuilder.CreateCondBr(isRef, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    let refRead = irBuilder.CallGCReadRef(enumValue, payload)
    let refResult = CreateOptionLikeNullCheck(irBuilder, refRead, enumCGType.IsAntiOptionLike(), name + ".tag.ref")
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    let payloadPtrTy = unsafe { LLVMPointerType(i1Ty, 1u32) }
    let nonRefPayload = irBuilder.CreateBitCast(payload, payloadPtrTy, name: name + ".tag.addr")
    let nonRefResult = irBuilder.CreateLoad(i1Ty, nonRefPayload, name: name + ".tag.nonref")
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[2])
    let phi = irBuilder.CreatePHI(i1Ty, name: name + ".tag")
    let values = ArrayList<LLVMValueRef>()
    values.add(refResult)
    values.add(nonRefResult)
    let incomingBlocks = ArrayList<LLVMBasicBlockRef>()
    incomingBlocks.add(blocks[0])
    incomingBlocks.add(blocks[1])
    irBuilder.AddIncoming(phi, values, incomingBlocks)
    return phi
}

private func GenerateOptionLikeTAssociatedValue(irBuilder: IRBuilder2, enumTy: EnumType, enumCGType: CGEnumType,
    enumValue: LLVMValueRef, associatedValueType: Type): LLVMValueRef {
    let i8Ty = unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
    let i8PtrTy = unsafe { LLVMPointerType(i8Ty, 1u32) }
    let blockNames = ArrayList<String>()
    blockNames.add("ref")
    blockNames.add("nonRef")
    blockNames.add("end")
    let blocks = irBuilder.CreateAndInsertBasicBlocks(blockNames)
    if (blocks.size < 3) {
        return LLVMNullValue()
    }
    let typeArgs = enumTy.GetTypeArgs()
    if (typeArgs.isEmpty()) {
        return LLVMNullValue()
    }
    let isRef = irBuilder.CreateTypeInfoIsReferenceCall(typeArgs[0])
    irBuilder.CreateCondBr(isRef, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    let payload = irBuilder.CreateBitCast(irBuilder.GetPayloadFromObject(enumValue), i8PtrTy)
    let refResult = irBuilder.CallGCReadRef(enumValue, payload)
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    let nonRefResult = GetOptionLikeNonRefAssociatedValue(irBuilder, enumCGType.GetOriginal(),
        associatedValueType, enumValue)
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[2])
    let phi = irBuilder.CreatePHI(i8PtrTy)
    let values = ArrayList<LLVMValueRef>()
    values.add(refResult)
    values.add(nonRefResult)
    let incomingBlocks = ArrayList<LLVMBasicBlockRef>()
    incomingBlocks.add(blocks[0])
    incomingBlocks.add(blocks[1])
    irBuilder.AddIncoming(phi, values, incomingBlocks)
    return phi
}

private func GetOptionLikeNonRefAssociatedValue(irBuilder: IRBuilder2, enumTy: Type,
    associatedValueType: Type, enumValueWithTI: LLVMValueRef): LLVMValueRef {
    let associatedValueTypeInfo = irBuilder.CreateTypeInfo(associatedValueType)
    let associatedCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), associatedValueType)
    let associatedValueTypeSize = irBuilder.GetLayoutSize32(associatedValueType, associatedCGType)
    let nonRefResult = irBuilder.CallAllocaGenericWithTypeInfoAndSize(associatedValueType,
        associatedValueTypeInfo, associatedValueTypeSize)
    let enumTypeInfo = irBuilder.CreateTypeInfo(enumTy)
    let associatedValOffset = irBuilder.CallGetFieldOffset(enumTypeInfo, 1u64, 8u64)
    let indices = ArrayList<LLVMValueRef>()
    indices.add(associatedValOffset)
    let associatedValPtr = irBuilder.CreateInBoundsGEP(unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) },
        enumValueWithTI, indices)
    irBuilder.CallGCReadGeneric(nonRefResult, enumValueWithTI, associatedValPtr, associatedValueTypeSize)
    return nonRefResult
}

private func CreateOptionLikeNullCheck(irBuilder: IRBuilder2, value: LLVMValueRef, isAntiOptionLike: Bool,
    name: String): LLVMValueRef {
    let nullValue = unsafe { LLVMConstNull(CGType.GetRefType(irBuilder.GetLLVMContext())) }
    let predicate = if (isAntiOptionLike) { LLVMIntPredicate.NE } else { LLVMIntPredicate.EQ }
    return irBuilder.CreateICmp(predicate, value, nullValue, name: name)
}

private func LoadObjectPayloadField(irBuilder: IRBuilder2, objectValue: LLVMValueRef, storageTy: Type,
    path: ArrayList<UInt64>, name: String, expectedTy: Option<Type>): LLVMValueRef {
    if (path.size != 1) {
        throw IllegalArgumentException("faithful codegen enum payload field path expects one component")
    }
    let storageCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), storageTy)
    let layoutType = storageCGType.GetLLVMType()
    let payload = irBuilder.GetPayloadFromObject(objectValue)
    let typedPayload = irBuilder.CreateBitCast(payload, unsafe { LLVMPointerType(layoutType, 1u32) },
        name: name + ".payload")
    let fieldPtr = irBuilder.CreateStructGEP(layoutType, typedPayload, UInt32(path[0]), name: name + ".addr")
    if (let Some(fieldType) <- GetFieldCGTypeAtPath(storageCGType, path)) {
        let loaded = if (IsGCRefField(irBuilder, fieldType.GetOriginal())) {
            irBuilder.CallGCReadRef(objectValue, fieldPtr)
        } else {
            irBuilder.CreateLoad(fieldType.GetLLVMType(), fieldPtr, name: name)
        }
        return CastExtractedFieldIfNeeded(irBuilder, loaded, fieldType.GetOriginal(), expectedTy)
    }
    return LLVMNullValue()
}

private func LoadClassFieldWithBarrierIfNeeded(irBuilder: IRBuilder2, baseCGType: CGType,
    baseObject: LLVMValueRef, fieldAddr: LLVMValueRef, fieldType: CGType, name: String): LLVMValueRef {
    if (!baseCGType.GetOriginal().StripAllRefs().IsClass()) {
        return irBuilder.CreateLoad(fieldType.GetLLVMType(), fieldAddr, name: name)
    }
    if (!IsAddressSpacePointer(baseObject, 1u32) || !IsAddressSpacePointer(fieldAddr, 1u32)) {
        return irBuilder.CreateLoad(fieldType.GetLLVMType(), fieldAddr, name: name)
    }
    if (IsClassGCRefField(irBuilder, fieldType)) {
        return irBuilder.CallGCReadRef(baseObject, fieldAddr)
    }
    if (IsAggregateFieldWithRef(irBuilder, fieldType)) {
        let fieldSize = if (let Some(size) <- fieldType.GetSize()) { size } else { 0 }
        let fieldSizeValue = unsafe {
            LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(fieldSize), 0)
        }
        let dest = irBuilder.CreateEntryAlloca(fieldType.GetLLVMType(), name: name + ".gcread")
        irBuilder.CallGCReadStruct(dest, baseObject, fieldAddr, fieldSizeValue, fieldType.GetOriginal().ToString())
        return dest
    }
    return irBuilder.CreateLoad(fieldType.GetLLVMType(), fieldAddr, name: name)
}

private func IsClassGCRefField(irBuilder: IRBuilder2, fieldType: CGType): Bool {
    if (fieldType.IsReference()) {
        return true
    }
    if (let Some(enumCGType) <- (CGType.GetOrCreate(irBuilder.GetCGModule(),
        fieldType.GetOriginal().StripAllRefs()) as CGEnumType)) {
        return enumCGType.IsOptionLikeRef()
    }
    return false
}

private func IsAggregateFieldWithRef(irBuilder: IRBuilder2, fieldType: CGType): Bool {
    if (!(fieldType.IsStructType() || fieldType.IsVArrayType())) {
        return false
    }
    return irBuilder.IsLLVMTypeContainsRef(fieldType.GetLLVMType())
}

private func IsGCRefField(irBuilder: IRBuilder2, fieldTy: Type): Bool {
    let stripped = fieldTy.StripAllRefs()
    if (stripped.IsReferenceType()) {
        return true
    }
    if (let Some(enumCGType) <- (CGType.GetOrCreate(irBuilder.GetCGModule(), stripped) as CGEnumType)) {
        return enumCGType.IsCommonEnum() || enumCGType.IsOptionLikeRef()
    }
    return false
}

private func IsAddressSpacePointer(value: LLVMValueRef, addressSpace: UInt32): Bool {
    let rawTy = unsafe { LLVMTypeOf(value) }
    return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 12 &&
        unsafe { LLVMGetPointerAddressSpace(rawTy) } == addressSpace
}

private func CastExtractedFieldIfNeeded(irBuilder: IRBuilder2, rawValue: LLVMValueRef, sourceTy: Type,
    expectedTy: Option<Type>): LLVMValueRef {
    if (let Some(targetTy) <- expectedTy) {
        if (!sourceTy.IsEqual(targetTy)) {
            let targetLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType()
            return CastValueToType(irBuilder, rawValue, sourceTy, targetTy, targetLLVMType)
        }
    }
    return rawValue
}

private func BuildFieldPathByNames(baseTy: Type, names: ArrayList<String>): Option<ArrayList<UInt64>> {
    if (names.isEmpty()) {
        return None
    }
    let path = ArrayList<UInt64>()
    var currentTy = baseTy.StripAllRefs()
    for (name in names) {
        if (let Some(customTy) <- (currentTy as CustomType)) {
            let fields = customTy.GetCustomTypeDef().GetAllInstanceVars()
            var idx: Int64 = 0
            var found = false
            while (idx < fields.size) {
                let fieldInfo = fields[idx]
                if (fieldInfo.name == name || fieldInfo.rawMangledName == name) {
                    path.add(UInt64(idx))
                    currentTy = fieldInfo.ty.StripAllRefs()
                    found = true
                    break
                }
                idx++
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

private func GetFieldCGTypeAtPath(rootType: CGType, path: ArrayList<UInt64>): Option<CGType> {
    if (path.isEmpty()) {
        return None
    }
    var currentType = rootType
    for (item in path) {
        let contained = currentType.GetContainedTypes()
        let fieldIdx = Int64(item)
        if (fieldIdx < 0 || fieldIdx >= contained.size) {
            return None
        }
        currentType = contained[fieldIdx]
    }
    return Some(currentType)
}

private func RetypeFieldAddressForLoad(irBuilder: IRBuilder2, fieldAddr: LLVMValueRef,
    fieldType: CGType, name: String): LLVMValueRef {
    if (fieldType.GetOriginal().StripAllRefs().IsGeneric()) {
        return fieldAddr
    }
    let rawTy = unsafe { LLVMTypeOf(fieldAddr) }
    if (rawTy.isNull() || unsafe { LLVMGetTypeKind(rawTy) } != 12) {
        return fieldAddr
    }
    let addrspace = unsafe { LLVMGetPointerAddressSpace(rawTy) }
    let typedPtrTy = unsafe { LLVMPointerType(fieldType.GetLLVMType(), addrspace) }
    return irBuilder.CreateBitCast(fieldAddr, typedPtrTy, name: name + ".typed")
}

private func ShouldLoadGenericClassField(baseCGType: CGType, fieldCGType: CGType): Bool {
    return baseCGType.GetOriginal().StripAllRefs().IsClass() && fieldCGType.GetOriginal().StripAllRefs().IsGeneric()
}
