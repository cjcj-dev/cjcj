package cangjie_compiler::codegen

import cangjie_compiler::chir.Type

public func GetOrInsertCodeGenGlobal(cgMod: CGModule, globalName: String, globalType: LLVMTypeRef): LLVMValueRef {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
            result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
            if (result.isNull()) {
                result = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameCString.value) }
            }
        }
        return result
    }
    return LLVMNullValue()
}

public func GetOrCreateTypeInfoGlobal(cgMod: CGModule, chirTy: Type, genericKind: CGGenericKind): LLVMValueRef {
    let typeInfoTy = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
    let typeInfoName = CGType.GetNameOfTypeInfoGV(chirTy)
    if (genericKind == CGGenericKind.STATIC_GI) {
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            try (nameCString = unsafe { LibC.mallocCString(typeInfoName) }.asResource()) {
                let existing = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
                if (existing.isNull()) {
                    cgMod.GetCGContext().RegisterStaticGIName(typeInfoName)
                }
            }
        }
    }
    cgMod.GetCGContext().AddCodeGenAddedFuncsOrVars(chirTy, typeInfoName)
    return GetOrInsertCodeGenGlobal(cgMod, typeInfoName, typeInfoTy)
}

public func NeedTypeTemplate(chirTy: Type): Bool {
    if (chirTy.IsTuple() || chirTy.IsVArray() || chirTy.IsRawArray() || chirTy.IsCPointer() ||
        chirTy.IsBox() || chirTy.IsFunc()) {
        return true
    }
    return !chirTy.GetTypeArgs().isEmpty()
}

public func GetOrCreateTypeTemplateGlobal(cgMod: CGModule, chirTy: Type): LLVMValueRef {
    if (!NeedTypeTemplate(chirTy)) {
        return LLVMNullValue()
    }
    let templateTy = CGType.GetOrCreateTypeTemplateType(cgMod.GetLLVMContext())
    let templateName = CGType.GetNameOfTypeTemplateGV(chirTy)
    cgMod.GetCGContext().AddCodeGenAddedFuncsOrVars(chirTy, templateName)
    return GetOrInsertCodeGenGlobal(cgMod, templateName, templateTy)
}
