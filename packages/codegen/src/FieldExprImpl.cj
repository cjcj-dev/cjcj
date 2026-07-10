package cjcj::codegen

import std.collection.*
import cjcj::chir.CustomType
import cjcj::chir.Expression
import cjcj::chir.Field
import cjcj::chir.FieldByName
import cjcj::chir.LocalVar
import cjcj::chir.Type
import cjcj::chir.TypeCast
import cjcj::chir.Value

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
        return GenerateFieldByPath(irBuilder, fieldExpr.GetBase(), fieldExpr.GetPath(), "field")
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
            return GenerateFieldByPath(irBuilder, base, path, "field")
        }
    }
    return LLVMNullValue()
}

private func GenerateFieldByPath(irBuilder: IRBuilder2, base: Value,
    path: ArrayList<UInt64>, name: String): LLVMValueRef {
    let baseValue = irBuilder.GetCGModule().GetMappedCGValue(base)
    if (let Some(baseCGType) <- baseValue.GetCGType()) {
        if (baseCGType.IsPointerType()) {
            let fieldValue = irBuilder.CreateGEP(baseValue, path, name: name)
            let baseType = unsafe { LLVMTypeOf(baseValue.GetRawValue()) }
            if (!baseType.isNull() && unsafe { LLVMGetTypeKind(baseType) } == 12 &&
                unsafe { LLVMGetPointerAddressSpace(baseType) } == 1u32) {
                irBuilder.GetCGContext().SetBasePtr(fieldValue.GetRawValue(), baseValue.GetRawValue())
            }
            return irBuilder.CreateLoad(fieldValue)
        }
        if (!path.isEmpty()) {
            var extracted = baseValue.GetRawValue()
            for (item in path) {
                extracted = irBuilder.CreateExtractValue(extracted, UInt32(item), name: name)
            }
            return extracted
        }
    }
    return LLVMNullValue()
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
