package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.Type

private let UG_CLASS_KIND: UInt64 = 128u64
private let UG_STRUCT_KIND: UInt64 = 22u64
private let UG_ENUM_KIND: UInt64 = 23u64

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
    let typeInfo = GetOrInsertCodeGenGlobal(cgMod, typeInfoName, typeInfoTy)
    DefineConcreteTypeInfoIfNeeded(cgMod, chirTy, typeInfo, typeInfoTy)
    return typeInfo
}

private func DefineConcreteTypeInfoIfNeeded(cgMod: CGModule, chirTy: Type, typeInfo: LLVMValueRef,
    typeInfoTy: LLVMTypeRef): Unit {
    if (typeInfo.isNull() || unsafe { LLVMIsDeclaration(typeInfo) } == 0) {
        return
    }
    if (!(chirTy.IsClass() || chirTy.IsStruct() || chirTy.IsEnum())) {
        return
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let initializer = BuildConcreteTypeInfoInitializer(cgMod, moduleHandle, chirTy, typeInfoTy)
        unsafe {
            LLVMSetInitializer(typeInfo, initializer)
            LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.Internal))
            LLVMSetGlobalConstant(typeInfo, 1)
        }
    }
}

private func BuildConcreteTypeInfoInitializer(cgMod: CGModule, moduleHandle: LLVMModuleHandle, chirTy: Type,
    typeInfoTy: LLVMTypeRef): LLVMValueRef {
    let contextHandle = cgMod.GetLLVMContext()
    let context = contextHandle.raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i16Type = unsafe { LLVMInt16TypeInContext(context) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let i32PtrType = unsafe { LLVMPointerType(i32Type, 0u32) }
    let bitMapPtrType = unsafe { LLVMPointerType(CGType.GetBitMapType(contextHandle), 0u32) }
    let extensionDefPtrPtrType = unsafe {
        LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(contextHandle), 0u32)
    }
    let cgType = CGType.GetOrCreate(cgMod, chirTy)
    let typeInfoName = CGType.GetNameOfTypeInfoGV(chirTy)
    let fieldCount = if (let Some(customTy) <- (chirTy as CustomType)) {
        UInt64(customTy.GetCustomTypeDef().GetAllInstanceVars().size)
    } else {
        0u64
    }
    let sizeValue = if (chirTy.IsClass()) {
        cgMod.GetTypeSize(cgType.GetLayoutType())
    } else if (let Some(staticSize) <- cgType.GetSize()) {
        UInt64(staticSize)
    } else {
        0u64
    }
    let alignValue = if (let Some(staticAlign) <- cgType.GetAlign()) {
        UInt64(staticAlign)
    } else {
        0u64
    }
    let typeInfoValues = ArrayList<LLVMValueRef>()
    typeInfoValues.add(GenerateTypeInfoNameConstant(cgMod, moduleHandle, chirTy.ToString()))
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, TypeInfoKind(chirTy), 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, fieldCount, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, sizeValue, 0) })
    typeInfoValues.add(unsafe { LLVMConstNull(bitMapPtrType) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, alignValue, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, INHERITED_CLASS_NUM_FE_FLAG, 0) })
    typeInfoValues.add(GenerateOffsetsOfTypeInfo(cgMod, chirTy, cgType, typeInfoName, i32PtrType))
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(GenerateFieldsOfTypeInfo(cgMod, chirTy, typeInfoName, i8PtrType))
    typeInfoValues.add(unsafe { LLVMConstNull(CGType.GetOrCreateTypeInfoPtrType(contextHandle)) })
    typeInfoValues.add(unsafe { LLVMConstNull(extensionDefPtrPtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    return TypeInfoConstStruct(typeInfoTy, typeInfoValues)
}

private func GenerateFieldsOfTypeInfo(cgMod: CGModule, chirTy: Type, typeInfoName: String,
    i8PtrType: LLVMTypeRef): LLVMValueRef {
    let fieldTypes = GetInstanceFieldTypes(chirTy)
    if (fieldTypes.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let arrayType = unsafe { LLVMArrayType(typeInfoPtrType, UInt32(fieldTypes.size)) }
    let fieldsGlobal = GetOrInsertCodeGenGlobal(cgMod, typeInfoName + ".fields", arrayType)
    if (unsafe { LLVMIsDeclaration(fieldsGlobal) } != 0) {
        let fieldInfos = ArrayList<LLVMValueRef>()
        for (fieldTy in fieldTypes) {
            fieldInfos.add(CGType.GetOrCreate(cgMod, fieldTy.StripAllRefs()).GetOrCreateTypeInfo())
        }
        unsafe {
            LLVMSetInitializer(fieldsGlobal, ConstArray(typeInfoPtrType, fieldInfos))
            LLVMSetLinkage(fieldsGlobal, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(fieldsGlobal, 1)
        }
    }
    return unsafe { LLVMConstBitCast(fieldsGlobal, i8PtrType) }
}

private func GenerateOffsetsOfTypeInfo(cgMod: CGModule, chirTy: Type, cgType: CGType,
    typeInfoName: String, i32PtrType: LLVMTypeRef): LLVMValueRef {
    let fieldTypes = GetInstanceFieldTypes(chirTy)
    if (fieldTypes.isEmpty()) {
        return unsafe { LLVMConstNull(i32PtrType) }
    }
    let i32Type = unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) }
    let arrayType = unsafe { LLVMArrayType(i32Type, UInt32(fieldTypes.size)) }
    let offsetsGlobal = GetOrInsertCodeGenGlobal(cgMod, typeInfoName + ".offsets", arrayType)
    if (unsafe { LLVMIsDeclaration(offsetsGlobal) } != 0) {
        let offsets = ArrayList<LLVMValueRef>()
        let targetData = cgMod.GetModuleTargetData()
        var idx: Int64 = 0
        while (idx < fieldTypes.size) {
            let offset = targetData.GetOffsetOfElement(cgType.GetLayoutType(), UInt32(idx))
            offsets.add(unsafe { LLVMConstInt(i32Type, offset, 0) })
            idx++
        }
        unsafe {
            LLVMSetInitializer(offsetsGlobal, ConstArray(i32Type, offsets))
            LLVMSetLinkage(offsetsGlobal, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(offsetsGlobal, 1)
        }
    }
    return unsafe { LLVMConstBitCast(offsetsGlobal, i32PtrType) }
}

private func GetInstanceFieldTypes(chirTy: Type): ArrayList<Type> {
    let result = ArrayList<Type>()
    if (let Some(customTy) <- (chirTy as CustomType)) {
        for (member in customTy.GetCustomTypeDef().GetAllInstanceVars()) {
            if (!member.isStatic) {
                result.add(member.ty)
            }
        }
    }
    return result
}

private func ConstArray(elementType: LLVMTypeRef, values: ArrayList<LLVMValueRef>): LLVMValueRef {
    if (values.isEmpty()) {
        return unsafe { LLVMConstArray(elementType, CPointer<LLVMValueRef>(), 0u32) }
    }
    var result = LLVMNullValue()
    try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
        var idx: Int64 = 0
        while (idx < values.size) {
            unsafe { (valuePtr.value + idx).write(values[idx]) }
            idx++
        }
        result = unsafe { LLVMConstArray(elementType, valuePtr.value, UInt32(values.size)) }
    }
    return result
}

private func TypeInfoKind(chirTy: Type): UInt64 {
    if (chirTy.IsClass()) { return UG_CLASS_KIND }
    if (chirTy.IsStruct()) { return UG_STRUCT_KIND }
    if (chirTy.IsEnum()) { return UG_ENUM_KIND }
    return 0u64
}

private func TypeInfoConstStruct(structType: LLVMTypeRef, values: ArrayList<LLVMValueRef>): LLVMValueRef {
    if (values.isEmpty()) {
        return unsafe { LLVMConstNamedStruct(structType, CPointer<LLVMValueRef>(), 0u32) }
    }
    var result = LLVMNullValue()
    try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
        var idx: Int64 = 0
        while (idx < values.size) {
            unsafe { (valuePtr.value + idx).write(values[idx]) }
            idx++
        }
        result = unsafe { LLVMConstNamedStruct(structType, valuePtr.value, UInt32(values.size)) }
    }
    return result
}

private func GenerateTypeInfoNameConstant(cgMod: CGModule, moduleHandle: LLVMModuleHandle, value: String): LLVMValueRef {
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let globalType = unsafe { LLVMArrayType(i8Type, UInt32(value.size + 1)) }
    let globalName = value + ".ti.name"
    var global = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
        global = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
        if (global.isNull()) {
            global = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameCString.value) }
            try (valueCString = unsafe { LibC.mallocCString(value) }.asResource()) {
                let initializer = unsafe {
                    LLVMConstStringInContext(context, valueCString.value, UInt32(value.size), 0)
                }
                unsafe {
                    LLVMSetInitializer(global, initializer)
                    LLVMSetLinkage(global, LLVMLinkageValue(LLVMLinkage.Private))
                    LLVMSetGlobalConstant(global, 1)
                }
            }
        }
    }
    let zero = unsafe { LLVMConstInt(i32Type, 0u64, 0) }
    return TypeInfoConstInBoundsGEP2(globalType, global, zero, zero)
}

private func TypeInfoConstInBoundsGEP2(elementType: LLVMTypeRef, pointer: LLVMValueRef,
    firstIndex: LLVMValueRef, secondIndex: LLVMValueRef): LLVMValueRef {
    var result = LLVMNullValue()
    try (indexPtr = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
        unsafe {
            (indexPtr.value + 0).write(firstIndex)
            (indexPtr.value + 1).write(secondIndex)
            result = LLVMConstInBoundsGEP2(elementType, pointer, indexPtr.value, 2u32)
        }
    }
    return result
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
