package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Field
import cangjie_compiler::chir.FieldByName
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value

public func GenerateFieldExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(fieldExpr) <- (chirExpr as Field)) {
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
    let baseValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, base)
    if (let Some(baseCGType) <- baseValue.GetCGType()) {
        if (baseCGType.IsPointerType()) {
            if (let Some(elementType) <- baseCGType.GetPointerElementType()) {
                let indices = ArrayList<LLVMValueRef>()
                indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), 0u64, 0) })
                for (item in path) {
                    indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), item, 0) })
                }
                let fieldAddr = irBuilder.CreateGEP(elementType.GetLLVMType(), baseValue.GetRawValue(), indices,
                    name: name + ".addr")
                if (let Some(fieldType) <- GetFieldCGTypeAtPath(elementType, path)) {
                    return irBuilder.CreateLoad(fieldType.GetLLVMType(), fieldAddr, name: name)
                }
                return fieldAddr
            }
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
