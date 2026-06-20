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
    let baseValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, base)
    if (let Some(baseCGType) <- baseValue.GetCGType()) {
        if (baseCGType.IsPointerType()) {
            if (let Some(elementType) <- baseCGType.GetPointerElementType()) {
                let indices = ArrayList<LLVMValueRef>()
                indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), 0u64, 0) })
                for (item in path) {
                    indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), item, 0) })
                }
                let basePointer = if (baseCGType.GetOriginal().StripAllRefs().IsClass()) {
                    let layoutType = elementType.GetLayoutType()
                    irBuilder.CreateBitCast(irBuilder.GetPayloadFromObject(baseValue.GetRawValue()),
                        unsafe { LLVMPointerType(layoutType, 1u32) }, name: name + ".payload")
                } else {
                    baseValue.GetRawValue()
                }
                let gepElementType = if (baseCGType.GetOriginal().StripAllRefs().IsClass()) {
                    elementType.GetLayoutType()
                } else {
                    elementType.GetLLVMType()
                }
                let fieldAddr = irBuilder.CreateGEP(gepElementType, basePointer, indices,
                    name: name + ".addr")
                if (let Some(fieldType) <- GetFieldCGTypeAtPath(elementType, path)) {
                    let loaded = irBuilder.CreateLoad(fieldType.GetLLVMType(), fieldAddr, name: name)
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
    let baseValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, base).GetRawValue()
    return Some(LoadObjectPayloadField(irBuilder, baseValue, targetTy, path, name, expectedTy))
}

private func GenerateDirectEnumField(irBuilder: IRBuilder2, base: Value,
    path: ArrayList<UInt64>, name: String, expectedTy: Option<Type>): Option<LLVMValueRef> {
    let baseTy = base.GetType() ?? return None
    let enumTy = (baseTy.StripAllRefs() as EnumType) ?? return None
    let enumCGType = (CGType.GetOrCreate(irBuilder.GetCGModule(), enumTy) as CGEnumType) ?? return None
    let baseValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, base).GetRawValue()
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
