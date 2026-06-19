package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.BooleanType
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CPointerType
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.RefType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.VArrayType

private let UG_CLASS_KIND: UInt64 = 128u64
private let UG_RAW_ARRAY_KIND: UInt64 = 130u64
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
    let typeInfo = DeclareTypeInfoGlobal(cgMod, chirTy, genericKind)
    DefineTypeInfoGlobalIfNeeded(cgMod, chirTy, typeInfo)
    return typeInfo
}

public func DeclareTypeInfoGlobal(cgMod: CGModule, chirTy: Type, genericKind: CGGenericKind): LLVMValueRef {
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
    if (chirTy.IsPrimitive()) {
        let layoutName = if (chirTy.IsVoid()) { UNIT_TYPE_STR } else { chirTy.ToString() + ".Type" }
        LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), typeInfo, GC_TYPE_META_NAME, layoutName)
    }
    return typeInfo
}

public func DefineTypeInfoGlobalIfNeeded(cgMod: CGModule, chirTy: Type, typeInfo: LLVMValueRef): Unit {
    DefineConcreteTypeInfoIfNeeded(cgMod, chirTy, typeInfo, CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext()))
}

private func DefineConcreteTypeInfoIfNeeded(cgMod: CGModule, chirTy: Type, typeInfo: LLVMValueRef,
    typeInfoTy: LLVMTypeRef): Unit {
    if (typeInfo.isNull() || unsafe { LLVMIsDeclaration(typeInfo) } == 0) {
        return
    }
    if (IsImportedCustomType(chirTy)) {
        return
    }
    if (chirTy.IsRawArray()) {
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            let initializer = BuildRawArrayTypeInfoInitializer(cgMod, moduleHandle, chirTy, typeInfoTy)
            unsafe {
                LLVMSetInitializer(typeInfo, initializer)
                LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.LinkOnceODR))
                LLVMSetGlobalConstant(typeInfo, 0)
            }
            LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), typeInfo, GC_TYPE_META_NAME,
                ARRAY_LAYOUT_PREFIX + chirTy.ToString())
        }
        return
    }
    if (!(chirTy.IsClass() || chirTy.IsStruct() || chirTy.IsEnum())) {
        return
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let initializer = BuildConcreteTypeInfoInitializer(cgMod, moduleHandle, chirTy, typeInfoTy)
        unsafe {
            LLVMSetInitializer(typeInfo, initializer)
            if (chirTy.GetTypeArgs().isEmpty()) {
                LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.Internal))
                LLVMSetGlobalConstant(typeInfo, 1)
            } else {
                LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.LinkOnceODR))
                LLVMSetGlobalConstant(typeInfo, 0)
            }
        }
        LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), typeInfo, GC_TYPE_META_NAME, GetLayoutMetadataName(chirTy))
    }
}

private func IsImportedCustomType(chirTy: Type): Bool {
    if (let Some(customTy) <- (chirTy as CustomType)) {
        return customTy.GetCustomTypeDef().TestAttr(Attribute.IMPORTED)
    }
    return false
}

private func BuildRawArrayTypeInfoInitializer(cgMod: CGModule, moduleHandle: LLVMModuleHandle, chirTy: Type,
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
    let rawArrayTy = (chirTy as RawArrayType) ?? throw IllegalArgumentException("expected raw array type info")
    let elementTy = rawArrayTy.GetElementType().StripAllRefs()
    let elementCGType = CGType.GetOrCreate(cgMod, elementTy)
    let elementSize = if (let Some(size) <- elementCGType.GetSize()) { UInt64(size) } else { 0u64 }
    let typeTemplateTy = CGType.GetOrCreateTypeTemplateType(contextHandle)
    let rawArrayTypeTemplate = GetOrInsertCodeGenGlobal(cgMod, "RawArray.tt", typeTemplateTy)
    let typeInfoValues = ArrayList<LLVMValueRef>()
    typeInfoValues.add(GenerateTypeInfoNameConstant(cgMod, moduleHandle, CGType.GetRuntimeTypeName(chirTy)))
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, UG_RAW_ARRAY_KIND, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, elementSize, 0) })
    typeInfoValues.add(unsafe { LLVMConstNull(bitMapPtrType) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 1u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, INHERITED_CLASS_NUM_FE_FLAG, 0) })
    typeInfoValues.add(unsafe { LLVMConstNull(i32PtrType) })
    typeInfoValues.add(unsafe { LLVMConstBitCast(rawArrayTypeTemplate, i8PtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(CGType.GetOrCreate(cgMod, elementTy).GetOrCreateTypeInfo())
    typeInfoValues.add(unsafe { LLVMConstNull(extensionDefPtrPtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    return TypeInfoConstStruct(typeInfoTy, typeInfoValues)
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
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(contextHandle)
    let bitMapPtrType = unsafe { LLVMPointerType(CGType.GetBitMapType(contextHandle), 0u32) }
    let extensionDefPtrPtrType = unsafe {
        LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(contextHandle), 0u32)
    }
    let cgType = CGType.GetOrCreate(cgMod, chirTy)
    let typeInfoName = CGType.GetNameOfTypeInfoGV(chirTy)
    let fieldCount = UInt64(GetInstanceFieldTypes(chirTy).size)
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
    typeInfoValues.add(GenerateTypeInfoNameConstant(cgMod, moduleHandle, CGType.GetRuntimeTypeName(chirTy)))
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, TypeInfoKind(chirTy), 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, fieldCount, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, sizeValue, 0) })
    typeInfoValues.add(unsafe { LLVMConstNull(bitMapPtrType) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, alignValue, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, UInt64(chirTy.GetTypeArgs().size), 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, InheritedClassNumValue(chirTy), 0) })
    typeInfoValues.add(GenerateOffsetsOfTypeInfo(cgMod, chirTy, cgType, typeInfoName, i32PtrType))
    typeInfoValues.add(GenerateSourceGenericOfTypeInfo(cgMod, chirTy, i8PtrType))
    typeInfoValues.add(GenerateTypeArgsOfTypeInfo(cgMod, chirTy, typeInfoName, i8PtrType))
    typeInfoValues.add(GenerateFieldsOfTypeInfo(cgMod, chirTy, typeInfoName, i8PtrType))
    typeInfoValues.add(GenerateSuperOfTypeInfo(cgMod, chirTy, typeInfoPtrType))
    typeInfoValues.add(unsafe { LLVMConstNull(extensionDefPtrPtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    return TypeInfoConstStruct(typeInfoTy, typeInfoValues)
}

private func GenerateSourceGenericOfTypeInfo(cgMod: CGModule, chirTy: Type, i8PtrType: LLVMTypeRef): LLVMValueRef {
    if (chirTy.GetTypeArgs().isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        let typeTemplateTy = CGType.GetOrCreateTypeTemplateType(cgMod.GetLLVMContext())
        let def = customTy.GetCustomTypeDef()
        let typeTemplateName = if (def.GetPackageName().isEmpty()) {
            def.GetSrcCodeIdentifier() + ".tt"
        } else {
            def.GetPackageName() + ":" + def.GetSrcCodeIdentifier() + ".tt"
        }
        let typeTemplate = GetOrInsertCodeGenGlobal(cgMod, typeTemplateName, typeTemplateTy)
        if (!typeTemplate.isNull()) {
            return unsafe { LLVMConstBitCast(typeTemplate, i8PtrType) }
        }
    }
    let typeTemplate = GetOrCreateTypeTemplateGlobal(cgMod, chirTy)
    if (!typeTemplate.isNull()) {
        return unsafe { LLVMConstBitCast(typeTemplate, i8PtrType) }
    }
    return unsafe { LLVMConstNull(i8PtrType) }
}

private func GenerateTypeArgsOfTypeInfo(cgMod: CGModule, chirTy: Type, typeInfoName: String,
    i8PtrType: LLVMTypeRef): LLVMValueRef {
    let typeArgs = chirTy.GetTypeArgs()
    if (typeArgs.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let arrayType = unsafe { LLVMArrayType(typeInfoPtrType, UInt32(typeArgs.size)) }
    let typeArgsGlobal = GetOrInsertCodeGenGlobal(cgMod, typeInfoName + ".typeArgs", arrayType)
    if (unsafe { LLVMIsDeclaration(typeArgsGlobal) } != 0) {
        let values = ArrayList<LLVMValueRef>()
        for (typeArg in typeArgs) {
            values.add(CGType.GetOrCreate(cgMod, typeArg.StripAllRefs()).GetOrCreateTypeInfo())
        }
        unsafe {
            LLVMSetInitializer(typeArgsGlobal, ConstArray(typeInfoPtrType, values))
            LLVMSetLinkage(typeArgsGlobal, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(typeArgsGlobal, 1)
        }
    }
    return unsafe { LLVMConstBitCast(typeArgsGlobal, i8PtrType) }
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

public func GetInstanceFieldTypes(chirTy: Type): ArrayList<Type> {
    let result = ArrayList<Type>()
    if (let Some(enumTy) <- (chirTy as EnumType)) {
        return GetEnumTypeInfoFieldTypes(enumTy)
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        let genericParams = customTy.GetCustomTypeDef().GetGenericTypeParams()
        let genericArgs = customTy.GetGenericArgs()
        for (member in customTy.GetCustomTypeDef().GetAllInstanceVars()) {
            if (!member.isStatic) {
                result.add(SubstituteGenericFieldType(member.ty, genericParams, genericArgs))
            }
        }
    }
    return result
}

private func GetEnumTypeInfoFieldTypes(enumTy: EnumType): ArrayList<Type> {
    let result = ArrayList<Type>()
    result.add(BooleanType())
    let genericParams = enumTy.GetEnumDef().GetGenericTypeParams()
    let genericArgs = enumTy.GetGenericArgs()
    for (ctor in enumTy.GetEnumDef().GetCtors()) {
        var idx: Int64 = 0
        for (payloadTy in ctor.payloadTypes) {
            let fieldTy = SubstituteGenericFieldType(payloadTy, genericParams, genericArgs)
            let storageIdx = idx + 1
            if (storageIdx >= result.size) {
                result.add(fieldTy)
            }
            idx++
        }
    }
    return result
}

private func SubstituteGenericFieldType(ty: Type, genericParams: ArrayList<GenericType>,
    genericArgs: ArrayList<Type>): Type {
    if (genericParams.isEmpty() || genericArgs.isEmpty()) {
        return ty
    }
    if (let Some(genericTy) <- (ty as GenericType)) {
        var idx: Int64 = 0
        while (idx < genericParams.size && idx < genericArgs.size) {
            if (genericTy.GetIdentifier() == genericParams[idx].GetIdentifier()) {
                return genericArgs[idx]
            }
            idx++
        }
        return ty
    }
    if (let Some(refTy) <- (ty as RefType)) {
        return RefType(SubstituteGenericFieldType(refTy.GetBaseType(), genericParams, genericArgs))
    }
    if (let Some(rawArrayTy) <- (ty as RawArrayType)) {
        return RawArrayType(SubstituteGenericFieldType(rawArrayTy.GetElementType(), genericParams, genericArgs),
            dims: rawArrayTy.GetDims())
    }
    if (let Some(varrayTy) <- (ty as VArrayType)) {
        return VArrayType(SubstituteGenericFieldType(varrayTy.GetElementType(), genericParams, genericArgs),
            varrayTy.size)
    }
    if (let Some(cpointerTy) <- (ty as CPointerType)) {
        return CPointerType(SubstituteGenericFieldType(cpointerTy.GetElementType(), genericParams, genericArgs))
    }
    return ty
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

private func InheritedClassNumValue(chirTy: Type): UInt64 {
    if (let Some(classTy) <- (chirTy as ClassType)) {
        if (classTy.GetClassDef().IsInterface()) {
            return INHERITED_CLASS_NUM_FE_FLAG + 2u64
        }
    }
    return INHERITED_CLASS_NUM_FE_FLAG
}

private func GetLayoutMetadataName(chirTy: Type): String {
    if (chirTy.IsClass()) {
        return GetClassObjLayoutName(chirTy.ToString())
    }
    if (chirTy.IsString()) {
        return "record.std.core:String"
    }
    return STRUCT_TYPE_PREFIX + chirTy.ToString()
}

private func IsCoreObjectClass(classTy: ClassType): Bool {
    let def = classTy.GetClassDef()
    return def.GetPackageName() == "std.core" && def.GetSrcCodeIdentifier() == "Object"
}

private func GetCoreObjectTypeInfo(cgMod: CGModule): LLVMValueRef {
    let typeInfoTy = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
    let objectTypeInfo = GetOrInsertCodeGenGlobal(cgMod, "std.core:Object.ti", typeInfoTy)
    LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), objectTypeInfo, GC_TYPE_META_NAME,
        GetClassObjLayoutName("std.core:Object"))
    return objectTypeInfo
}

private func GenerateSuperOfTypeInfo(cgMod: CGModule, chirTy: Type, typeInfoPtrType: LLVMTypeRef): LLVMValueRef {
    if (let Some(classTy) <- (chirTy as ClassType)) {
        if (let Some(superTy) <- classTy.GetSuperClassTy()) {
            return CGType.GetOrCreate(cgMod, superTy.StripAllRefs()).GetOrCreateTypeInfo()
        }
        if (!IsCoreObjectClass(classTy)) {
            return GetCoreObjectTypeInfo(cgMod)
        }
    }
    return unsafe { LLVMConstNull(typeInfoPtrType) }
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
