package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Type

private let EXTENSION_DEFS_NAME: String = "NonExternalExtensionDefs"

public func GenerateInterfaceExtensionDefs(cgMod: CGModule): Unit {
    for (def in cgMod.GetCGContext().GetSubCHIRPackage().chirCustomDefs) {
        if (def.TestAttr(Attribute.IMPORTED)) {
            continue
        }
        if (!IsCurrentPackageDef(cgMod, def)) {
            continue
        }
        if (let Some(classDef) <- (def as ClassDef)) {
            GenerateExtensionDefsForClassLike(cgMod, classDef)
        }
    }
    EmitNonExternalExtensionDefsTable(cgMod)
}

public func RedefineTypeInfosForCustomDefs(cgMod: CGModule): Unit {
    for (def in cgMod.GetCGContext().GetSubCHIRPackage().chirCustomDefs) {
        if (!IsCurrentPackageDef(cgMod, def)) {
            continue
        }
        if (let Some(ty) <- def.GetType()) {
            RedefineTypeInfoGlobal(cgMod, ty)
        }
    }
}

private func IsCurrentPackageDef(cgMod: CGModule, def: CustomTypeDef): Bool {
    return def.GetPackageName() == cgMod.GetCGContext().GetCurrentPkgName()
}

private func GenerateExtensionDefsForClassLike(cgMod: CGModule, def: ClassDef): Unit {
    if (let None <- def.GetType()) {
        return
    }
    let startIdx = cgMod.GetNonExternalExtensionDefsNum()
    var emitted = false
    if (!def.IsInterface()) {
        if (GenerateObjectExtensionDefForType(cgMod, def)) {
            emitted = true
        }
        if (GenerateExtensionDefForType(cgMod, def, RequireClassType(def), false)) {
            emitted = true
        }
    } else if (!def.GetMethods().isEmpty()) {
        if (GenerateExtensionDefForType(cgMod, def, RequireClassType(def), false)) {
            emitted = true
        }
    }
    let interfaces = CollectImplementedInterfaces(def)
    for (interfaceTy in interfaces) {
        if (GenerateExtensionDefForType(cgMod, def, interfaceTy, IsDirectInterface(def, interfaceTy))) {
            emitted = true
        }
    }
    if (emitted) {
        if (let Some(ty) <- def.GetType()) {
            cgMod.RegisterExtensionDefStart(ty, startIdx)
        }
    }
}

private func GenerateObjectExtensionDefForType(cgMod: CGModule, targetDef: ClassDef): Bool {
    let targetType = RequireClassType(targetDef)
    let extensionDefType = CGType.GetOrCreateExtensionDefType(cgMod.GetLLVMContext())
    let name = CGType.GetRuntimeTypeName(targetType) + ".ed.std.core:Object"
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
    values.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    values.add(unsafe { LLVMConstInt(i8Type, 1u64, 0) })
    values.add(unsafe { LLVMConstInt(i8Type, 0b10000001u64, 0) })
    values.add(unsafe { LLVMConstInt(i16Type, 0u64, 0) })
    values.add(TypeInfoAsI8Ptr(cgMod, targetType, i8PtrType))
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

private func GenerateExtensionDefForType(cgMod: CGModule, targetDef: ClassDef, inheritedType: ClassType,
    direct: Bool): Bool {
    let targetType = RequireClassType(targetDef)
    let funcs = FunctionsForInheritedType(targetDef, inheritedType)
    if (funcs.isEmpty() && inheritedType.GetClassDef().IsInterface() &&
        inheritedType.GetClassDef().nodeId == targetDef.nodeId) {
        return false
    }
    let extensionDefType = CGType.GetOrCreateExtensionDefType(cgMod.GetLLVMContext())
    let name = ExtensionDefName(targetType, inheritedType)
    let extensionDef = GetOrInsertCodeGenGlobal(cgMod, name, extensionDefType)
    if (unsafe { LLVMIsDeclaration(extensionDef) } == 0) {
        return false
    }
    let content = BuildExtensionDefContent(cgMod, targetType, inheritedType, funcs, direct)
    unsafe {
        LLVMSetInitializer(extensionDef, ConstNamedStruct(extensionDefType, content))
        LLVMSetLinkage(extensionDef, LLVMLinkageValue(LLVMLinkage.Private))
        LLVMSetGlobalConstant(extensionDef, 1)
    }
    cgMod.AddNonExternalExtensionDef(extensionDef)
    return true
}

private func BuildExtensionDefContent(cgMod: CGModule, targetType: ClassType, inheritedType: ClassType,
    funcs: ArrayList<Option<Function>>, direct: Bool): ArrayList<LLVMValueRef> {
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i16Type = unsafe { LLVMInt16TypeInContext(context) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let values = ArrayList<LLVMValueRef>()
    values.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
    values.add(unsafe { LLVMConstInt(i8Type, 1u64, 0) })
    values.add(unsafe { LLVMConstInt(i8Type, ExtensionDefFlag(targetType, inheritedType, direct), 0) })
    values.add(unsafe { LLVMConstInt(i16Type, UInt64(funcs.size), 0) })
    values.add(TypeInfoAsI8Ptr(cgMod, targetType, i8PtrType))
    values.add(TypeInfoAsI8Ptr(cgMod, inheritedType, i8PtrType))
    values.add(unsafe { LLVMConstNull(i8PtrType) })
    values.add(GenerateFuncTableForType(cgMod, targetType, inheritedType, funcs, i8PtrType))
    return values
}

private func ExtensionDefFlag(targetType: ClassType, inheritedType: ClassType, direct: Bool): UInt64 {
    var flag: UInt64 = 0b00000001u64
    if (direct) {
        flag |= 0b10000000u64
    }
    if (SameRootPackage(targetType.GetClassDef().GetPackageName(), inheritedType.GetClassDef().GetPackageName())) {
        flag |= 0b00000110u64
    }
    return flag
}

private func GenerateFuncTableForType(cgMod: CGModule, targetType: ClassType, inheritedType: ClassType,
    funcs: ArrayList<Option<Function>>, i8PtrType: LLVMTypeRef): LLVMValueRef {
    if (funcs.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let tableType = unsafe { LLVMArrayType(i8PtrType, UInt32(funcs.size * 2)) }
    let table = GetOrInsertCodeGenGlobal(cgMod, ExtensionDefName(targetType, inheritedType) + ".ft", tableType)
    if (unsafe { LLVMIsDeclaration(table) } != 0) {
        let values = ArrayList<LLVMValueRef>()
        for (fn in funcs) {
            values.add(FunctionAsI8Ptr(cgMod, fn, i8PtrType))
        }
        for (fn2 in funcs) {
            values.add(OuterTypeInfoForFunction(cgMod, targetType, fn2, i8PtrType))
        }
        unsafe {
            LLVMSetInitializer(table, ConstArray(i8PtrType, values))
            LLVMSetLinkage(table, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(table, 1)
        }
    }
    return unsafe { LLVMConstBitCast(table, i8PtrType) }
}

private func FunctionsForInheritedType(targetDef: ClassDef, inheritedType: ClassType): ArrayList<Option<Function>> {
    let out = ArrayList<Option<Function>>()
    let inheritedDef = inheritedType.GetClassDef()
    if (inheritedDef.nodeId == targetDef.nodeId) {
        if (!targetDef.IsInterface()) {
            return out
        }
        for (method in targetDef.GetMethods()) {
            if (!method.IsConstructor()) {
                out.add(None)
            }
        }
        return out
    }
    for (interfaceMethod in inheritedDef.GetMethods()) {
        if (interfaceMethod.IsConstructor()) {
            continue
        }
        out.add(FindImplementation(targetDef, interfaceMethod))
    }
    return out
}

private func FindImplementation(targetDef: ClassDef, interfaceMethod: Function): Option<Function> {
    for (method in targetDef.GetMethods()) {
        if (method.IsConstructor()) {
            continue
        }
        if (MethodNameMatches(method, interfaceMethod.GetSrcCodeIdentifier()) ||
            MethodNameMatches(method, interfaceMethod.GetIdentifierWithoutPrefix())) {
            return Some(method)
        }
    }
    if (let Some(superDef) <- targetDef.GetSuperClassDef()) {
        return FindImplementation(superDef, interfaceMethod)
    }
    return None
}

private func MethodNameMatches(method: Function, name: String): Bool {
    return method.GetSrcCodeIdentifier() == name || method.GetIdentifierWithoutPrefix() == name ||
        method.GetRawMangledName() == name
}

private func FunctionAsI8Ptr(cgMod: CGModule, fn: Option<Function>, i8PtrType: LLVMTypeRef): LLVMValueRef {
    if (let Some(method) <- fn) {
        if (method.TestAttr(Attribute.ABSTRACT)) {
            return unsafe { LLVMConstNull(i8PtrType) }
        }
        return unsafe { LLVMConstBitCast(cgMod.GetOrInsertCGFunction(method).GetRawFunction(), i8PtrType) }
    }
    return unsafe { LLVMConstNull(i8PtrType) }
}

private func OuterTypeInfoForFunction(cgMod: CGModule, targetType: ClassType, fn: Option<Function>,
    i8PtrType: LLVMTypeRef): LLVMValueRef {
    if (let Some(method) <- fn) {
        if (let Some(parent) <- method.GetParentCustomTypeDef()) {
            if (let Some(parentType) <- parent.GetType()) {
                return TypeInfoAsI8Ptr(cgMod, parentType, i8PtrType)
            }
        }
    }
    return TypeInfoAsI8Ptr(cgMod, targetType, i8PtrType)
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

private func CollectImplementedInterfaces(def: ClassDef): ArrayList<ClassType> {
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

private func IsDirectInterface(def: ClassDef, interfaceTy: ClassType): Bool {
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

private func ExtensionDefName(targetType: ClassType, inheritedType: ClassType): String {
    return CGType.GetRuntimeTypeName(targetType) + ".ed." + CGType.GetRuntimeTypeName(inheritedType)
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
