package cjcj::codegen

import std.collection.*
import cjcj::basic.Linkage
import cjcj::chir.Attribute
import cjcj::chir.BooleanType
import cjcj::chir.BoxType
import cjcj::chir.ClassDef
import cjcj::chir.ClassType
import cjcj::chir.CPointerType
import cjcj::chir.CustomType
import cjcj::chir.CustomTypeDef
import cjcj::chir.EnumDef
import cjcj::chir.EnumType
import cjcj::chir.FuncType
import cjcj::chir.GenericType
import cjcj::chir.LinkTypeInfo
import cjcj::chir.RawArrayType
import cjcj::chir.RefType
import cjcj::chir.StructDef
import cjcj::chir.StructType
import cjcj::chir.Type
import cjcj::chir.TypeKindIndex
import cjcj::chir.TupleType
import cjcj::chir.VArrayType
import cjcj::chir.{GetCustomTypeIdentifier, GetTypeQualifiedName}
import cjcj::option.{ArchType, EnvironmentType, OSType}
import cjcj::utils.{CJC_ASSERT, REF_PACKAGE_NAME, STD_LIB_WEAK_REF, StaticCast}

private let UG_CLASS_KIND: UInt64 = 128u64
private let UG_INTERFACE_KIND: UInt64 = 129u64
private let UG_RAW_ARRAY_KIND: UInt64 = 130u64
private let UG_COMMON_ENUM_KIND: UInt64 = 132u64
private let UG_WEAKREF_KIND: UInt64 = 133u64
private let UG_FUNC_KIND: UInt64 = 131u64
private let UG_GENERIC_CUSTOM_KIND: UInt64 = 254u64
private let UG_GENERIC_KIND: UInt64 = 255u64
private let UG_CSTRING: UInt64 = 17u64
private let UG_CPOINTER: UInt64 = 18u64
private let UG_CFUNC: UInt64 = 19u64
private let UG_VARRAY: UInt64 = 20u64
private let UG_TUPLE_KIND: UInt64 = 21u64
private let LLVM_STRUCT_TYPE_KIND: Int32 = 10
private let UG_STRUCT_KIND: UInt64 = 22u64
private let UG_ENUM_KIND: UInt64 = 23u64
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

public func GetOrCreateTypeInfoGlobal(cgMod: CGModule, chirTy: Type, genericKind: CGGenericKind): LLVMValueRef {
    let typeInfo = DeclareTypeInfoGlobal(cgMod, chirTy, genericKind)
    DefineTypeInfoGlobalIfNeeded(cgMod, chirTy, typeInfo)
    return typeInfo
}

public func DeclareTypeInfoGlobal(cgMod: CGModule, chirTy: Type, genericKind: CGGenericKind): LLVMValueRef {
    let typeInfoTy = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
    let typeInfoName = TypeInfoGlobalName(cgMod, chirTy)
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
    if (genericKind == CGGenericKind.STATIC_GI || genericKind == CGGenericKind.CONCRETE) {
        addAttribute(typeInfo, GC_KLASS_ATTR)
        if (!IsModifiableClass(chirTy)) {
            addAttribute(typeInfo, NOT_MODIFIABLE_CLASS_ATTR)
        }
    }
    if (chirTy.IsPrimitive() || chirTy.IsVoid() || chirTy.IsCString() || chirTy.IsCPointer()) {
        // C++ attaches the GC-layout metadata from the CGType's layout struct name (CGType::GenTypeInfo,
        // CGType.cpp:623/634): primitives/void/CString use "<type>.Type"; every CPointer<T> shares the
        // single "CPointer.Type" layout (CGCPointerType.cpp:21-24), so its metadata is that fixed name.
        let layoutName = if (chirTy.IsVoid()) {
            UNIT_TYPE_STR
        } else if (chirTy.IsCPointer()) {
            "CPointer.Type"
        } else {
            chirTy.ToString() + ".Type"
        }
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
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        try (nameCString = unsafe { LibC.mallocCString(typeInfoName) }.asResource()) {
            let found = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
            if (!found.isNull()) {
                return found
            }
        }
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
        values.add(cgMod.GenerateTypeNameConstantString(genericTy.GetSrcCodeIdentifier(), false))
        values.add(unsafe { LLVMConstInt(i8Type, UG_GENERIC_KIND, 0) })
        values.add(unsafe { LLVMConstInt(i32Type, UInt64(genericTy.GetUpperBounds().size), 0) })
        values.add(GenerateUpperBoundsOfGenericTypeInfo(cgMod, genericTy, typeInfoName))
        unsafe {
            LLVMSetInitializer(typeInfo, TypeInfoConstStruct(typeInfoTy, values))
            LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.Private))
            addAttribute(typeInfo, GENERIC_TYPEINFO_ATTR)
            LLVMSetGlobalConstant(typeInfo, 0)
        }
    }
    return typeInfo
}

public func GetOrCreateGenericCustomTypeInfoGlobal(cgMod: CGModule, chirTy: Type): LLVMValueRef {
    let typeInfoTy = GetOrCreateGenericCustomTypeInfoType(cgMod.GetLLVMContext())
    let qualifiedName = GetTypeQualifiedNameForReflect(cgMod, chirTy, forNameFieldOfTi: true)
    let typeInfoName = qualifiedName + ".ti"
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        try (nameCString = unsafe { LibC.mallocCString(typeInfoName) }.asResource()) {
            let found = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
            if (!found.isNull()) {
                return found
            }
        }
    }
    let typeInfo = GetOrInsertCodeGenGlobal(cgMod, typeInfoName, typeInfoTy)
    if (typeInfo.isNull()) {
        return typeInfo
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let context = cgMod.GetLLVMContext().raw
        let i8Type = unsafe { LLVMInt8TypeInContext(context) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let values = ArrayList<LLVMValueRef>()
        values.add(cgMod.GenerateTypeNameConstantString(GetTypeQualifiedName(chirTy, forNameFieldOfTi: true), false))
        values.add(unsafe { LLVMConstInt(i8Type, UG_GENERIC_CUSTOM_KIND, 0) })
        values.add(unsafe { LLVMConstInt(i8Type, GenTypeArgsNumOfGenericCustomTypeInfo(cgMod, chirTy), 0) })
        values.add(GenTypeArgsOfGenericCustomTypeInfo(cgMod, chirTy))
        values.add(unsafe { LLVMConstBitCast(CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), i8PtrType) })
        unsafe {
            LLVMSetInitializer(typeInfo, TypeInfoConstStruct(typeInfoTy, values))
            LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.Private))
            addAttribute(typeInfo, GENERIC_TYPEINFO_ATTR)
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
    addAttribute(upperBoundsGlobal, CJTI_UPPER_BOUNDS_ATTR)
    return unsafe { LLVMConstBitCast(upperBoundsGlobal, i8PtrType) }
}

private func GenTypeArgsOfGenericCustomTypeInfo(cgMod: CGModule, chirTy: Type): LLVMValueRef {
    let i8Type = unsafe { LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let typeArgs = ArrayList<Type>()
    if (let Some(customTy) <- (chirTy as CustomType)) {
        for (typeArg in customTy.GetGenericArgs()) {
            typeArgs.add(typeArg)
        }
    } else if (let Some(tupleTy) <- (chirTy as TupleType)) {
        for (typeArg in tupleTy.GetTypeArgs()) {
            typeArgs.add(typeArg)
        }
    } else if (let Some(funcTy) <- (chirTy as FuncType)) {
        typeArgs.add(funcTy.GetReturnType())
        for (paramTy in funcTy.GetParamTypes()) {
            typeArgs.add(paramTy)
        }
    } else if (let Some(cPointerTy) <- (chirTy as CPointerType)) {
        typeArgs.add(cPointerTy.GetElementType())
    } else if (let Some(vArrayTy) <- (chirTy as VArrayType)) {
        var idx: UInt64 = 0u64
        while (idx < vArrayTy.GetSize()) {
            typeArgs.add(vArrayTy.GetElementType())
            idx++
        }
    }
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
    let typeArgsGlobal = GetOrInsertCodeGenGlobal(cgMod,
        GetTypeQualifiedNameForReflect(cgMod, chirTy) + ".ti.typeArgs", arrayType)
    if (unsafe { LLVMIsDeclaration(typeArgsGlobal) } != 0) {
        unsafe {
            LLVMSetInitializer(typeArgsGlobal, ConstArray(i8PtrType, values))
            LLVMSetLinkage(typeArgsGlobal, LLVMLinkageValue(LLVMLinkage.Private))
        }
    }
    return unsafe { LLVMConstBitCast(typeArgsGlobal, i8PtrType) }
}

private func GenTypeArgsNumOfGenericCustomTypeInfo(cgMod: CGModule, chirTy: Type): UInt64 {
    if (let Some(vArrayTy) <- (chirTy as VArrayType)) {
        return vArrayTy.GetSize()
    }
    return GenTypeArgsNumOfTypeInfo(cgMod, chirTy)
}

private func GetTypeArgsQualifiedNameForReflect(cgMod: CGModule, typeArgs: ArrayList<Type>,
    forNameFieldOfTi!: Bool): String {
    var out = ""
    var idx: Int64 = 0
    for (typeArg in typeArgs) {
        if (idx > 0) {
            out += ","
        }
        out += GetTypeQualifiedNameForReflect(cgMod, typeArg, forNameFieldOfTi: forNameFieldOfTi)
        idx++
    }
    return out
}

private func GetTypeQualifiedNameOfCustomTypeForReflect(cgMod: CGModule, customTy: CustomType,
    forNameFieldOfTi!: Bool): String {
    let def = customTy.GetCustomTypeDef()
    // CGType.cpp:962 uses type.IsAutoEnvGenericBase(); Type.cpp:85.
    if (customTy.IsAutoEnvGenericBase()) {
        let typeArgs = customTy.GetGenericArgs()
        CJC_ASSERT(!typeArgs.isEmpty())
        let paramTypes = ArrayList<Type>()
        var idx: Int64 = 0
        while (idx + 1 < typeArgs.size) {
            paramTypes.add(typeArgs[idx])
            idx++
        }
        return "Closure<(" + GetTypeArgsQualifiedNameForReflect(cgMod, paramTypes, forNameFieldOfTi: true) + ")->" +
            GetTypeQualifiedNameForReflect(cgMod, typeArgs[typeArgs.size - 1], forNameFieldOfTi: true) + ">"
    }
    let packageName = if (let Some(genericDecl) <- def.GetGenericDecl()) {
        genericDecl.GetPackageName()
    } else {
        def.GetPackageName()
    }
    var out = packageName + ":" + GetCustomTypeIdentifier(customTy)
    let typeArgs = customTy.GetGenericArgs()
    if (!typeArgs.isEmpty()) {
        out += "<" + GetTypeArgsQualifiedNameForReflect(cgMod, typeArgs,
            forNameFieldOfTi: forNameFieldOfTi) + ">"
    }
    return out
}

private func GetTypeQualifiedNameForReflect(cgMod: CGModule, chirTy: Type,
    forNameFieldOfTi!: Bool = false): String {
    let stripped = chirTy.StripAllRefs()
    if (stripped.IsPrimitive()) {
        return stripped.ToString()
    }
    if (let Some(rawArrayTy) <- (stripped as RawArrayType)) {
        return "RawArray<" + GetTypeQualifiedNameForReflect(cgMod, rawArrayTy.GetElementType(),
            forNameFieldOfTi: forNameFieldOfTi) + ">"
    }
    if (let Some(vArrayTy) <- (stripped as VArrayType)) {
        return "VArray<" + GetTypeQualifiedNameForReflect(cgMod, vArrayTy.GetElementType(),
            forNameFieldOfTi: forNameFieldOfTi) + "," + "${vArrayTy.GetSize()}" + ">"
    }
    if (let Some(cPointerTy) <- (stripped as CPointerType)) {
        return "CPointer<" + GetTypeQualifiedNameForReflect(cgMod, cPointerTy.GetElementType(),
            forNameFieldOfTi: forNameFieldOfTi) + ">"
    }
    if (stripped.IsCString()) {
        return "CString"
    }
    if (let Some(tupleTy) <- (stripped as TupleType)) {
        return "Tuple<" + GetTypeArgsQualifiedNameForReflect(cgMod, tupleTy.GetTypeArgs(),
            forNameFieldOfTi: forNameFieldOfTi) + ">"
    }
    if (let Some(customTy) <- (stripped as CustomType)) {
        return GetTypeQualifiedNameOfCustomTypeForReflect(cgMod, customTy,
            forNameFieldOfTi: forNameFieldOfTi)
    }
    if (let Some(funcTy) <- (stripped as FuncType)) {
        return "(" + GetTypeArgsQualifiedNameForReflect(cgMod, funcTy.GetParamTypes(),
            forNameFieldOfTi: forNameFieldOfTi) + ")->" +
            GetTypeQualifiedNameForReflect(cgMod, funcTy.GetReturnType(), forNameFieldOfTi: forNameFieldOfTi)
    }
    if (let Some(genericTy) <- (stripped as GenericType)) {
        return GenericTypeInfoName(cgMod, genericTy)
    }
    if (stripped.IsVoid()) {
        return UNIT_TYPE_STR
    }
    if (let Some(boxTy) <- (stripped as BoxType)) {
        let typeQualifiedName = GetTypeQualifiedNameForReflect(cgMod, boxTy.GetBaseType(),
            forNameFieldOfTi: forNameFieldOfTi)
        return if (forNameFieldOfTi) { typeQualifiedName } else { "Box<" + typeQualifiedName + ">" }
    }
    throw IllegalArgumentException("unexpected type for reflect qualified name: " + stripped.ToString())
}

public func RedefineTypeInfoGlobal(cgMod: CGModule, chirTy: Type): Unit {
    if (!(chirTy.IsClass() || chirTy.IsStruct() || chirTy.IsEnum() || chirTy.IsTuple())) {
        return
    }
    if (IsImportedCustomType(chirTy)) {
        return
    }
    if (!OwnsCustomDeclTypeInfo(cgMod, chirTy)) {
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
    if (cgMod.GetLLVMModule().isSome()) {
        let initializer = BuildConcreteTypeInfoInitializer(cgMod, chirTy, typeInfo, typeInfoTy)
        unsafe {
            LLVMSetInitializer(typeInfo, initializer)
            SetConcreteTypeInfoLinkage(cgMod, typeInfo, chirTy)
        }
        LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), typeInfo, GC_TYPE_META_NAME,
            GetLayoutMetadataName(cgMod, chirTy))
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
        if (cgMod.GetLLVMModule().isSome()) {
            let initializer = BuildRawArrayTypeInfoInitializer(cgMod, chirTy, typeInfoTy)
            unsafe {
                LLVMSetInitializer(typeInfo, initializer)
                LLVMSetLinkage(typeInfo, LLVMLinkageValue(LLVMLinkage.LinkOnceODR))
                LLVMSetGlobalConstant(typeInfo, 0)
            }
        }
        return
    }
    if (!(chirTy.IsClass() || chirTy.IsStruct() || chirTy.IsEnum() || chirTy.IsTuple() || chirTy.IsFunc() ||
        chirTy.IsVArray() || chirTy.IsCPointer())) {
        return
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        if (customTy.GetCustomTypeDef().TestAttr(Attribute.IMPORTED) &&
            CGType.GetCGGenericKind(chirTy) == CGGenericKind.CONCRETE) {
            return
        }
        if (!OwnsCustomDeclTypeInfo(cgMod, chirTy)) {
            return
        }
    }
    if (IsGenericRelatedCustomType(chirTy)) {
        return
    }
    if (cgMod.GetLLVMModule().isSome()) {
        let initializer = BuildConcreteTypeInfoInitializer(cgMod, chirTy, typeInfo, typeInfoTy)
        unsafe {
            LLVMSetInitializer(typeInfo, initializer)
            SetConcreteTypeInfoLinkage(cgMod, typeInfo, chirTy)
        }
        LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), typeInfo, GC_TYPE_META_NAME,
            GetLayoutMetadataName(cgMod, chirTy))
    }
}

private func IsGenericRelatedCustomType(chirTy: Type): Bool {
    // Faithful to C++ !IsDynamicGI() (CGType.cpp:616 GenTypeInfo asserts !IsDynamicGI): any
    // generic-related (DYNAMIC_GI) type — including non-CustomType generic tuples like
    // (Generic-K, Generic-V) — must NOT get a concrete static %TypeInfo. STATIC_GI types
    // (e.g. ArrayList<String>) have IsGenericRelated()==false and are still emitted.
    return chirTy.IsGenericRelated()
}

private func OwnsCustomDeclTypeInfo(cgMod: CGModule, chirTy: Type): Bool {
    if (let Some(customTy) <- (chirTy.StripAllRefs() as CustomType)) {
        if (!customTy.GetGenericArgs().isEmpty()) {
            return true
        }
        let def = customTy.GetCustomTypeDef()
        if (let Some(genericDecl) <- def.GetGenericDecl()) {
            return cgMod.OwnsCustomTypeDef(genericDecl)
        }
        return cgMod.OwnsCustomTypeDef(def)
    }
    return true
}

private func SetConcreteTypeInfoLinkage(cgMod: CGModule, typeInfo: LLVMValueRef, chirTy: Type): Unit {
    if (CGType.GetCGGenericKind(chirTy) == CGGenericKind.STATIC_GI) {
        let staticGILinkage = if (cgMod.GetCGContext().GetCompileOptions().target.os == OSType.WINDOWS) {
            LLVMLinkage.Internal
        } else {
            LLVMLinkage.LinkOnceODR
        }
        unsafe {
            LLVMSetLinkage(typeInfo, LLVMLinkageValue(staticGILinkage))
            LLVMSetGlobalConstant(typeInfo, 0)
        }
        return
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        let chirLinkage = customTy.GetCustomTypeDef().Get<LinkTypeInfo, Linkage>()
        AddLinkageTypeMetadata(typeInfo, CHIRLinkage2LLVMLinkage(chirLinkage),
            cgMod.GetCGContext().IsCGParallelEnabled())
        unsafe { LLVMSetGlobalConstant(typeInfo, 0) }
        return
    }
    let fallbackLinkage = if (chirTy.GetTypeArgs().isEmpty()) {
        if (ShouldExportTypeInfo(chirTy)) { LLVMLinkage.External } else { LLVMLinkage.LinkOnceODR }
    } else {
        LLVMLinkage.LinkOnceODR
    }
    unsafe {
        LLVMSetLinkage(typeInfo, LLVMLinkageValue(fallbackLinkage))
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

private func BuildRawArrayTypeInfoInitializer(cgMod: CGModule, chirTy: Type, typeInfoTy: LLVMTypeRef): LLVMValueRef {
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
    typeInfoValues.add(cgMod.GenerateTypeNameConstantString(GetTypeQualifiedName(chirTy, forNameFieldOfTi: true),
        false))
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

private func BuildConcreteTypeInfoInitializer(cgMod: CGModule, chirTy: Type, typeInfo: LLVMValueRef,
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
    let typeInfoName = TypeInfoGlobalName(cgMod, chirTy)
    let fieldCount = GenFieldsNumOfTypeInfo(cgMod, chirTy)
    var inheritedClassNum = InheritedClassNumBase(chirTy)
    let (mtable, updatedInheritedClassNum) = GenerateMTableOfTypeInfo(cgMod, chirTy, i8PtrType, inheritedClassNum)
    inheritedClassNum = updatedInheritedClassNum
    let sizeValue = TypeInfoSizeValue(cgMod, chirTy, cgType)
    let alignValue = TypeInfoAlignValue(cgMod, chirTy, cgType)
    let typeInfoValues = ArrayList<LLVMValueRef>()
    typeInfoValues.add(cgMod.GenerateTypeNameConstantString(TypeInfoRuntimeName(cgMod, chirTy), false))
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, TypeInfoKind(cgMod, chirTy), 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, fieldCount, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, sizeValue, 0) })
    typeInfoValues.add(unsafe { LLVMConstNull(bitMapPtrType) })
    typeInfoValues.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, alignValue, 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i8Type, GenTypeArgsNumOfTypeInfo(cgMod, chirTy), 0) })
    typeInfoValues.add(unsafe { LLVMConstInt(i16Type, inheritedClassNum + INHERITED_CLASS_NUM_FE_FLAG, 0) })
    typeInfoValues.add(GenerateOffsetsOfTypeInfo(cgMod, chirTy, cgType, typeInfoName, i32PtrType))
    typeInfoValues.add(GenerateSourceGenericOfTypeInfo(cgMod, chirTy, i8PtrType))
    typeInfoValues.add(GenerateTypeArgsOfTypeInfo(cgMod, chirTy, typeInfo, typeInfoName, i8PtrType))
    typeInfoValues.add(GenerateFieldsOfTypeInfo(cgMod, chirTy, typeInfoName, i8PtrType))
    typeInfoValues.add(GenerateSuperOfTypeInfo(cgMod, chirTy, typeInfo, typeInfoPtrType))
    typeInfoValues.add(GenerateExtensionDefPtrOfTypeInfo(cgMod, chirTy, extensionDefPtrPtrType))
    typeInfoValues.add(mtable)
    typeInfoValues.add(unsafe { LLVMConstNull(i8PtrType) })
    return TypeInfoConstStruct(typeInfoTy, typeInfoValues)
}

private func GenerateSourceGenericOfTypeInfo(cgMod: CGModule, chirTy: Type, i8PtrType: LLVMTypeRef): LLVMValueRef {
    let cgType = CGType.GetOrCreate(cgMod, chirTy)
    if (let Some(classTy) <- (chirTy as ClassType)) {
        if (let Some(finalizer) <- classTy.GetClassDef().GetFinalizer()) {
            if (!cgType.IsStaticGI()) {
                CJC_ASSERT(classTy.GetGenericArgs().isEmpty())
                return unsafe { LLVMConstBitCast(cgMod.GetOrInsertCGFunction(finalizer).GetRawFunction(), i8PtrType) }
            }
        }
    }
    if (cgType.IsStaticGI()) {
        let typeTemplate = cgType.GetOrCreateTypeTemplate()
        return unsafe { LLVMConstBitCast(typeTemplate, i8PtrType) }
    }
    return unsafe { LLVMConstNull(i8PtrType) }
}

public func EnsureSourceGenericTypeTemplate(cgMod: CGModule, customTy: CustomType): LLVMValueRef {
    let sourceTy = StaticCast<CustomType>(customTy.GetCustomTypeDef().GetType().getOrThrow())
    return CGType.GetOrCreate(cgMod, sourceTy).GetOrCreateTypeTemplate()
}

public func DefineCustomTypeTemplateIfNeeded(cgMod: CGModule, customTy: CustomType,
    typeTemplate: LLVMValueRef): Unit {
    let sourceTy = SourceCustomType(customTy)
    let typeTemplateTy = CGType.GetOrCreateTypeTemplateType(cgMod.GetLLVMContext())
    let typeTemplateName = SourceGenericTypeTemplateName(sourceTy)
    if (cgMod.GetCGContext().IsCustomTypeOfOtherLLVMModule(sourceTy) || IsAutoEnvBaseType(sourceTy)) {
        if (LinkageOfCustomTypeDef(sourceTy.GetCustomTypeDef()) == Linkage.EXTERNAL_WEAK) {
            unsafe { LLVMSetLinkage(typeTemplate, LLVMLinkageValue(LLVMLinkage.ExternalWeak)) }
        }
        return
    }
    if (IsRuntimeOwnedTypeTemplate(typeTemplateName)) {
        unsafe { LLVMSetLinkage(typeTemplate, LLVMLinkageValue(LLVMLinkage.External)) }
        return
    }
    if (!typeTemplate.isNull() && unsafe { LLVMIsDeclaration(typeTemplate) } != 0) {
        let linkageType = TypeTemplateLinkage(sourceTy.GetCustomTypeDef())
        if (cgMod.GetLLVMModule().isSome()) {
            unsafe {
                LLVMSetInitializer(typeTemplate,
                    BuildSourceGenericTypeTemplateInitializer(cgMod, sourceTy, typeTemplateTy, typeTemplateName))
                addAttribute(typeTemplate, TYPE_TEMPLATE_ATTR)
                AddLinkageTypeMetadata(typeTemplate, linkageType, cgMod.GetCGContext().IsCGParallelEnabled())
            }
        }
    }
}

public func RefreshSourceGenericTypeTemplateInitializer(cgMod: CGModule, customTy: CustomType): Unit {
    let sourceTy = StaticCast<CustomType>(customTy.GetCustomTypeDef().GetType().getOrThrow())
    if (sourceTy.GetGenericArgs().isEmpty() || sourceTy.GetCustomTypeDef().TestAttr(Attribute.IMPORTED)) {
        return
    }
    let _ = CGType.GetOrCreate(cgMod, sourceTy).GetOrCreateTypeTemplate()
}

private func SourceGenericTypeTemplateName(customTy: CustomType): String {
    return CGType.GetNameOfTypeTemplateGV(SourceCustomType(customTy))
}

private func IsRuntimeOwnedTypeTemplate(typeTemplateName: String): Bool {
    return typeTemplateName == "Tuple.tt" || typeTemplateName == "VArray.tt" ||
        typeTemplateName == "RawArray.tt" || typeTemplateName == "CPointer.tt" ||
        typeTemplateName == "CFunc.tt" || typeTemplateName == "Closure.tt"
}

private func SourceGenericTypeTemplateRuntimeName(customTy: CustomType): String {
    let templateName = SourceGenericTypeTemplateName(customTy)
    if (templateName.endsWith(".tt")) {
        return templateName[0..(templateName.size - 3)]
    }
    return templateName
}

private func ReplaceDelimiterAfterOrgName(typeName: String): String {
    if (let Some(splitter) <- typeName.indexOf("::")) {
        return typeName[0..splitter] + "/" + typeName[splitter + 2..]
    }
    return typeName
}

private func BuildSourceGenericTypeTemplateInitializer(cgMod: CGModule, customTy: CustomType,
    typeTemplateTy: LLVMTypeRef, typeTemplateName: String): LLVMValueRef {
    let sourceTy = SourceCustomType(customTy)
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i16Type = unsafe { LLVMInt16TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let extensionDefPtrPtrType = unsafe {
        LLVMPointerType(CGType.GetOrCreateExtensionDefPtrType(cgMod.GetLLVMContext()), 0u32)
    }
    let values = ArrayList<LLVMValueRef>()
    let runtimeName = SourceGenericTypeTemplateRuntimeName(sourceTy)
    values.add(cgMod.GenerateTypeNameConstantString(runtimeName, false,
        qualifiedName: ReplaceDelimiterAfterOrgName(runtimeName)))
    values.add(unsafe { LLVMConstInt(i8Type, TypeInfoKind(cgMod, sourceTy), 0) })
    values.add(unsafe { LLVMConstInt(i8Type, 0u64, 0) })
    let fieldNum = UInt64(GetTypeTemplateFieldTypes(cgMod, sourceTy).size)
    values.add(unsafe { LLVMConstInt(i16Type, fieldNum, 0) })
    values.add(unsafe { LLVMConstInt(i16Type, UInt64(sourceTy.GetGenericArgs().size), 0) })
    values.add(GenerateFieldsFnsOfTypeTemplate(cgMod, sourceTy, typeTemplateName, i8PtrType))
    values.add(GenerateSuperFnOfTypeTemplate(cgMod, sourceTy, typeTemplateName, i8PtrType))
    values.add(GenerateFinalizerOfTypeTemplate(cgMod, sourceTy, i8PtrType))
    values.add(unsafe { LLVMConstNull(i8PtrType) })
    values.add(GenerateExtensionDefPtrOfTypeInfo(cgMod, sourceTy, extensionDefPtrPtrType))
    values.add(unsafe { LLVMConstInt(i16Type, TypeTemplateInheritedClassNumValue(sourceTy), 0) })
    return TypeInfoConstStruct(typeTemplateTy, values)
}

private func GenerateFieldsFnsOfTypeTemplate(cgMod: CGModule, customTy: CustomType, typeTemplateName: String,
    i8PtrType: LLVMTypeRef): LLVMValueRef {
    let sourceTy = SourceCustomType(customTy)
    if (let Some(enumTy) <- (sourceTy as EnumType)) {
        if (let Some(enumCGType) <- (CGType.GetOrCreate(cgMod, enumTy) as CGEnumType)) {
            if (enumCGType.IsOptionLikeT()) {
                return enumCGType.GenFieldsFnsOfTypeTemplateForOptionLikeT(cgMod, typeTemplateName)
            }
        }
    }
    let fieldTypes = GetTypeTemplateFieldTypes(cgMod, sourceTy)
    if (fieldTypes.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let fieldFnType = GetTypeTemplateCallbackFunctionType(cgMod)
    let fieldFns = ArrayList<LLVMValueRef>()
    let genericParams = TypeTemplateGenericParams(sourceTy)
    var idx: Int64 = 0
    while (idx < fieldTypes.size) {
        fieldFns.add(GenerateTypeTemplateTypeInfoFn(cgMod, fieldFnType, typeTemplateName + ".fieldTiFn." +
            idx.toString(), fieldTypes[idx], genericParams))
        idx++
    }
    return GenFieldsFnsOfTypeTemplate(cgMod, typeTemplateName, fieldFns)
}

public func GenFieldsFnsOfTypeTemplate(cgMod: CGModule, funcPrefixName: String,
    fieldsFn: ArrayList<LLVMValueRef>): LLVMValueRef {
    let fieldNum = fieldsFn.size
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
    CJC_ASSERT(fieldNum > 0)
    let fieldFnPtrType = unsafe { LLVMTypeOf(fieldsFn[0]) }
    let arrayType = unsafe { LLVMArrayType(fieldFnPtrType, UInt32(fieldNum)) }
    let globalArray = GetOrInsertCodeGenGlobal(cgMod, funcPrefixName + ".fieldTiFns", arrayType)
    unsafe {
        LLVMSetLinkage(globalArray, LLVMLinkageValue(LLVMLinkage.Private))
        LLVMSetInitializer(globalArray, ConstArray(fieldFnPtrType, fieldsFn))
    }
    addAttribute(globalArray, CJTT_FIELDS_FNS_ATTR)
    return unsafe { LLVMConstBitCast(globalArray, i8PtrType) }
}

public func GenFieldsFnsOfTypeTemplate(cgMod: CGModule, funcPrefixName: String, fieldTypes: ArrayList<Type>,
    genericParamIndicesMap: ArrayList<GenericType>): LLVMValueRef {
    let fieldNum = fieldTypes.size
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
    if (fieldNum == 0) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let typeInfoType = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
    let argTypes = ArrayList<LLVMTypeRef>()
    argTypes.add(unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) })
    argTypes.add(unsafe { LLVMPointerType(LLVMPointerType(typeInfoType, 0u32), 0u32) })
    let fieldFn = BuildTypeInfoFunctionType(i8PtrType, argTypes)
    let initializers = ArrayList<LLVMValueRef>()
    var idx: Int64 = 0
    for (fieldType in fieldTypes) {
        let fieldName = idx.toString()
        let funcName = funcPrefixName + ".fieldTiFn." + fieldName
        initializers.add(GenerateTypeTemplateTypeInfoFn(cgMod, fieldFn, funcName, fieldType, genericParamIndicesMap))
        idx++
    }
    return GenFieldsFnsOfTypeTemplate(cgMod, funcPrefixName, initializers)
}

private func GenerateSuperFnOfTypeTemplate(cgMod: CGModule, customTy: CustomType, typeTemplateName: String,
    i8PtrType: LLVMTypeRef): LLVMValueRef {
    let sourceTy = SourceCustomType(customTy)
    if (let Some(classTy) <- (sourceTy as ClassType)) {
        if (!classTy.GetClassDef().IsClass()) {
            return unsafe { LLVMConstNull(i8PtrType) }
        }
        if (let Some(superTy) <- TypeTemplateSuperClassTy(cgMod, classTy)) {
            let superFn = GenerateTypeTemplateTypeInfoFn(cgMod, GetTypeTemplateCallbackFunctionType(cgMod),
                typeTemplateName + ".superTiFn", superTy, TypeTemplateGenericParams(sourceTy))
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
    unsafe { LLVMSetUnnamedAddress(fn, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr)) }
    try (irBuilder = IRBuilder2(cgMod)) {
        let entry = irBuilder.CreateEntryBasicBlock(fn, "entry")
        irBuilder.SetInsertPoint(entry)
        let typeInfo = CreateTypeInfoForCallbackBody(cgMod, irBuilder, memberTy, genericParams,
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

public func CreateTypeInfoForTemplateCallback(cgMod: CGModule, irBuilder: IRBuilder2, chirTy: Type,
    genericParams: ArrayList<GenericType>, runtimeTypeInfoArray: LLVMValueRef,
    plainRuntimeTypeInfoArrayGEP!: Bool = false): LLVMValueRef {
    let baseTy = chirTy.StripAllRefs()
    if (let Some(genericTy) <- (baseTy as GenericType)) {
        if (let Some(genericIdx) <- FindGenericParamIndex(genericTy, genericParams)) {
            return GetRuntimeTypeInfoFromArray(irBuilder, runtimeTypeInfoArray, genericIdx, genericTy,
                plainRuntimeTypeInfoArrayGEP: plainRuntimeTypeInfoArrayGEP)
        }
        throw IllegalStateException("missing runtime TypeInfo mapping for template generic type: " + baseTy.ToString())
    }
    if (ContainsGenericType(baseTy)) {
        throw IllegalStateException("unexpected generic-related callback type: " + baseTy.ToString())
    }
    return GetAutoEnvBaseClosureTypeInfo(cgMod, baseTy) ??
        CGType.GetOrCreate(cgMod, baseTy).GetOrCreateTypeInfo()
}

private func GetAutoEnvBaseClosureTypeInfo(cgMod: CGModule, chirTy: Type): Option<LLVMValueRef> {
    let customTy = (chirTy.StripAllRefs() as CustomType) ?? return None
    if (!IsAutoEnvBaseType(customTy)) {
        return None
    }
    return Some(CGType.GetOrCreate(cgMod, AutoEnvGenericBaseType(customTy)).GetOrCreateTypeInfo())
}

private func AutoEnvGenericBaseType(customTy: CustomType): CustomType {
    if (IsAutoEnvInstBaseType(customTy)) {
        if (let Some(classTy) <- (customTy as ClassType)) {
            if (let Some(superTy) <- classTy.GetSuperClassTy()) {
                if (let Some(superCustomTy) <- (superTy as CustomType)) {
                    return superCustomTy
                }
            }
        }
    }
    return customTy
}

private func ClosureRuntimeTypeName(cgMod: CGModule, customTy: CustomType): String {
    let typeArgs = customTy.GetGenericArgs()
    if (typeArgs.isEmpty()) {
        return GetTypeQualifiedName(customTy, forNameFieldOfTi: true)
    }
    var params = ""
    var idx: Int64 = 0
    while (idx + 1 < typeArgs.size) {
        if (idx > 0) {
            params += ","
        }
        params += RuntimeTypeNameForClosure(cgMod, typeArgs[idx])
        idx++
    }
    return "Closure<(" + params + ")->" + RuntimeTypeNameForClosure(cgMod, typeArgs[typeArgs.size - 1]) + ">"
}

private func RuntimeTypeNameForClosure(cgMod: CGModule, chirTy: Type): String {
    let stripped = chirTy.StripAllRefs()
    if (stripped.IsVoid()) {
        return UNIT_TYPE_STR
    }
    if (let Some(customTy) <- (stripped as CustomType)) {
        if (IsAutoEnvBaseType(customTy)) {
            return ClosureRuntimeTypeName(cgMod, AutoEnvGenericBaseType(customTy))
        }
    }
    return GetTypeQualifiedName(stripped, forNameFieldOfTi: true)
}

private func TypeInfoGlobalName(cgMod: CGModule, chirTy: Type): String {
    if (let Some(customTy) <- (chirTy.StripAllRefs() as CustomType)) {
        if (IsAutoEnvBaseType(customTy)) {
            return ClosureRuntimeTypeName(cgMod, AutoEnvGenericBaseType(customTy)) + ".ti"
        }
    }
    return CGType.GetNameOfTypeInfoGV(chirTy)
}

private func TypeInfoRuntimeName(cgMod: CGModule, chirTy: Type): String {
    if (let Some(customTy) <- (chirTy.StripAllRefs() as CustomType)) {
        if (IsAutoEnvBaseType(customTy)) {
            return ClosureRuntimeTypeName(cgMod, AutoEnvGenericBaseType(customTy))
        }
    }
    return GetTypeQualifiedName(chirTy, forNameFieldOfTi: true)
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

private func GetRuntimeTypeInfoFromArray(irBuilder: IRBuilder2, runtimeTypeInfoArray: LLVMValueRef,
    idx: Int64, genericTy: GenericType, plainRuntimeTypeInfoArrayGEP!: Bool = false): LLVMValueRef {
    if (plainRuntimeTypeInfoArrayGEP) {
        return irBuilder.GetTypeInfoFromTiArrayPlain(runtimeTypeInfoArray, idx,
            name: "ti." + genericTy.GetSrcCodeIdentifier())
    }
    return irBuilder.GetTypeInfoFromTiArray(runtimeTypeInfoArray, idx,
        name: "ti." + genericTy.GetSrcCodeIdentifier())
}

public func CreateTypeInfoForCallbackBody(cgMod: CGModule, irBuilder: IRBuilder2,
    chirTy: Type, genericParams: ArrayList<GenericType>, runtimeTypeInfoArray: LLVMValueRef,
    plainRuntimeTypeInfoArrayGEP!: Bool = false): LLVMValueRef {
    let baseTy = chirTy.StripAllRefs()
    if (!baseTy.IsGenericRelated()) {
        return CreateTypeInfoForTemplateCallback(cgMod, irBuilder, chirTy, genericParams, runtimeTypeInfoArray,
            plainRuntimeTypeInfoArrayGEP: plainRuntimeTypeInfoArrayGEP)
    }
    if ((baseTy as GenericType).isSome()) {
        return CreateTypeInfoForTemplateCallback(cgMod, irBuilder, chirTy, genericParams, runtimeTypeInfoArray,
            plainRuntimeTypeInfoArrayGEP: plainRuntimeTypeInfoArrayGEP)
    }
    let typeInfoProviders = HashMap<Int64, (IRBuilder2) -> LLVMValueRef>()
    var idx: Int64 = 0
    while (idx < genericParams.size) {
        let genericParam = genericParams[idx]
        let genericParamIdx = idx
        typeInfoProviders[genericParam.objectId] = { builder: IRBuilder2 =>
            GetRuntimeTypeInfoFromArray(builder, runtimeTypeInfoArray, genericParamIdx, genericParam,
                plainRuntimeTypeInfoArrayGEP: plainRuntimeTypeInfoArrayGEP)
        }
        idx++
    }
    return irBuilder.CreateTypeInfo(baseTy, typeInfoProviders)
}

private func GetTypeTemplateFieldTypes(cgMod: CGModule, customTy: CustomType): ArrayList<Type> {
    if (let Some(enumTy) <- (customTy as EnumType)) {
        return GetEnumTypeTemplateFieldTypes(cgMod, enumTy)
    }
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

private func GetEnumTypeTemplateFieldTypes(cgMod: CGModule, enumTy: EnumType): ArrayList<Type> {
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
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            result.add(builder.context.GetUnitTy())
            if (let Some(objectTy) <- builder.context.GetObjectTy()) {
                result.add(builder.context.GetRefTy(objectTy))
            } else {
                CJC_ASSERT(false)
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
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE) {
            return result
        }
        CJC_ASSERT(false)
    }
    return result
}

private func TypeTemplateSuperClassTy(cgMod: CGModule, classTy: ClassType): Option<ClassType> {
    if (let Some(superTy) <- classTy.GetSuperClassTy(builder: Some(cgMod.GetCGContext().GetCHIRBuilder()))) {
        return Some(superTy)
    }
    return None
}

private func GenerateFinalizerOfTypeTemplate(cgMod: CGModule, customTy: CustomType,
    i8PtrType: LLVMTypeRef): LLVMValueRef {
    let sourceTy = SourceCustomType(customTy)
    if (let Some(classTy) <- (sourceTy as ClassType)) {
        if (let Some(finalizer) <- classTy.GetClassDef().GetFinalizer()) {
            return unsafe { LLVMConstBitCast(cgMod.GetOrInsertCGFunction(finalizer).GetRawFunction(), i8PtrType) }
        }
    }
    return unsafe { LLVMConstNull(i8PtrType) }
}

private func SourceCustomType(customTy: CustomType): CustomType {
    let def = customTy.GetCustomTypeDef()
    if (let Some(genericDecl) <- def.GetGenericDecl()) {
        return SourceCustomTypeForDef(genericDecl, customTy)
    }
    if (def.IsGenericDef()) {
        return SourceCustomTypeForDef(def, customTy)
    }
    if (let Some(defTy) <- def.GetType()) {
        return StaticCast<CustomType>(defTy)
    }
    return customTy
}

private func SourceCustomTypeForDef(def: CustomTypeDef, fallback: CustomType): CustomType {
    let genericArgs = ArrayList<Type>()
    for (param in def.GetGenericTypeParams()) {
        genericArgs.add(param)
    }
    if (let Some(classDef) <- (def as ClassDef)) {
        return ClassType(classDef, genericArgs)
    }
    if (let Some(structDef) <- (def as StructDef)) {
        return StructType(structDef, genericArgs)
    }
    if (let Some(enumDef) <- (def as EnumDef)) {
        return EnumType(enumDef, genericArgs)
    }
    if (let Some(defTy) <- def.GetType()) {
        return StaticCast<CustomType>(defTy)
    }
    return fallback
}

private func TypeTemplateGenericParams(customTy: CustomType): ArrayList<GenericType> {
    let result = ArrayList<GenericType>()
    for (param in customTy.GetCustomTypeDef().GetGenericTypeParams()) {
        AddGenericParamIfAbsent(result, param)
    }
    for (arg in customTy.GetGenericArgs()) {
        if (let Some(genericArg) <- (arg as GenericType)) {
            AddGenericParamIfAbsent(result, genericArg)
        }
    }
    return result
}

private func AddGenericParamIfAbsent(params: ArrayList<GenericType>, candidate: GenericType): Unit {
    for (param in params) {
        if (candidate.IsEqual(param) || candidate.GetIdentifier() == param.GetIdentifier() ||
            candidate.GetSrcCodeIdentifier() == param.GetSrcCodeIdentifier()) {
            return
        }
    }
    params.add(candidate)
}

private func LinkageOfCustomTypeDef(def: CustomTypeDef): Linkage {
    return def.Get<LinkTypeInfo, Linkage>()
}

private func TypeTemplateLinkage(def: CustomTypeDef): LLVMLinkage {
    let linkageType = CHIRLinkage2LLVMLinkage(LinkageOfCustomTypeDef(def))
    if (LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.Internal)) {
        return LLVMLinkage.Private
    }
    return linkageType
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

private func GenFieldsNumOfTypeInfo(cgMod: CGModule, chirTy: Type): UInt64 {
    if (let Some(vArrayTy) <- (chirTy as VArrayType)) {
        return vArrayTy.GetSize()
    }
    return UInt64(GetInstanceFieldTypes(cgMod, chirTy).size)
}

private func GenTypeArgsNumOfTypeInfo(_: CGModule, chirTy: Type): UInt64 {
    if (IsAutoEnvBaseType(chirTy)) {
        CJC_ASSERT(!IsAutoEnvInstBaseType(chirTy))
        return 1u64
    }
    if (let Some(funcTy) <- (chirTy as FuncType)) {
        return UInt64(funcTy.GetParamTypes().size + 1)
    }
    if ((chirTy as CPointerType).isSome()) {
        return 1u64
    }
    if (let Some(tupleTy) <- (chirTy as TupleType)) {
        return UInt64(tupleTy.GetTypeArgs().size)
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        return UInt64(customTy.GetGenericArgs().size)
    }
    return 0u64
}

private func GenerateTypeArgsOfTypeInfo(cgMod: CGModule, chirTy: Type, typeInfo: LLVMValueRef,
    typeInfoName: String, i8PtrType: LLVMTypeRef): LLVMValueRef {
    if (let Some(boxTy) <- (chirTy as BoxType)) {
        let boxBaseCGType = CGType.GetOrCreate(cgMod, boxTy.GetBaseType().StripAllRefs())
        let boxBaseTI = boxBaseCGType.GetOrCreateTypeInfo()
        if (boxBaseCGType.IsStaticGI()) {
            cgMod.GetCGContext().AddDependentPartialOrderOfTypes(boxBaseTI, typeInfo)
        }
        return unsafe { LLVMConstBitCast(boxBaseTI, i8PtrType) }
    }
    let typeArgs = ArrayList<Type>()
    if (IsAutoEnvBaseType(chirTy)) {
        if (let Some(customTy) <- (chirTy as CustomType)) {
            let genericArgs = customTy.GetGenericArgs()
            if (!genericArgs.isEmpty()) {
                let paramTypes = ArrayList<Type>()
                var idx: Int64 = 0
                while (idx + 1 < genericArgs.size) {
                    paramTypes.add(genericArgs[idx])
                    idx++
                }
                typeArgs.add(FuncType(paramTypes, genericArgs[genericArgs.size - 1]))
            }
        }
    } else if (let Some(funcTy) <- (chirTy as FuncType)) {
        typeArgs.add(funcTy.GetReturnType())
        for (paramTy in funcTy.GetParamTypes()) {
            typeArgs.add(paramTy)
        }
    } else if (let Some(cPointerTy) <- (chirTy as CPointerType)) {
        typeArgs.add(cPointerTy.GetElementType())
    } else if (let Some(tupleTy) <- (chirTy as TupleType)) {
        for (typeArg in tupleTy.GetTypeArgs()) {
            typeArgs.add(typeArg)
        }
    } else if (let Some(customTy) <- (chirTy as CustomType)) {
        for (typeArg in customTy.GetGenericArgs()) {
            typeArgs.add(typeArg)
        }
    }
    if (typeArgs.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let arrayType = unsafe { LLVMArrayType(typeInfoPtrType, UInt32(typeArgs.size)) }
    let typeArgsGlobal = GetOrInsertCodeGenGlobal(cgMod, typeInfoName + ".typeArgs", arrayType)
    if (unsafe { LLVMIsDeclaration(typeArgsGlobal) } != 0) {
        let values = ArrayList<LLVMValueRef>()
        for (typeArg in typeArgs) {
            let argCGType = CGType.GetOrCreate(cgMod, typeArg.StripAllRefs())
            let argTI = argCGType.GetOrCreateTypeInfo()
            if (argCGType.IsStaticGI()) {
                cgMod.GetCGContext().AddDependentPartialOrderOfTypes(argTI, typeInfo)
            }
            values.add(unsafe { LLVMConstBitCast(argTI, typeInfoPtrType) })
        }
        unsafe {
            LLVMSetInitializer(typeArgsGlobal, ConstArray(typeInfoPtrType, values))
            LLVMSetLinkage(typeArgsGlobal, LLVMLinkageValue(LLVMLinkage.Private))
            addAttribute(typeArgsGlobal, CJTI_TYPE_ARGS_ATTR)
            LLVMSetGlobalConstant(typeArgsGlobal, 1)
            LLVMSetUnnamedAddress(typeArgsGlobal, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr))
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
            fieldInfos.add(GetAutoEnvBaseClosureTypeInfo(cgMod, fieldTy) ??
                CGType.GetOrCreate(cgMod, fieldTy.StripAllRefs()).GetOrCreateTypeInfo())
        }
        unsafe {
            LLVMSetInitializer(fieldsGlobal, ConstArray(typeInfoPtrType, fieldInfos))
            LLVMSetLinkage(fieldsGlobal, LLVMLinkageValue(LLVMLinkage.Private))
            addAttribute(fieldsGlobal, CJTI_FIELDS_ATTR)
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
            addAttribute(offsetsGlobal, CJTI_OFFSETS_ATTR)
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
    if (IsAutoEnvBaseType(chirTy)) {
        return UG_FUNC_KIND
    }
    if (chirTy.IsFunc()) { return UG_CFUNC }
    if (chirTy.IsVArray()) { return UG_VARRAY }
    if (chirTy.IsCPointer()) { return UG_CPOINTER }
    if (chirTy.IsCString()) { return UG_CSTRING }
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

private func IsCoreObjectClass(classTy: ClassType): Bool {
    return IsCoreObjectClassDef(classTy.GetClassDef())
}

private func ClassInheritanceDepth(classTy: ClassType): Int64 {
    if (classTy.GetClassDef().IsInterface()) {
        return 0
    }
    let classDef = classTy.GetClassDef()
    if (IsCoreObjectClass(classTy)) {
        return 1
    }
    var count: Int64 = 2
    var current = classDef.GetSuperClassDef()
    while (let Some(superDef) <- current) {
        if (!IsCoreObjectClassDef(superDef)) {
            count++
        }
        current = superDef.GetSuperClassDef()
    }
    return count
}

private func IsCoreObjectClassDef(def: ClassDef): Bool {
    return def.GetPackageName() == "std.core" && def.GetSrcCodeIdentifier() == "Object"
}

private func GenerateExtensionDefPtrOfTypeInfo(cgMod: CGModule, chirTy: Type,
    extensionDefPtrPtrType: LLVMTypeRef): LLVMValueRef {
    if (let Some(startIdx) <- cgMod.GetExtensionDefStart(chirTy)) {
        let defs = if (IsExternalDefinedType(chirTy)) {
            cgMod.GetExternalExtensionDefs()
        } else {
            cgMod.GetNonExternalExtensionDefs()
        }
        if (!defs.isEmpty()) {
            if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
                let tableName = if (IsExternalDefinedType(chirTy)) {
                    "ExternalExtensionDefs"
                } else {
                    "NonExternalExtensionDefs"
                }
                try (nameCString = unsafe { LibC.mallocCString(tableName) }.asResource()) {
                    let table = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
                    if (!table.isNull()) {
                        let arrayType = unsafe { LLVMGlobalGetValueType(table) }
                        let i32Type = unsafe { LLVMInt32TypeInContext(cgMod.GetLLVMContext().raw) }
                        let zero = unsafe { LLVMConstInt(i32Type, 0u64, 0) }
                        let index = unsafe { LLVMConstInt(i32Type, UInt64(startIdx), 0) }
                        return TypeInfoConstInBoundsGEP2(arrayType, table, zero, index)
                    }
                }
            }
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

private func GetLayoutMetadataName(cgMod: CGModule, chirTy: Type): String {
    let cgType = CGType.GetOrCreate(cgMod, chirTy)
    let layoutType = cgType.GetLayoutType()
    if (!layoutType.isNull() && unsafe { LLVMGetTypeKind(layoutType) } == LLVM_STRUCT_TYPE_KIND) {
        let layoutName = LLVMCStringToString(unsafe { LLVMGetStructName(layoutType) }) ?? ""
        if (!layoutName.isEmpty()) {
            return layoutName
        }
    }
    if (chirTy.IsClass()) {
        return GetClassObjLayoutName(chirTy.ToString())
    }
    if (chirTy.IsString()) {
        return "record.std.core:String"
    }
    return STRUCT_TYPE_PREFIX + chirTy.ToString()
}

private func GenerateSuperOfTypeInfo(cgMod: CGModule, chirTy: Type, typeInfo: LLVMValueRef,
    typeInfoPtrType: LLVMTypeRef): LLVMValueRef {
    if (let Some(cPointerTy) <- (chirTy as CPointerType)) {
        let elementTI = CGType.GetOrCreate(cgMod, cPointerTy.GetElementType().StripAllRefs()).GetOrCreateTypeInfo()
        return unsafe { LLVMConstBitCast(elementTI, typeInfoPtrType) }
    }
    if (let Some(vArrayTy) <- (chirTy as VArrayType)) {
        let elementCGType = CGType.GetOrCreate(cgMod, vArrayTy.GetElementType().StripAllRefs())
        let elementTI = elementCGType.GetOrCreateTypeInfo()
        if (elementCGType.IsStaticGI()) {
            cgMod.GetCGContext().AddDependentPartialOrderOfTypes(elementTI, typeInfo)
        }
        return unsafe { LLVMConstBitCast(elementTI, typeInfoPtrType) }
    }
    if (let Some(classTy) <- (chirTy as ClassType)) {
        if (classTy.GetClassDef().IsInterface()) {
            return unsafe { LLVMConstNull(typeInfoPtrType) }
        }
        if (IsAutoEnvBaseType(classTy)) {
            return unsafe { LLVMConstNull(typeInfoPtrType) }
        }
        if (let Some(superTy) <- classTy.GetSuperClassTy(builder: Some(cgMod.GetCGContext().GetCHIRBuilder()))) {
            let superTi = GetAutoEnvBaseClosureTypeInfo(cgMod, superTy) ??
                CGType.GetOrCreate(cgMod, superTy.StripAllRefs()).GetOrCreateTypeInfo()
            // Coerce to the %TypeInfo* slot type: a DYNAMIC_GI super (e.g. generic Iterator<...>)
            // resolves to a %GenericCustomTypeInfo* global; the C++ reference output places it in
            // TYPEINFO_SUPER via `%TypeInfo* bitcast (%GenericCustomTypeInfo* ... to %TypeInfo*)`
            // (Module::getOrInsertGlobal coercion). LLVMConstBitCast is an identity no-op when the
            // super is already %TypeInfo* (non-generic super), matching C++ byte-for-byte.
            return unsafe { LLVMConstBitCast(superTi, typeInfoPtrType) }
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
        chirTy.IsBox() || chirTy.IsCFunc() || chirTy.IsFunc()) {
        return true
    }
    if (let Some(customTy) <- (chirTy as CustomType)) {
        return !customTy.GetGenericArgs().isEmpty()
    }
    return false
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
