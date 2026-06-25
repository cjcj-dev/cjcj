package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.BooleanType
import cangjie_compiler::chir.BoxType
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CPointerType
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.RawArrayType
import cangjie_compiler::chir.RefType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKindIndex
import cangjie_compiler::chir.TupleType
import cangjie_compiler::chir.VArrayType
import cangjie_compiler::option.{ArchType, EnvironmentType}
import cangjie_compiler::utils.{REF_PACKAGE_NAME, STD_LIB_WEAK_REF}

private let UG_CLASS_KIND: UInt64 = 128u64
private let UG_INTERFACE_KIND: UInt64 = 129u64
private let UG_RAW_ARRAY_KIND: UInt64 = 130u64
private let UG_COMMON_ENUM_KIND: UInt64 = 132u64
private let UG_WEAKREF_KIND: UInt64 = 133u64
private let UG_GENERIC_CUSTOM_KIND: UInt64 = 254u64
private let UG_GENERIC_KIND: UInt64 = 255u64
private let UG_TUPLE_KIND: UInt64 = 21u64
private let UG_STRUCT_KIND: UInt64 = 22u64
private let UG_ENUM_KIND: UInt64 = 23u64
private let GET_TYPE_INFO_INTRINSIC_NAME: String = "llvm.cj.get.type.info"
private let TYPEINFO_MTABLE_INLINE_FLAG: UInt64 = 9223372036854775808u64
private let MTABLE_INLINE_BITS_LIMIT: Int64 = 63

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

// Mirror C++ llvm::Module::getNamedGlobal: return the existing global with this name, or None if it
// has not been inserted yet. Used by the generic-typeinfo creators to short-circuit recursion when
// the in-progress global has already been declared (but not yet initialized).
public func GetNamedCodeGenGlobal(cgMod: CGModule, globalName: String): Option<LLVMValueRef> {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(globalName) }.asResource()) {
            result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
        }
        if (!result.isNull()) {
            return result
        }
    }
    return None
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

public func GetOrCreateGenericTypeInfoGlobal(cgMod: CGModule, chirTy: Type): LLVMValueRef {
    let genericTy = (chirTy as GenericType) ?? throw IllegalArgumentException("expected generic type info")
    let typeInfoTy = GetOrCreateGenericTypeInfoType(cgMod.GetLLVMContext())
    let typeInfoName = GenericTypeInfoName(cgMod, genericTy) + ".ti"
    // Mirror C++ CGGenericType::GetOrCreateTypeInfo (CGGenericType.cpp:58-60): if the global already
    // exists (even just declared, before its initializer is set) return it. This caches the global
    // BEFORE generating its upper bounds, so a re-entrant lookup during F-bounded upper-bound
    // generation reuses the in-progress global instead of recursing forever.
    if (let Some(found) <- GetNamedCodeGenGlobal(cgMod, typeInfoName)) {
        return found
    }
    let typeInfo = GetOrInsertCodeGenGlobal(cgMod, typeInfoName, typeInfoTy)
    if (typeInfo.isNull()) {
        return typeInfo
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let context = cgMod.GetLLVMContext().raw
        let i8Type = unsafe { LLVMInt8TypeInContext(context) }
        let i32Type = unsafe { LLVMInt32TypeInContext(context) }
        let values = ArrayList<LLVMValueRef>()
        values.add(GenerateTypeInfoNameConstant(cgMod, moduleHandle, genericTy.GetSrcCodeIdentifier()))
        values.add(unsafe { LLVMConstInt(i8Type, UG_GENERIC_KIND, 0) })
        values.add(unsafe { LLVMConstInt(i32Type, UInt64(genericTy.GetUpperBounds().size), 0) })
        values.add(GenerateUpperBoundsOfGenericTypeInfo(cgMod, genericTy, typeInfoName))
        unsafe {
            LLVMSetInitializer(typeInfo, TypeInfoConstStruct(typeInfoTy, values))
            LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(typeInfo, 0)
        }
    }
    return typeInfo
}

public func GetOrCreateGenericCustomTypeInfoGlobal(cgMod: CGModule, chirTy: Type): LLVMValueRef {
    let customTy = (chirTy as CustomType) ?? throw IllegalArgumentException("expected generic custom type info")
    let typeInfoTy = GetOrCreateGenericCustomTypeInfoType(cgMod.GetLLVMContext())
    let qualifiedName = GenericCustomTypeInfoName(cgMod, customTy)
    // Mirror C++ CGType::GetOrCreateGenericCustomTypeInfo (CGType.cpp:1046-1048): if the global already
    // exists (even just declared, before its initializer is set) return it. This caches the global
    // BEFORE generating its type args, so a re-entrant lookup during F-bounded type-arg generation
    // reuses the in-progress global instead of recursing forever.
    if (let Some(found) <- GetNamedCodeGenGlobal(cgMod, qualifiedName + ".ti")) {
        return found
    }
    let typeInfo = GetOrInsertCodeGenGlobal(cgMod, qualifiedName + ".ti", typeInfoTy)
    if (typeInfo.isNull()) {
        return typeInfo
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let context = cgMod.GetLLVMContext().raw
        let i8Type = unsafe { LLVMInt8TypeInContext(context) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let values = ArrayList<LLVMValueRef>()
        values.add(GenerateTypeInfoNameConstant(cgMod, moduleHandle, qualifiedName))
        values.add(unsafe { LLVMConstInt(i8Type, UG_GENERIC_CUSTOM_KIND, 0) })
        values.add(unsafe { LLVMConstInt(i8Type, UInt64(customTy.GetGenericArgs().size), 0) })
        values.add(GenerateTypeArgsOfGenericCustomTypeInfo(cgMod, customTy, qualifiedName))
        values.add(unsafe { LLVMConstBitCast(EnsureSourceGenericTypeTemplate(cgMod, customTy), i8PtrType) })
        unsafe {
            LLVMSetInitializer(typeInfo, TypeInfoConstStruct(typeInfoTy, values))
            LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(typeInfo, 0)
        }
    }
    return typeInfo
}

private func GetOrCreateGenericTypeInfoType(context: LLVMContextHandle): LLVMTypeRef {
    let result = GetOrCreateNamedStructType(context, "GenericTypeInfo")
    let i8Type = unsafe { LLVMInt8TypeInContext(context.raw) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context.raw) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let body = ArrayList<LLVMTypeRef>()
    body.add(i8PtrType)
    body.add(i8Type)
    body.add(i32Type)
    body.add(i8PtrType)
    SetStructTypeBody(result, body)
    return result
}

private func GetOrCreateGenericCustomTypeInfoType(context: LLVMContextHandle): LLVMTypeRef {
    let result = GetOrCreateNamedStructType(context, "GenericCustomTypeInfo")
    let i8Type = unsafe { LLVMInt8TypeInContext(context.raw) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let body = ArrayList<LLVMTypeRef>()
    body.add(i8PtrType)
    body.add(i8Type)
    body.add(i8Type)
    body.add(i8PtrType)
    body.add(i8PtrType)
    SetStructTypeBody(result, body)
    return result
}

private func GenericTypeInfoName(cgMod: CGModule, genericTy: GenericType): String {
    return cgMod.GetCGContext().GetGenericTypeUniqueName(genericTy.GetSrcCodeIdentifier(),
        genericTy.GetUpperBounds())
}

private func GenerateUpperBoundsOfGenericTypeInfo(cgMod: CGModule, genericTy: GenericType,
    typeInfoName: String): LLVMValueRef {
    let i8Type = unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let upperBounds = genericTy.GetUpperBounds()
    if (upperBounds.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let values = ArrayList<LLVMValueRef>()
    for (upperBound in upperBounds) {
        values.add(unsafe {
            LLVMConstBitCast(CGType.GetOrCreate(cgMod, upperBound.StripAllRefs()).GetOrCreateTypeInfo(), i8PtrType)
        })
    }
    let arrayType = unsafe { LLVMArrayType(i8PtrType, UInt32(values.size)) }
    let upperBoundsGlobal = GetOrInsertCodeGenGlobal(cgMod, typeInfoName + ".upperBounds", arrayType)
    if (unsafe { LLVMIsDeclaration(upperBoundsGlobal) } != 0) {
        unsafe {
            LLVMSetInitializer(upperBoundsGlobal, ConstArray(i8PtrType, values))
            LLVMSetLinkage(upperBoundsGlobal, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(upperBoundsGlobal, 1)
        }
    }
    return unsafe { LLVMConstBitCast(upperBoundsGlobal, i8PtrType) }
}

private func GenerateTypeArgsOfGenericCustomTypeInfo(cgMod: CGModule, customTy: CustomType,
    qualifiedName: String): LLVMValueRef {
    let i8Type = unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let typeArgs = customTy.GetGenericArgs()
    if (typeArgs.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let values = ArrayList<LLVMValueRef>()
    for (typeArg in typeArgs) {
        values.add(unsafe {
            LLVMConstBitCast(CGType.GetOrCreate(cgMod, typeArg.StripAllRefs()).GetOrCreateTypeInfo(), i8PtrType)
        })
    }
    let arrayType = unsafe { LLVMArrayType(i8PtrType, UInt32(values.size)) }
    let typeArgsGlobal = GetOrInsertCodeGenGlobal(cgMod, qualifiedName + ".typeArgs", arrayType)
    if (unsafe { LLVMIsDeclaration(typeArgsGlobal) } != 0) {
        unsafe {
            LLVMSetInitializer(typeArgsGlobal, ConstArray(i8PtrType, values))
            LLVMSetLinkage(typeArgsGlobal, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(typeArgsGlobal, 1)
        }
    }
    return unsafe { LLVMConstBitCast(typeArgsGlobal, i8PtrType) }
}

private func GenericCustomTypeInfoName(cgMod: CGModule, customTy: CustomType): String {
    let def = customTy.GetCustomTypeDef()
    let packageName = if (let Some(genericDecl) <- def.GetGenericDecl()) {
        genericDecl.GetPackageName()
    } else {
        def.GetPackageName()
    }
    var name = if (packageName.isEmpty()) {
        def.GetSrcCodeIdentifier()
    } else {
        packageName + ":" + def.GetSrcCodeIdentifier()
    }
    let typeArgs = customTy.GetGenericArgs()
    if (!typeArgs.isEmpty()) {
        name += "<" + GenericTypeArgsQualifiedName(cgMod, typeArgs) + ">"
    }
    return name
}

private func GenericTypeArgsQualifiedName(cgMod: CGModule, typeArgs: ArrayList<Type>): String {
    var out = ""
    var idx: Int64 = 0
    for (typeArg in typeArgs) {
        if (idx > 0) {
            out += ","
        }
        out += GenericTypeQualifiedName(cgMod, typeArg)
        idx++
    }
    return out
}

private func GenericTypeQualifiedName(cgMod: CGModule, chirTy: Type): String {
    let stripped = chirTy.StripAllRefs()
    if (let Some(genericTy) <- (stripped as GenericType)) {
        return GenericTypeInfoName(cgMod, genericTy)
    }
    if (let Some(customTy) <- (stripped as CustomType)) {
        return GenericCustomTypeInfoName(cgMod, customTy)
    }
    return stripped.ToString()
}

public func RedefineTypeInfoGlobal(cgMod: CGModule, chirTy: Type): Unit {
    if (!(chirTy.IsClass() || chirTy.IsStruct() || chirTy.IsEnum() || chirTy.IsTuple())) {
        return
    }
    if (IsImportedCustomType(chirTy)) {
        return
    }
    let typeInfoTy = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
    let typeInfo = DeclareTypeInfoGlobal(cgMod, chirTy, CGType.GetCGGenericKind(chirTy))
    if (typeInfo.isNull()) {
        return
    }
    if (IsGenericRelatedCustomType(chirTy)) {
        return
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let initializer = BuildConcreteTypeInfoInitializer(cgMod, moduleHandle, chirTy, typeInfoTy)
        unsafe {
            LLVMSetInitializer(typeInfo, initializer)
            SetConcreteTypeInfoLinkage(typeInfo, chirTy)
        }
        LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), typeInfo, GC_TYPE_META_NAME, GetLayoutMetadataName(chirTy))
    }
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
    if (!(chirTy.IsClass() || chirTy.IsStruct() || chirTy.IsEnum() || chirTy.IsTuple())) {
        return
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        if (customTy.GetCustomTypeDef().TestAttr(Attribute.IMPORTED) &&
            CGType.GetCGGenericKind(chirTy) == CGGenericKind.CONCRETE) {
            return
        }
    }
    if (IsGenericRelatedCustomType(chirTy)) {
        return
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let initializer = BuildConcreteTypeInfoInitializer(cgMod, moduleHandle, chirTy, typeInfoTy)
        unsafe {
            LLVMSetInitializer(typeInfo, initializer)
            SetConcreteTypeInfoLinkage(typeInfo, chirTy)
        }
        LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), typeInfo, GC_TYPE_META_NAME, GetLayoutMetadataName(chirTy))
    }
}

private func IsGenericRelatedCustomType(chirTy: Type): Bool {
    return (chirTy as CustomType).isSome() && chirTy.IsGenericRelated()
}

private func SetConcreteTypeInfoLinkage(typeInfo: LLVMValueRef, chirTy: Type): Unit {
    let linkage = if (chirTy.GetTypeArgs().isEmpty()) {
        if (ShouldExportTypeInfo(chirTy)) { LLVMLinkage.External } else { LLVMLinkage.Internal }
    } else {
        LLVMLinkage.LinkOnceODR
    }
    unsafe {
        LLVMSetLinkage(typeInfo, LLVMLinkageValue(linkage))
        LLVMSetGlobalConstant(typeInfo, 0)
    }
}

private func ShouldExportTypeInfo(chirTy: Type): Bool {
    if (let Some(customTy) <- (chirTy as CustomType)) {
        let def = customTy.GetCustomTypeDef()
        return def.TestAttr(Attribute.PUBLIC) || def.TestAttr(Attribute.PROTECTED)
    }
    return false
}

private func IsImportedCustomType(chirTy: Type): Bool {
    if (!chirTy.GetTypeArgs().isEmpty()) {
        return false
    }
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
    let fieldCount = UInt64(GetInstanceFieldTypes(cgMod, chirTy).size)
    var inheritedClassNum = InheritedClassNumBase(chirTy)
    let (mtable, updatedInheritedClassNum) = GenerateMTableOfTypeInfo(cgMod, chirTy, i8PtrType, inheritedClassNum)
    inheritedClassNum = updatedInheritedClassNum
    let sizeValue = TypeInfoSizeValue(cgMod, chirTy, cgType)
    let alignValue = TypeInfoAlignValue(cgMod, chirTy, cgType)
    let typeInfoValues = ArrayList<LLVMValueRef>()
    typeInfoValues.add(GenerateTypeInfoNameConstant(cgMod, moduleHandle, CGType.GetRuntimeTypeName(chirTy)))
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, TypeInfoKind(cgMod, chirTy), 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, fieldCount, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, sizeValue, 0) })
    typeInfoValues.add(unsafe { LLVMConstNull(bitMapPtrType) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, alignValue, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, UInt64(chirTy.GetTypeArgs().size), 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, inheritedClassNum + INHERITED_CLASS_NUM_FE_FLAG, 0) })
    typeInfoValues.add(GenerateOffsetsOfTypeInfo(cgMod, chirTy, cgType, typeInfoName, i32PtrType))
    typeInfoValues.add(GenerateSourceGenericOfTypeInfo(cgMod, chirTy, i8PtrType))
    typeInfoValues.add(GenerateTypeArgsOfTypeInfo(cgMod, chirTy, typeInfoName, i8PtrType))
    typeInfoValues.add(GenerateFieldsOfTypeInfo(cgMod, chirTy, typeInfoName, i8PtrType))
    typeInfoValues.add(GenerateSuperOfTypeInfo(cgMod, chirTy, typeInfoPtrType))
    typeInfoValues.add(GenerateExtensionDefPtrOfTypeInfo(cgMod, chirTy, extensionDefPtrPtrType))
    typeInfoValues.add(mtable)
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    return TypeInfoConstStruct(typeInfoTy, typeInfoValues)
}

private func GenerateSourceGenericOfTypeInfo(cgMod: CGModule, chirTy: Type, i8PtrType: LLVMTypeRef): LLVMValueRef {
    if (chirTy.GetTypeArgs().isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        let typeTemplate = EnsureSourceGenericTypeTemplate(cgMod, customTy)
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

public func EnsureSourceGenericTypeTemplate(cgMod: CGModule, customTy: CustomType): LLVMValueRef {
    let typeTemplateTy = CGType.GetOrCreateTypeTemplateType(cgMod.GetLLVMContext())
    let typeTemplateName = SourceGenericTypeTemplateName(customTy)
    let typeTemplate = GetOrInsertCodeGenGlobal(cgMod, typeTemplateName, typeTemplateTy)
    if (!typeTemplate.isNull() && unsafe { LLVMIsDeclaration(typeTemplate) } != 0) {
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            unsafe {
                LLVMSetInitializer(typeTemplate,
                    BuildSourceGenericTypeTemplateInitializer(cgMod, moduleHandle, customTy, typeTemplateTy,
                        typeTemplateName))
                LLVMSetLinkage(typeTemplate, LLVMLinkageValue(LLVMLinkage.LinkOnceODR))
                LLVMSetGlobalConstant(typeTemplate, 0)
            }
        }
    }
    return typeTemplate
}

private func SourceGenericTypeTemplateName(customTy: CustomType): String {
    return SourceGenericTypeTemplateRuntimeName(customTy) + ".tt"
}

private func SourceGenericTypeTemplateRuntimeName(customTy: CustomType): String {
    let def = customTy.GetCustomTypeDef()
    if (def.GetPackageName().isEmpty()) {
        return def.GetSrcCodeIdentifier()
    }
    return def.GetPackageName() + ":" + def.GetSrcCodeIdentifier()
}

private func BuildSourceGenericTypeTemplateInitializer(cgMod: CGModule, moduleHandle: LLVMModuleHandle,
    customTy: CustomType, typeTemplateTy: LLVMTypeRef, typeTemplateName: String): LLVMValueRef {
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i16Type = unsafe { LLVMInt16TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let extensionDefPtrPtrType = unsafe {
        LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(cgMod.GetLLVMContext()), 0u32)
    }
    let values = ArrayList<LLVMValueRef>()
    let isAutoEnv = IsAutoEnvType(customTy)
    let runtimeName = if (isAutoEnv) { SourceGenericTypeTemplateRuntimeName(customTy) } else { typeTemplateName }
    values.add(GenerateTypeInfoNameConstant(cgMod, moduleHandle, runtimeName))
    values.add(unsafe { LLVMConstInt(i8Type, TypeInfoKind(cgMod, customTy), 0) })
    values.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    let fieldNum = if (isAutoEnv) {
        UInt64(GetTypeTemplateFieldTypes(cgMod, customTy).size)
    } else {
        UInt64(customTy.GetCustomTypeDef().GetAllInstanceVarNum())
    }
    values.add(unsafe { LLVMConstInt(i16Type, fieldNum, 0) })
    values.add(unsafe { LLVMConstInt(i16Type, UInt64(customTy.GetCustomTypeDef().GetGenericTypeParams().size), 0) })
    values.add(if (isAutoEnv) {
        GenerateFieldsFnsOfTypeTemplate(cgMod, customTy, typeTemplateName, i8PtrType)
    } else {
        unsafe { LLVMConstNull(i8PtrType) }
    })
    values.add(if (isAutoEnv) {
        GenerateSuperFnOfTypeTemplate(cgMod, customTy, typeTemplateName, i8PtrType)
    } else {
        unsafe { LLVMConstNull(i8PtrType) }
    })
    values.add(unsafe { LLVMConstNull(i8PtrType) })
    values.add(unsafe { LLVMConstNull(i8PtrType) })
    values.add(unsafe { LLVMConstNull(extensionDefPtrPtrType) })
    values.add(unsafe { LLVMConstInt(i16Type, if (isAutoEnv) {
        TypeTemplateInheritedClassNumValue(customTy)
    } else {
        InheritedClassNumValue(customTy)
    }, 0) })
    return TypeInfoConstStruct(typeTemplateTy, values)
}

private func GenerateFieldsFnsOfTypeTemplate(cgMod: CGModule, customTy: CustomType, typeTemplateName: String,
    i8PtrType: LLVMTypeRef): LLVMValueRef {
    let fieldTypes = GetTypeTemplateFieldTypes(cgMod, customTy)
    if (fieldTypes.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let fieldFnType = GetTypeTemplateCallbackFunctionType(cgMod)
    let fieldFns = ArrayList<LLVMValueRef>()
    let genericParams = customTy.GetCustomTypeDef().GetGenericTypeParams()
    var idx: Int64 = 0
    while (idx < fieldTypes.size) {
        fieldFns.add(GenerateTypeTemplateTypeInfoFn(cgMod, fieldFnType, typeTemplateName + ".fieldTiFn." +
            idx.toString(), fieldTypes[idx], genericParams))
        idx++
    }
    let fieldFnPtrType = unsafe { LLVMTypeOf(fieldFns[0]) }
    let arrayType = unsafe { LLVMArrayType(fieldFnPtrType, UInt32(fieldFns.size)) }
    let fieldFnsGlobal = GetOrInsertCodeGenGlobal(cgMod, typeTemplateName + ".fieldTiFns", arrayType)
    unsafe {
        LLVMSetInitializer(fieldFnsGlobal, ConstArray(fieldFnPtrType, fieldFns))
        LLVMSetLinkage(fieldFnsGlobal, LLVMLinkageValue(LLVMLinkage.Private))
        LLVMSetGlobalConstant(fieldFnsGlobal, 1)
    }
    return unsafe { LLVMConstBitCast(fieldFnsGlobal, i8PtrType) }
}

private func GenerateSuperFnOfTypeTemplate(cgMod: CGModule, customTy: CustomType, typeTemplateName: String,
    i8PtrType: LLVMTypeRef): LLVMValueRef {
    let sourceTy = SourceCustomType(customTy)
    if (let Some(classTy) <- (sourceTy as ClassType)) {
        if (!classTy.GetClassDef().IsClass()) {
            return unsafe { LLVMConstNull(i8PtrType) }
        }
        if (let Some(superTy) <- TypeTemplateSuperClassTy(classTy)) {
            let superFn = GenerateTypeTemplateTypeInfoFn(cgMod, GetTypeTemplateCallbackFunctionType(cgMod),
                typeTemplateName + ".superTiFn", superTy, customTy.GetCustomTypeDef().GetGenericTypeParams())
            return unsafe { LLVMConstBitCast(superFn, i8PtrType) }
        }
    }
    return unsafe { LLVMConstNull(i8PtrType) }
}

private func GenerateTypeTemplateTypeInfoFn(cgMod: CGModule, functionType: LLVMTypeRef, name: String, memberTy: Type,
    genericParams: ArrayList<GenericType>): LLVMValueRef {
    let fn = cgMod.GetOrInsertFunction(name, functionType)
    if (unsafe { LLVMIsDeclaration(fn) } == 0) {
        return fn
    }
    unsafe { LLVMSetLinkage(fn, LLVMLinkageValue(LLVMLinkage.Private)) }
    AddFnAttr(fn, "native-interface-fn")
    try (irBuilder = IRBuilder2(cgMod)) {
        let entry = irBuilder.CreateEntryBasicBlock(fn, "entry")
        irBuilder.SetInsertPoint(entry)
        let typeInfo = CreateTypeInfoForTemplateCallback(cgMod, irBuilder, memberTy, genericParams,
            unsafe { LLVMGetParam(fn, 1u32) })
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
        let rawTypeInfo = irBuilder.CreateBitCast(typeInfo, i8PtrType, name: "ti.raw")
        irBuilder.CreateRet(rawTypeInfo)
    }
    return fn
}

private func GetTypeTemplateCallbackFunctionType(cgMod: CGModule): LLVMTypeRef {
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let params = ArrayList<LLVMTypeRef>()
    params.add(i32Type)
    params.add(unsafe { LLVMPointerType(typeInfoPtrType, 0u32) })
    return BuildTypeInfoFunctionType(i8PtrType, params)
}

private func BuildTypeInfoFunctionType(returnType: LLVMTypeRef, paramTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
    if (paramTypes.isEmpty()) {
        return unsafe { LLVMFunctionType(returnType, CPointer<LLVMTypeRef>(), 0u32, 0) }
    }
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: paramTypes.size).asResource()) {
        var idx: Int64 = 0
        while (idx < paramTypes.size) {
            unsafe { (paramPtr.value + idx).write(paramTypes[idx]) }
            idx++
        }
        result = unsafe { LLVMFunctionType(returnType, paramPtr.value, UInt32(paramTypes.size), 0) }
    }
    return result
}

private func CreateTypeInfoForTemplateCallback(cgMod: CGModule, irBuilder: IRBuilder2, chirTy: Type,
    genericParams: ArrayList<GenericType>, runtimeTypeInfoArray: LLVMValueRef): LLVMValueRef {
    let baseTy = chirTy.StripAllRefs()
    if (let Some(genericTy) <- (baseTy as GenericType)) {
        if (let Some(genericIdx) <- FindGenericParamIndex(genericTy, genericParams)) {
            return GetRuntimeTypeInfoFromArray(cgMod, irBuilder, runtimeTypeInfoArray, genericIdx, genericTy)
        }
        return CGType.GetOrCreate(cgMod, baseTy).GetOrCreateTypeInfo()
    }
    if (ContainsGenericType(baseTy)) {
        return CreateRuntimeTypeInfoForTemplateCallback(cgMod, irBuilder, baseTy, genericParams, runtimeTypeInfoArray)
    }
    return CGType.GetOrCreate(cgMod, baseTy).GetOrCreateTypeInfo()
}

private func FindGenericParamIndex(genericTy: GenericType, genericParams: ArrayList<GenericType>): Option<Int64> {
    var idx: Int64 = 0
    while (idx < genericParams.size) {
        if (genericTy.IsEqual(genericParams[idx]) || genericTy.GetIdentifier() == genericParams[idx].GetIdentifier() ||
            genericTy.GetSrcCodeIdentifier() == genericParams[idx].GetSrcCodeIdentifier()) {
            return Some(idx)
        }
        idx++
    }
    return None
}

private func GetRuntimeTypeInfoFromArray(cgMod: CGModule, irBuilder: IRBuilder2, runtimeTypeInfoArray: LLVMValueRef,
    idx: Int64, genericTy: GenericType): LLVMValueRef {
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let i32Type = unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) }
    let indices = ArrayList<LLVMValueRef>()
    indices.add(unsafe { LLVMConstInt(i32Type, UInt64(idx), 0) })
    let typeInfoSlot = irBuilder.CreateGEP(typeInfoPtrType, runtimeTypeInfoArray, indices,
        name: "ti." + genericTy.GetSrcCodeIdentifier() + ".addr")
    return irBuilder.CreateLoad(typeInfoPtrType, typeInfoSlot, name: "ti." + genericTy.GetSrcCodeIdentifier())
}

private func CreateRuntimeTypeInfoForTemplateCallback(cgMod: CGModule, irBuilder: IRBuilder2, chirTy: Type,
    genericParams: ArrayList<GenericType>, runtimeTypeInfoArray: LLVMValueRef): LLVMValueRef {
    let (typeTemplate, typeArgs) = RuntimeTypeTemplateAndArgs(cgMod, chirTy)
    if (typeArgs.isEmpty()) {
        return CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeInfo()
    }
    let localTypeInfoArray = CreateTypeInfoArrayForTemplateCallback(cgMod, irBuilder, typeArgs, genericParams,
        runtimeTypeInfoArray)
    let i8Type = unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let callArgs = ArrayList<LLVMValueRef>()
    callArgs.add(irBuilder.CreateBitCast(typeTemplate, i8PtrType, name: "ti.template"))
    callArgs.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw), UInt64(typeArgs.size), 0) })
    callArgs.add(localTypeInfoArray)
    return CallGetTypeInfoIntrinsic(cgMod, irBuilder, callArgs)
}

private func RuntimeTypeTemplateAndArgs(cgMod: CGModule, chirTy: Type): (LLVMValueRef, ArrayList<Type>) {
    let typeArgs = ArrayList<Type>()
    if (let Some(tupleTy) <- (chirTy as TupleType)) {
        for (typeArg in tupleTy.GetTypeArgs()) {
            typeArgs.add(typeArg)
        }
        return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
    }
    if (let Some(funcTy) <- (chirTy as FuncType)) {
        typeArgs.add(funcTy.GetReturnType())
        for (paramTy in funcTy.GetParamTypes()) {
            typeArgs.add(paramTy)
        }
        return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
    }
    if (let Some(varrayTy) <- (chirTy as VArrayType)) {
        var idx: UInt64 = 0u64
        while (idx < varrayTy.size) {
            typeArgs.add(varrayTy.GetElementType())
            idx++
        }
        return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
    }
    if (let Some(rawArrayTy) <- (chirTy as RawArrayType)) {
        typeArgs.add(rawArrayTy.GetElementType())
        return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
    }
    if (let Some(cPointerTy) <- (chirTy as CPointerType)) {
        typeArgs.add(cPointerTy.GetElementType())
        return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
    }
    if (let Some(boxTy) <- (chirTy as BoxType)) {
        typeArgs.add(boxTy.GetBaseType())
        return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        let typeTemplate = EnsureSourceGenericTypeTemplate(cgMod, SourceCustomType(customTy))
        if (IsAutoEnvBaseType(customTy)) {
            let autoEnvTy = if (IsAutoEnvInstBaseType(customTy)) {
                if (let Some(classTy) <- (customTy as ClassType)) {
                    if (let Some(superTy) <- classTy.GetSuperClassTy()) {
                        superTy
                    } else {
                        classTy
                    }
                } else {
                    customTy
                }
            } else {
                customTy
            }
            let autoEnvArgs = autoEnvTy.GetGenericArgs()
            if (!autoEnvArgs.isEmpty()) {
                let paramTypes = ArrayList<Type>()
                var idx: Int64 = 0
                while (idx + 1 < autoEnvArgs.size) {
                    paramTypes.add(autoEnvArgs[idx])
                    idx++
                }
                typeArgs.add(FuncType(paramTypes, autoEnvArgs[autoEnvArgs.size - 1]))
            }
        } else {
            for (typeArg in customTy.GetGenericArgs()) {
                typeArgs.add(typeArg)
            }
        }
        return (typeTemplate, typeArgs)
    }
    return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
}

private func CreateTypeInfoArrayForTemplateCallback(cgMod: CGModule, irBuilder: IRBuilder2, typeArgs: ArrayList<Type>,
    genericParams: ArrayList<GenericType>, runtimeTypeInfoArray: LLVMValueRef): LLVMValueRef {
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let arrayType = unsafe { LLVMArrayType(typeInfoPtrType, UInt32(typeArgs.size)) }
    let slot = irBuilder.CreateEntryAlloca(arrayType, name: "ti.args")
    let i32Type = unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) }
    var idx: Int64 = 0
    while (idx < typeArgs.size) {
        let indices = ArrayList<LLVMValueRef>()
        indices.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
        indices.add(unsafe { LLVMConstInt(i32Type, UInt64(idx), 0) })
        let argSlot = irBuilder.CreateGEP(arrayType, slot, indices, name: "ti.arg")
        let argTypeInfo = irBuilder.CreatePointerCast(CreateTypeInfoForTemplateCallback(cgMod, irBuilder,
            typeArgs[idx], genericParams, runtimeTypeInfoArray), typeInfoPtrType, name: "ti.arg.cast")
        irBuilder.CreateStore(argTypeInfo, argSlot)
        idx++
    }
    return irBuilder.CreateBitCast(slot, unsafe { LLVMPointerType(typeInfoPtrType, 0u32) }, name: "ti.args.raw")
}

private func CallGetTypeInfoIntrinsic(cgMod: CGModule, irBuilder: IRBuilder2,
    args: ArrayList<LLVMValueRef>): LLVMValueRef {
    let i8Type = unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let i8PtrPtrType = unsafe { LLVMPointerType(i8PtrType, 0u32) }
    let i32Type = unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) }
    let paramTypes = ArrayList<LLVMTypeRef>()
    paramTypes.add(i8PtrType)
    paramTypes.add(i32Type)
    paramTypes.add(i8PtrPtrType)
    let functionType = BuildTypeInfoFunctionType(i8PtrType, paramTypes)
    let fixedArgs = ArrayList<LLVMValueRef>()
    fixedArgs.add(irBuilder.CreateBitCast(args[0], i8PtrType, name: "ti.template.raw"))
    fixedArgs.add(args[1])
    fixedArgs.add(irBuilder.CreateBitCast(args[2], i8PtrPtrType, name: "ti.args.i8"))
    return irBuilder.CreateCallOrInvoke(cgMod.GetOrInsertFunction(GET_TYPE_INFO_INTRINSIC_NAME, functionType),
        functionType, fixedArgs, name: "ti")
}

private func GetTypeTemplateFieldTypes(cgMod: CGModule, customTy: CustomType): ArrayList<Type> {
    let result = ArrayList<Type>()
    if (IsAutoEnvType(customTy)) {
        let intNativeTy = GetIntNativeRuntimeType(cgMod)
        result.add(intNativeTy)
        result.add(intNativeTy)
    }
    for (fieldTy in SourceCustomType(customTy).GetInstantiatedMemberTys()) {
        result.add(fieldTy)
    }
    return result
}

private func TypeTemplateSuperClassTy(classTy: ClassType): Option<ClassType> {
    if (let Some(superTy) <- classTy.GetSuperClassTy()) {
        return Some(superTy)
    }
    return None
}

private func SourceCustomType(customTy: CustomType): CustomType {
    if (let Some(sourceTy) <- customTy.GetCustomTypeDef().GetType()) {
        return sourceTy
    }
    return customTy
}

private func TypeTemplateInheritedClassNumValue(customTy: CustomType): UInt64 {
    if (IsAutoEnvType(customTy)) {
        return INHERITED_CLASS_NUM_FE_FLAG
    }
    return InheritedClassNumValue(customTy)
}

private func GetIntNativeRuntimeType(cgMod: CGModule): Type {
    let context = cgMod.GetCGContext().GetCHIRBuilder().context
    return if (cgMod.GetCGContext().GetCompileOptions().target.arch == ArchType.ARM32) {
        context.GetInt32Ty()
    } else {
        context.GetInt64Ty()
    }
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
    let fieldTypes = GetInstanceFieldTypes(cgMod, chirTy)
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
    let fieldTypes = GetInstanceFieldTypes(cgMod, chirTy)
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

public func GetInstanceFieldTypes(cgMod: CGModule, chirTy: Type): ArrayList<Type> {
    let result = ArrayList<Type>()
    if (let Some(enumTy) <- (chirTy as EnumType)) {
        return GetEnumTypeInfoFieldTypes(cgMod, enumTy)
    }
    if (chirTy.IsTuple()) {
        for (fieldTy in chirTy.GetTypeArgs()) {
            result.add(fieldTy)
        }
        return result
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        if (IsAutoEnvType(customTy)) {
            let intNativeTy = GetIntNativeRuntimeType(cgMod)
            result.add(intNativeTy)
            result.add(intNativeTy)
        }
        for (fieldTy in customTy.GetInstantiatedMemberTys()) {
            result.add(fieldTy)
        }
    }
    return result
}

private func GetEnumTypeInfoFieldTypes(cgMod: CGModule, enumTy: EnumType): ArrayList<Type> {
    let result = ArrayList<Type>()
    let builder = cgMod.GetCGContext().GetCHIRBuilder()
    if (let Some(enumCGType) <- (CGType.GetOrCreate(cgMod, enumTy) as CGEnumType)) {
        let enumKind = enumCGType.GetCGEnumTypeKind()
        if (enumKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED ||
            enumKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_OTHER) {
            result.add(builder.context.GetInt32Ty())
            return result
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF) {
            return result
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            result.add(builder.context.GetUnitTy())
            if (let Some(associatedTy) <- enumCGType.GetAssociatedValueTypeOfOptionLike()) {
                result.add(associatedTy)
            }
            return result
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            result.add(builder.context.GetBoolTy())
            if (let Some(associatedTy) <- enumCGType.GetAssociatedValueTypeOfOptionLike()) {
                result.add(associatedTy)
            }
            return result
        }
    }
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

private func TypeInfoSizeValue(cgMod: CGModule, chirTy: Type, cgType: CGType): UInt64 {
    if (let Some(enumCGType) <- (cgType as CGEnumType)) {
        let enumKind = enumCGType.GetCGEnumTypeKind()
        let context = cgMod.GetLLVMContext().raw
        if (enumKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED) {
            return cgMod.GetTypeSize(unsafe { LLVMInt32TypeInContext(context) })
        }
        if (enumKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_OTHER ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            return cgMod.GetTypeSize(CGType.GetRefType(cgMod.GetLLVMContext()))
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE) {
            return 0u64
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF) {
            if (let Some(unionSize) <- enumCGType.GetSizeOfConstructorUnion()) {
                return 4u64 + UInt64(unionSize)
            }
        }
    }
    if (chirTy.IsClass()) {
        return cgMod.GetTypeSize(cgType.GetLayoutType())
    }
    if (let Some(staticSize) <- cgType.GetSize()) {
        return UInt64(staticSize)
    }
    return 0u64
}

private func TypeInfoAlignValue(cgMod: CGModule, _: Type, cgType: CGType): UInt64 {
    if (let Some(enumCGType) <- (cgType as CGEnumType)) {
        let enumKind = enumCGType.GetCGEnumTypeKind()
        let context = cgMod.GetLLVMContext().raw
        if (enumKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED) {
            return UInt64(cgMod.GetABITypeAlignment(unsafe { LLVMInt32TypeInContext(context) }))
        }
        if (enumKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_OTHER ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            return UInt64(cgMod.GetABITypeAlignment(CGType.GetRefType(cgMod.GetLLVMContext())))
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE) {
            return 1u64
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF) {
            return if (cgMod.GetCGContext().GetCompileOptions().target.arch == ArchType.ARM32 &&
                cgMod.GetCGContext().GetCompileOptions().target.env == EnvironmentType.ANDROID) {
                4u64
            } else {
                1u64
            }
        }
    }
    if (let Some(staticAlign) <- cgType.GetAlign()) {
        return UInt64(staticAlign)
    }
    return 0u64
}

private func TypeInfoKind(cgMod: CGModule, chirTy: Type): UInt64 {
    if (let Some(classTy) <- (chirTy as ClassType)) {
        if (IsWeakRefClass(classTy)) {
            return UG_WEAKREF_KIND
        }
        return if (classTy.GetClassDef().IsInterface()) { UG_INTERFACE_KIND } else { UG_CLASS_KIND }
    }
    if (chirTy.IsTuple()) { return UG_TUPLE_KIND }
    if (chirTy.IsStruct()) { return UG_STRUCT_KIND }
    if (chirTy.IsEnum()) {
        if (let Some(enumCGType) <- (CGType.GetOrCreate(cgMod, chirTy) as CGEnumType)) {
            return if (enumCGType.IsCommonEnum()) { UG_COMMON_ENUM_KIND } else { UG_ENUM_KIND }
        }
        return UG_ENUM_KIND
    }
    return 0u64
}

private func IsWeakRefClass(classTy: ClassType): Bool {
    let def = classTy.GetClassDef()
    let packageName = if (let Some(genericDecl) <- def.GetGenericDecl()) {
        genericDecl.GetPackageName()
    } else {
        def.GetPackageName()
    }
    return packageName == REF_PACKAGE_NAME && def.GetSrcCodeIdentifier() == STD_LIB_WEAK_REF
}

private func IsEqualOrInstantiatedTypeOf(actualTy: Type, genericRelatedTy: Type): Bool {
    if (actualTy.IsEqual(genericRelatedTy)) {
        return true
    }
    if (genericRelatedTy.IsGeneric()) {
        return true
    }
    if (TypeKindIndex(actualTy.GetTypeKind()) != TypeKindIndex(genericRelatedTy.GetTypeKind())) {
        return false
    }
    if (!SameCustomTypeDef(actualTy, genericRelatedTy)) {
        return false
    }
    let actualArgs = actualTy.GetTypeArgs()
    let genericArgs = genericRelatedTy.GetTypeArgs()
    if (actualArgs.size != genericArgs.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < actualArgs.size) {
        if (!IsEqualOrInstantiatedTypeOf(actualArgs[idx], genericArgs[idx])) {
            return false
        }
        idx++
    }
    return true
}

private func SameCustomTypeDef(left: Type, right: Type): Bool {
    if (let Some(leftCustom) <- (left as CustomType)) {
        if (let Some(rightCustom) <- (right as CustomType)) {
            return leftCustom.GetCustomTypeDef().nodeId == rightCustom.GetCustomTypeDef().nodeId
        }
        return false
    }
    return true
}

private func InheritedClassNumValue(chirTy: Type): UInt64 {
    return INHERITED_CLASS_NUM_FE_FLAG + InheritedClassNumBase(chirTy)
}

private func InheritedClassNumBase(chirTy: Type): UInt64 {
    if (let Some(classTy) <- (chirTy as ClassType)) {
        return UInt64(ClassInheritanceDepth(classTy))
    }
    return 0u64
}

private func ClassInheritanceDepth(classTy: ClassType): Int64 {
    if (classTy.GetClassDef().IsInterface()) {
        return 0
    }
    var count: Int64 = if (IsCoreObjectClass(classTy)) { 1 } else { 2 }
    var current = classTy.GetSuperClassTy()
    while (let Some(superTy) <- current) {
        if (!superTy.GetClassDef().IsInterface()) {
            count++
        }
        current = superTy.GetSuperClassTy()
    }
    return count
}

private func GenerateExtensionDefPtrOfTypeInfo(cgMod: CGModule, chirTy: Type,
    extensionDefPtrPtrType: LLVMTypeRef): LLVMValueRef {
    if (let Some(startIdx) <- cgMod.GetExtensionDefStart(chirTy)) {
        let defs = cgMod.GetNonExternalExtensionDefs()
        if (!defs.isEmpty()) {
            let extensionDefPtrType = CGType.GetOrCreateExtensionDefPtrType(cgMod.GetLLVMContext())
            let arrayType = unsafe { LLVMArrayType(extensionDefPtrType, UInt32(defs.size + 1)) }
            let table = GetOrInsertCodeGenGlobal(cgMod, "NonExternalExtensionDefs", arrayType)
            let i32Type = unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) }
            let zero = unsafe { LLVMConstInt(i32Type, 0u64, 0) }
            let index = unsafe { LLVMConstInt(i32Type, UInt64(startIdx), 0) }
            return TypeInfoConstInBoundsGEP2(arrayType, table, zero, index)
        }
    }
    return unsafe { LLVMConstNull(extensionDefPtrPtrType) }
}

private func GenerateMTableOfTypeInfo(cgMod: CGModule, chirTy: Type, i8PtrType: LLVMTypeRef,
    inheritedClassNum: UInt64): (LLVMValueRef, UInt64) {
    if ((inheritedClassNum >> 14u64) != 0u64 || cgMod.GetExtensionDefStart(chirTy).isNone()) {
        return (unsafe { LLVMConstNull(i8PtrType) }, inheritedClassNum)
    }
    let extendInterfaces = cgMod.GetExtensionDefInterfaces(chirTy)
    if (cgMod.GetCGContext().GetCompileOptions().target.arch == ArchType.ARM32 ||
        extendInterfaces.size >= MTABLE_INLINE_BITS_LIMIT) {
        return (unsafe { LLVMConstNull(i8PtrType) }, inheritedClassNum)
    }
    var bitValue = 0u64
    var bitmapIdx: Int64 = 0
    var updatedInheritedClassNum = inheritedClassNum
    if (chirTy.GetTypeArgs().isEmpty()) {
        while (bitmapIdx < extendInterfaces.size) {
            bitValue |= 1u64 << UInt64(bitmapIdx)
            bitmapIdx++
        }
    } else {
        var foundFirstCandidate = false
        for (interfaceInfo in extendInterfaces) {
            let matches = if (let Some(candidateTy) <- interfaceInfo.candidateTy) {
                IsEqualOrInstantiatedTypeOf(chirTy, candidateTy)
            } else {
                true
            }
            if (matches) {
                bitValue |= 1u64 << UInt64(bitmapIdx)
                foundFirstCandidate = true
            }
            if (foundFirstCandidate) {
                bitmapIdx++
            } else {
                updatedInheritedClassNum++
            }
        }
    }
    let i64Type = unsafe { LLVMInt64TypeInContext(cgMod.GetLLVMContext().raw) }
    let inlineBitmap = TYPEINFO_MTABLE_INLINE_FLAG | bitValue
    return (unsafe { LLVMConstIntToPtr(LLVMConstInt(i64Type, inlineBitmap, 0), i8PtrType) },
        updatedInheritedClassNum)
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
        if (classTy.GetClassDef().IsInterface()) {
            return unsafe { LLVMConstNull(typeInfoPtrType) }
        }
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
