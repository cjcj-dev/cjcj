package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Field
import cangjie_compiler::chir.FieldByName
import cangjie_compiler::chir.LocalVar
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeCast
import cangjie_compiler::chir.Value

public func GenerateFieldExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(fieldExpr) <- (chirExpr as Field)) {
        let _ = irBuilder.GetCGModule().GetMappedCGValue(fieldExpr.GetBase())
        if (let Some(localBase) <- (fieldExpr.GetBase() as LocalVar)) {
            if (let Some(ownerExpr) <- localBase.GetExpr()) {
                if (let Some(typeCastExpr) <- (ownerExpr as TypeCast)) {
                    if (typeCastExpr.GetSourceValue().GetType().getOrThrow().IsEnum() &&
                        typeCastExpr.GetTargetTy().getOrThrow().IsTuple()) {
                        return irBuilder.CreateEnumGEP(fieldExpr)
                    }
                }
            }
        }
        if (fieldExpr.GetBase().GetType().getOrThrow().IsEnum()) {
            return irBuilder.CreateEnumGEP(fieldExpr)
        }
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
