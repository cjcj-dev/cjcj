package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.EnumDef
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.ExtendDef
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.StructDef
import cangjie_compiler::chir.StructType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.VirtualMethodInfo
import cangjie_compiler::chir.VTableInType
import cangjie_compiler::mangle.GetTypeQualifiedName
import cangjie_compiler::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG, StaticCast}

private let EXTENSION_DEFS_NAME: String = "NonExternalExtensionDefs"

public func GenerateInterfaceExtensionDefs(cgMod: CGModule): Unit {
    for (def in cgMod.GetCGContext().GetSubCHIRPackage().chirCustomDefs) {
        if (!ShouldCollectExtensionDef(cgMod, def)) {
            continue
        }
        GenerateExtensionDefsForCustomDef(cgMod, def)
    }
    EmitNonExternalExtensionDefsTable(cgMod)
}

public func RedefineTypeInfosForCustomDefs(cgMod: CGModule): Unit {
    for (def in cgMod.GetCGContext().GetSubCHIRPackage().chirCustomDefs) {
        if (!IsCurrentPackageDef(cgMod, def)) {
            continue
        }
        if (def.IsExtend()) {
            continue
        }
        if (def.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            continue
        }
        if (let Some(classDef) <- (def as ClassDef)) {
            if (IsCoreObjectDef(classDef) || IsClosureConversionEnvClass(classDef)) {
                continue
            }
        }
        if (let Some(ty) <- def.GetType()) {
            if (ty.IsGenericRelated()) {
                continue
            }
            RedefineTypeInfoGlobal(cgMod, ty)
        }
    }
}

private func IsCurrentPackageDef(cgMod: CGModule, def: CustomTypeDef): Bool {
    return def.GetPackageName() == cgMod.GetCGContext().GetCurrentPkgName()
}

private func ShouldCollectExtensionDef(cgMod: CGModule, def: CustomTypeDef): Bool {
    if (def.TestAttr(Attribute.IMPORTED) || def.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
        return false
    }
    if (!IsCurrentPackageDef(cgMod, def)) {
        return false
    }
    if (let Some(classDef) <- (def as ClassDef)) {
        return !IsCoreObjectDef(classDef) && !IsClosureConversionEnvClass(classDef)
    }
    if (let Some(extendDef) <- (def as ExtendDef)) {
        return ShouldCollectExtendDef(extendDef)
    }
    return true
}

private func ShouldCollectExtendDef(extendDef: ExtendDef): Bool {
    if (let Some(extendedType) <- extendDef.GetExtendedType()) {
        if (!extendedType.IsNominal()) {
            return true
        }
        if (let Some(customTy) <- (extendedType as CustomType)) {
            return customTy.GetCustomTypeDef().TestAttr(Attribute.IMPORTED)
        }
    }
    return false
}

private func GenerateExtensionDefsForCustomDef(cgMod: CGModule, def: CustomTypeDef): Unit {
    if (let None <- def.GetType()) {
        return
    }
    let startIdx = cgMod.GetNonExternalExtensionDefsNum()
    var emitted = false
    let emittedInterfaces = ArrayList<MTableInterfaceInfo>()
    if (let Some(classDef) <- (def as ClassDef)) {
        if (!classDef.IsInterface()) {
            if (GenerateObjectExtensionDefForType(cgMod, classDef)) {
                emitted = true
            }
            let superTypes = CollectSuperClassTypes(classDef)
            var superIdx = superTypes.size - 1
            while (superIdx >= 0) {
                let superTy = superTypes[superIdx]
                if (!IsCoreObjectType(superTy)) {
                    let directSuper = superIdx == 0
                    if (GenerateExtensionDefForType(cgMod, def, superTy, directSuper)) {
                        emitted = true
                    }
                }
                superIdx--
            }
            if (GenerateExtensionDefForType(cgMod, def, RequireClassType(classDef), false)) {
                emitted = true
            }
        } else if (!def.GetMethods().isEmpty() && !RequireClassType(classDef).IsGenericRelated()) {
            let selfInterfaceTy = RequireClassType(classDef)
            if (GenerateExtensionDefForType(cgMod, def, selfInterfaceTy, false)) {
                emitted = true
                emittedInterfaces.add(MTableInterfaceInfo(selfInterfaceTy, None))
            }
        }
    }
    let interfaces = CollectImplementedInterfaces(def)
    for (interfaceTy in interfaces) {
        if (GenerateExtensionDefForType(cgMod, def, interfaceTy, IsDirectInterface(def, interfaceTy))) {
            emitted = true
            emittedInterfaces.add(MTableInterfaceInfo(interfaceTy, None))
        }
    }
    if (emitted) {
        let targetTy = SourceGenericTargetType(RequireExtensionTargetType(def))
        cgMod.RegisterExtensionDefStart(targetTy, startIdx)
        cgMod.RegisterExtensionDefInterfaces(targetTy, emittedInterfaces)
        if (let Some(customTy) <- (targetTy as CustomType)) {
            RefreshSourceGenericTypeTemplateInitializer(cgMod, customTy)
        }
    }
}

private func CollectSuperClassTypes(classDef: ClassDef): ArrayList<ClassType> {
    let out = ArrayList<ClassType>()
    var current = classDef.GetSuperClassTy()
    while (let Some(superTy) <- current) {
        out.add(superTy)
        current = superTy.GetSuperClassTy()
    }
    return out
}

private func GenerateObjectExtensionDefForType(cgMod: CGModule, targetDef: ClassDef): Bool {
    let targetType = SourceGenericTargetType(RequireClassType(targetDef))
    let coreObjectTy = RequireClassType(CoreObjectClassDef(targetDef))
    let extensionDefType = CGType.GetOrCreateExtensionDefType(cgMod.GetLLVMContext())
    let name = ExtensionDefName(targetType, coreObjectTy)
    let extensionDef = GetOrInsertCodeGenGlobal(cgMod, name, extensionDefType)
    if (unsafe { LLVMIsDeclaration(extensionDef) } == 0) {
        return false
    }
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i16Type = unsafe { LLVMInt16TypeInContext(context) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let values = ArrayList<LLVMValueRef>()
    values.add(unsafe { LLVMConstInt(i32Type, UInt64(TypeParamCount(cgMod, targetType)), 0) })
    values.add(unsafe { LLVMConstInt(i8Type, 1u64, 0) })
    values.add(unsafe { LLVMConstInt(i8Type, 0b10000001u64, 0) })
    values.add(unsafe { LLVMConstInt(i16Type, 0u64, 0) })
    values.add(TargetTypeAsI8Ptr(cgMod, targetType, i8PtrType))
    values.add(CoreObjectTypeInfoAsI8Ptr(cgMod, i8PtrType))
    values.add(unsafe { LLVMConstNull(i8PtrType) })
    values.add(unsafe { LLVMConstNull(i8PtrType) })
    unsafe {
        LLVMSetInitializer(extensionDef, ConstNamedStruct(extensionDefType, values))
        LLVMSetLinkage(extensionDef, LLVMLinkageValue(LLVMLinkage.Private))
        LLVMSetGlobalConstant(extensionDef, 1)
    }
    cgMod.AddNonExternalExtensionDef(extensionDef)
    return true
}

private func GenerateExtensionDefForType(cgMod: CGModule, targetDef: CustomTypeDef, inheritedType: ClassType,
    direct: Bool): Bool {
    let targetType = SourceGenericTargetType(RequireExtensionTargetType(targetDef))
    let effectiveInheritedType = if (inheritedType.GetClassDef().nodeId == targetDef.nodeId) {
        (targetType as ClassType) ?? inheritedType
    } else {
        inheritedType
    }
    let vTable = targetDef.GetDefVTable().GetExpectedTypeVTable(effectiveInheritedType)
    let funcTableSize = if (vTable.IsEmpty()) { 0 } else { vTable.GetMethodNum() }
    if (funcTableSize == 0 && effectiveInheritedType.GetClassDef().IsInterface() &&
        effectiveInheritedType.GetClassDef().nodeId == targetDef.nodeId) {
        return false
    }
    let extensionDefType = CGType.GetOrCreateExtensionDefType(cgMod.GetLLVMContext())
    let name = ExtensionDefName(targetType, effectiveInheritedType)
    let extensionDef = GetOrInsertCodeGenGlobal(cgMod, name, extensionDefType)
    if (unsafe { LLVMIsDeclaration(extensionDef) } == 0) {
        return false
    }
    let content = BuildExtensionDefContent(cgMod, targetType, effectiveInheritedType, vTable, funcTableSize, direct)
    unsafe {
        LLVMSetInitializer(extensionDef, ConstNamedStruct(extensionDefType, content))
        LLVMSetLinkage(extensionDef, LLVMLinkageValue(LLVMLinkage.Private))
        LLVMSetGlobalConstant(extensionDef, 1)
    }
    cgMod.AddNonExternalExtensionDef(extensionDef)
    return true
}

private func BuildExtensionDefContent(cgMod: CGModule, targetType: Type, inheritedType: ClassType,
    vTable: VTableInType, funcTableSize: Int64, direct: Bool): ArrayList<LLVMValueRef> {
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i16Type = unsafe { LLVMInt16TypeInContext(context) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let values = ArrayList<LLVMValueRef>()
    values.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    let (interfaceFnOrTi, isInterfaceTi) = GenerateInterfaceFn(cgMod, targetType, inheritedType, i8PtrType)
    values.add(unsafe { LLVMConstInt(i8Type, if (isInterfaceTi) { 1u64 } else { 0u64 }, 0) })
    values.add(unsafe { LLVMConstInt(i8Type, ExtensionDefFlag(targetType, inheritedType, direct), 0) })
    values.add(unsafe { LLVMConstInt(i16Type, UInt64(funcTableSize), 0) })
    values[0] = unsafe { LLVMConstInt(i32Type, UInt64(TypeParamCount(cgMod, targetType)), 0) }
    values.add(TargetTypeAsI8Ptr(cgMod, targetType, i8PtrType))
    values.add(interfaceFnOrTi)
    values.add(unsafe { LLVMConstNull(i8PtrType) })
    values.add(GenerateFuncTableForType(cgMod, ExtensionDefName(targetType, inheritedType), targetType,
        inheritedType, vTable, i8PtrType))
    return values
}

private func TypeParamCount(cgMod: CGModule, targetType: Type): Int64 {
    if (CGType.GetOrCreate(cgMod, targetType.StripAllRefs()).IsDynamicGI()) {
        return targetType.GetTypeArgs().size
    }
    return 0
}

private func TargetTypeAsI8Ptr(cgMod: CGModule, targetType: Type, i8PtrType: LLVMTypeRef): LLVMValueRef {
    let baseTy = targetType.StripAllRefs()
    if (CGType.GetOrCreate(cgMod, baseTy).IsDynamicGI()) {
        let template = if (let Some(customTy) <- (baseTy as CustomType)) {
            EnsureSourceGenericTypeTemplate(cgMod, SourceCustomType(customTy))
        } else {
            CGType.GetOrCreate(cgMod, baseTy).GetOrCreateTypeTemplate()
        }
        return unsafe { LLVMConstBitCast(template, i8PtrType) }
    }
    return TypeInfoAsI8Ptr(cgMod, baseTy, i8PtrType)
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

private func SourceGenericTargetType(targetType: Type): Type {
    if (let Some(customTy) <- (targetType.StripAllRefs() as CustomType)) {
        return SourceCustomType(customTy)
    }
    return targetType
}

private func GenerateInterfaceFn(cgMod: CGModule, targetType: Type, inheritedType: ClassType,
    i8PtrType: LLVMTypeRef): (LLVMValueRef, Bool) {
    let runtimeGenericParams = RuntimeGenericParams(targetType)
    if (!CGType.GetOrCreate(cgMod, inheritedType.StripAllRefs()).IsDynamicGI() ||
        !CanResolveRuntimeGenericParams(inheritedType, runtimeGenericParams)) {
        return (TypeInfoAsI8Ptr(cgMod, inheritedType, i8PtrType), true)
    }
    let context = cgMod.GetLLVMContext().raw
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let params = ArrayList<LLVMTypeRef>()
    params.add(unsafe { LLVMInt32TypeInContext(context) })
    params.add(unsafe { LLVMPointerType(typeInfoPtrType, 0u32) })
    let fnType = BuildLLVMFunctionType(i8PtrType, params)
    let fnName = ExtensionDefName(targetType, inheritedType) + "_iFn"
    let fn = cgMod.GetOrInsertFunction(fnName, fnType)
    if (unsafe { LLVMIsDeclaration(fn) } != 0) {
        unsafe { LLVMSetLinkage(fn, LLVMLinkageValue(LLVMLinkage.Private)) }
        AddFnAttr(fn, "native-interface-fn")
        unsafe { LLVMSetUnnamedAddress(fn, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr)) }
        let entry = IRBuilder2(cgMod)
        let block = entry.CreateEntryBasicBlock(fn, "entry")
        entry.SetInsertPoint(block)
        let runtimeTypeInfoArray = unsafe { LLVMGetParam(fn, 1u32) }
        let typeInfo = CreateTypeInfoForCallbackBody(cgMod, entry, block, inheritedType.StripAllRefs(),
            runtimeGenericParams, runtimeTypeInfoArray, plainRuntimeTypeInfoArrayGEP: true)
        entry.CreateRet(entry.CreateBitCast(typeInfo, i8PtrType, name: "interface.ti"))
        entry.close()
    }
    return (unsafe { LLVMConstBitCast(fn, i8PtrType) }, false)
}

private func CanResolveRuntimeGenericParams(chirTy: Type, genericParams: ArrayList<GenericType>): Bool {
    let baseTy = chirTy.StripAllRefs()
    if (let Some(genericTy) <- (baseTy as GenericType)) {
        return FindRuntimeGenericParam(genericTy, genericParams).isSome()
    }
    for (typeArg in baseTy.GetTypeArgs()) {
        if (!CanResolveRuntimeGenericParams(typeArg, genericParams)) {
            return false
        }
    }
    return true
}

private func FindRuntimeGenericParam(genericTy: GenericType,
    genericParams: ArrayList<GenericType>): Option<GenericType> {
    for (param in genericParams) {
        if (genericTy.IsEqual(param)) {
            return Some(param)
        }
    }
    return None
}

private func ExtensionDefFlag(targetType: Type, inheritedType: ClassType, direct: Bool): UInt64 {
    var flag: UInt64 = 0b00000001u64
    if (direct) {
        flag |= 0b10000000u64
    }
    if (SameRootPackage(TargetPackageName(targetType), inheritedType.GetClassDef().GetPackageName())) {
        flag |= 0b00000110u64
    }
    return flag
}

private func GenerateOuterTi(cgMod: CGModule, funcInfo: VirtualMethodInfo, i8PtrType: LLVMTypeRef): LLVMValueRef {
    let method = funcInfo.GetVirtualMethod().getOrThrow()
    if (method.IsPureAbstract()) {
        return SentinelI8Ptr(cgMod, i8PtrType)
    }
    let parentType = funcInfo.GetInstParentType().StripAllRefs()
    if (parentType.GetTypeArgs().isEmpty()) {
        return SentinelI8Ptr(cgMod, i8PtrType)
    }
    return TypeInfoAsI8Ptr(cgMod, parentType, i8PtrType)
}

private func GenerateOuterTiFn(cgMod: CGModule, extendDefName: String, targetType: Type,
    funcInfo: VirtualMethodInfo, i8PtrType: LLVMTypeRef): LLVMValueRef {
    let method = funcInfo.GetVirtualMethod().getOrThrow()
    if (method.IsPureAbstract()) {
        return SentinelI8Ptr(cgMod, i8PtrType)
    }
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let params = ArrayList<LLVMTypeRef>()
    params.add(typeInfoPtrType)
    let fnType = BuildLLVMFunctionType(typeInfoPtrType, params)
    let fnName = extendDefName + "_" + method.GetIdentifierWithoutPrefix() + "_GetOuterTiFn"
    let fn = cgMod.GetOrInsertFunction(fnName, fnType)
    if (unsafe { LLVMIsDeclaration(fn) } != 0) {
        unsafe { LLVMSetLinkage(fn, LLVMLinkageValue(LLVMLinkage.Private)) }
        AddFnAttr(fn, "native-interface-fn")
        unsafe { LLVMSetUnnamedAddress(fn, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr)) }
        let entry = IRBuilder2(cgMod)
        let block = entry.CreateEntryBasicBlock(fn, "entry")
        entry.SetInsertPoint(block)
        let targetTypeInfo = unsafe { LLVMGetParam(fn, 0u32) }
        let parentType = funcInfo.GetInstParentType().StripAllRefs()
        let outerTi = if (parentType.IsGenericRelated()) {
            entry.SetInsertPointForPreparingTypeInfo()
            let targetTypeArgs = entry.GetTypeArgsFromTypeInfo(targetTypeInfo)
            entry.SetInsertPoint(block)
            CreateTypeInfoForCallbackBody(cgMod, entry, block, parentType, RuntimeGenericParams(targetType),
                targetTypeArgs)
        } else {
            CGType.GetOrCreate(cgMod, parentType).GetOrCreateTypeInfo()
        }
        entry.CreateRet(entry.CreateBitCast(outerTi, typeInfoPtrType, name: "outer.ti"))
        entry.close()
    } else {
        CJC_ASSERT_WITH_MSG(false,
            "GenerateOuterTiFn should not be called multiple times for the same function. Something is wrong.")
    }
    return unsafe { LLVMConstBitCast(fn, i8PtrType) }
}

private func GenerateFuncTableForType(cgMod: CGModule, extendDefName: String, targetType: Type,
    inheritedType: ClassType, vTable: VTableInType, i8PtrType: LLVMTypeRef): LLVMValueRef {
    let _ = inheritedType
    if (vTable.IsEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let funcTableSize = vTable.GetMethodNum()
    CJC_ASSERT(funcTableSize != 0)
    let tableType = unsafe { LLVMArrayType(i8PtrType, UInt32(funcTableSize * 2)) }
    let table = GetOrInsertCodeGenGlobal(cgMod, extendDefName + ".ft", tableType)
    if (unsafe { LLVMIsDeclaration(table) } != 0) {
        let values = ArrayList<LLVMValueRef>()
        let virtualMethods = vTable.GetVirtualMethods()
        for (funcInfo in virtualMethods) {
            let method = funcInfo.GetVirtualMethod().getOrThrow()
            if (!method.IsPureAbstract()) {
                values.add(unsafe { LLVMConstBitCast(cgMod.GetOrInsertCGFunction(method).GetRawFunction(), i8PtrType) })
            } else {
                values.add(unsafe { LLVMConstNull(i8PtrType) })
            }
        }
        for (funcInfo2 in virtualMethods) {
            values.add(if (targetType.GetTypeArgs().isEmpty()) {
                GenerateOuterTi(cgMod, funcInfo2, i8PtrType)
            } else {
                GenerateOuterTiFn(cgMod, extendDefName, targetType, funcInfo2, i8PtrType)
            })
        }
        unsafe {
            LLVMSetInitializer(table, ConstArray(i8PtrType, values))
            LLVMSetLinkage(table, LLVMLinkageValue(LLVMLinkage.Private))
        }
        addAttribute(table, CJED_FUNC_TABLE_ATTR)
    }
    return unsafe { LLVMConstBitCast(table, i8PtrType) }
}

private func IsCoreObjectDef(def: CustomTypeDef): Bool {
    return def.GetPackageName() == "std.core" && def.GetSrcCodeIdentifier() == "Object"
}

private func CoreObjectClassDef(def: ClassDef): ClassDef {
    var current = def
    while (let Some(superDef) <- current.GetSuperClassDef()) {
        current = superDef
    }
    return current
}

private func SentinelI8Ptr(cgMod: CGModule, i8PtrType: LLVMTypeRef): LLVMValueRef {
    let i64Type = unsafe { LLVMInt64TypeInContext(cgMod.GetLLVMContext().raw) }
    return unsafe { LLVMConstIntToPtr(LLVMConstInt(i64Type, 1u64, 0), i8PtrType) }
}

private func RuntimeGenericParams(targetType: Type): ArrayList<GenericType> {
    if (let Some(customTy) <- (targetType.StripAllRefs() as CustomType)) {
        return customTy.GetCustomTypeDef().GetGenericTypeParams()
    }
    return ArrayList<GenericType>()
}

private func TypeInfoAsI8Ptr(cgMod: CGModule, ty: Type, i8PtrType: LLVMTypeRef): LLVMValueRef {
    return unsafe { LLVMConstBitCast(CGType.GetOrCreate(cgMod, ty.StripAllRefs()).GetOrCreateTypeInfo(), i8PtrType) }
}

private func CoreObjectTypeInfoAsI8Ptr(cgMod: CGModule, i8PtrType: LLVMTypeRef): LLVMValueRef {
    let typeInfoTy = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
    let objectTypeInfo = GetOrInsertCodeGenGlobal(cgMod, "std.core:Object.ti", typeInfoTy)
    LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), objectTypeInfo, GC_TYPE_META_NAME,
        GetClassObjLayoutName("std.core:Object"))
    return unsafe { LLVMConstBitCast(objectTypeInfo, i8PtrType) }
}

private func CollectImplementedInterfaces(def: CustomTypeDef): ArrayList<ClassType> {
    let out = ArrayList<ClassType>()
    for (interfaceTy in def.GetImplementedInterfaceTys()) {
        AddInterfaceType(out, interfaceTy)
        CollectSuperInterfaces(interfaceTy, out)
    }
    return out
}

private func CollectSuperInterfaces(interfaceTy: ClassType, out: ArrayList<ClassType>): Unit {
    for (parentTy in interfaceTy.GetClassDef().GetImplementedInterfaceTys()) {
        AddInterfaceType(out, parentTy)
        CollectSuperInterfaces(parentTy, out)
    }
}

private func AddInterfaceType(out: ArrayList<ClassType>, interfaceTy: ClassType): Unit {
    for (existing in out) {
        if (existing.GetClassDef().nodeId == interfaceTy.GetClassDef().nodeId) {
            return
        }
    }
    out.add(interfaceTy)
}

private func IsDirectInterface(def: CustomTypeDef, interfaceTy: ClassType): Bool {
    for (directTy in def.GetImplementedInterfaceTys()) {
        if (directTy.GetClassDef().nodeId == interfaceTy.GetClassDef().nodeId) {
            return true
        }
    }
    return false
}

private func RequireClassType(def: ClassDef): ClassType {
    if (let Some(ty) <- def.GetType()) {
        if (let Some(classTy) <- (ty as ClassType)) {
            return classTy
        }
    }
    throw IllegalStateException("class-like def has no class type: " + def.GetIdentifier())
}

private func IsCoreObjectType(ty: ClassType): Bool {
    let def = ty.GetClassDef()
    return IsCoreObjectDef(def)
}

private func IsClosureConversionEnvClass(def: ClassDef): Bool {
    return def.GetAnnotation("IsAutoEnvClass").isSome()
}

private func RequireCustomType(def: CustomTypeDef): Type {
    if (let Some(ty) <- def.GetType()) {
        return ty
    }
    throw IllegalStateException("custom def has no type: " + def.GetIdentifier())
}

private func RequireExtensionTargetType(def: CustomTypeDef): Type {
    if (let Some(extendDef) <- (def as ExtendDef)) {
        if (let Some(extendedType) <- extendDef.GetExtendedType()) {
            return extendedType
        }
    }
    return RequireCustomType(def)
}

private func ExtensionDefName(targetType: Type, inheritedType: ClassType): String {
    return GetTypeQualifiedName(targetType) + "_ed_" + GetTypeQualifiedName(inheritedType)
}

private func TargetPackageName(targetType: Type): String {
    if (let Some(customTy) <- (targetType.StripAllRefs() as CustomType)) {
        return customTy.GetCustomTypeDef().GetPackageName()
    }
    return ""
}

private func SameRootPackage(left: String, right: String): Bool {
    return RootPackage(left) == RootPackage(right)
}

private func RootPackage(name: String): String {
    let dot = name.indexOf(".")
    if (let Some(idx) <- dot) {
        return name[0..idx]
    }
    return name
}

private func BuildLLVMFunctionType(returnType: LLVMTypeRef, paramTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
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

private func EmitNonExternalExtensionDefsTable(cgMod: CGModule): Unit {
    let defs = cgMod.GetNonExternalExtensionDefs()
    if (defs.isEmpty()) {
        return
    }
    let extensionDefPtrType = CGType.GetOrCreateExtensionDefPtrType(cgMod.GetLLVMContext())
    let values = ArrayList<LLVMValueRef>()
    for (def in defs) {
        values.add(def)
    }
    values.add(unsafe { LLVMConstNull(extensionDefPtrType) })
    let arrayType = unsafe { LLVMArrayType(extensionDefPtrType, UInt32(values.size)) }
    let table = GetOrInsertCodeGenGlobal(cgMod, EXTENSION_DEFS_NAME, arrayType)
    unsafe {
        LLVMSetInitializer(table, ConstArray(extensionDefPtrType, values))
        LLVMSetLinkage(table, LLVMLinkageValue(LLVMLinkage.Private))
        LLVMSetGlobalConstant(table, 0)
    }
    cgMod.GetCGContext().AddLLVMUsedVars(EXTENSION_DEFS_NAME)
}

private func ConstNamedStruct(structType: LLVMTypeRef, values: ArrayList<LLVMValueRef>): LLVMValueRef {
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
