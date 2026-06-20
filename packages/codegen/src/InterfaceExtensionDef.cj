package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKindIndex

private let EXTENSION_DEFS_NAME: String = "NonExternalExtensionDefs"

private class InterfaceFunctionEntry {
    public let implementation: Option<Function>
    public let expected: Option<Function>

    public init(implementation: Option<Function>, expected: Option<Function>) {
        this.implementation = implementation
        this.expected = expected
    }
}

public func GenerateInterfaceExtensionDefs(cgMod: CGModule): Unit {
    for (def in cgMod.GetCGContext().GetSubCHIRPackage().chirCustomDefs) {
        if (def.TestAttr(Attribute.IMPORTED)) {
            continue
        }
        if (!IsCurrentPackageDef(cgMod, def)) {
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

private func GenerateExtensionDefsForCustomDef(cgMod: CGModule, def: CustomTypeDef): Unit {
    if (let None <- def.GetType()) {
        return
    }
    let startIdx = cgMod.GetNonExternalExtensionDefsNum()
    var emitted = false
    if (let Some(classDef) <- (def as ClassDef)) {
        if (!classDef.IsInterface()) {
            if (GenerateObjectExtensionDefForType(cgMod, classDef)) {
                emitted = true
            }
            if (GenerateExtensionDefForType(cgMod, def, RequireClassType(classDef), false)) {
                emitted = true
            }
        } else if (!def.GetMethods().isEmpty() && !RequireClassType(classDef).IsGenericRelated()) {
            if (GenerateExtensionDefForType(cgMod, def, RequireClassType(classDef), false)) {
                emitted = true
            }
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

private func GenerateExtensionDefForType(cgMod: CGModule, targetDef: CustomTypeDef, inheritedType: ClassType,
    direct: Bool): Bool {
    let targetType = RequireCustomType(targetDef)
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

private func BuildExtensionDefContent(cgMod: CGModule, targetType: Type, inheritedType: ClassType,
    funcs: ArrayList<InterfaceFunctionEntry>, direct: Bool): ArrayList<LLVMValueRef> {
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

private func GenerateFuncTableForType(cgMod: CGModule, targetType: Type, inheritedType: ClassType,
    funcs: ArrayList<InterfaceFunctionEntry>, i8PtrType: LLVMTypeRef): LLVMValueRef {
    if (funcs.isEmpty()) {
        return unsafe { LLVMConstNull(i8PtrType) }
    }
    let tableType = unsafe { LLVMArrayType(i8PtrType, UInt32(funcs.size * 2)) }
    let table = GetOrInsertCodeGenGlobal(cgMod, ExtensionDefName(targetType, inheritedType) + ".ft", tableType)
    if (unsafe { LLVMIsDeclaration(table) } != 0) {
        let values = ArrayList<LLVMValueRef>()
        for (fn in funcs) {
            values.add(FunctionAsI8Ptr(cgMod, targetType, inheritedType, fn, i8PtrType))
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

private func FunctionsForInheritedType(targetDef: CustomTypeDef, inheritedType: ClassType): ArrayList<InterfaceFunctionEntry> {
    let out = ArrayList<InterfaceFunctionEntry>()
    let inheritedDef = inheritedType.GetClassDef()
    if (inheritedDef.nodeId == targetDef.nodeId) {
        if (!targetDef.IsInterface()) {
            return out
        }
        for (method in targetDef.GetMethods()) {
            if (!method.IsConstructor()) {
                out.add(InterfaceFunctionEntry(DefaultMethodOrNone(method), Some(method)))
            }
        }
        return out
    }
    for (interfaceMethod in inheritedDef.GetMethods()) {
        if (interfaceMethod.IsConstructor()) {
            continue
        }
        out.add(InterfaceFunctionEntry(FindImplementation(targetDef, interfaceMethod), Some(interfaceMethod)))
    }
    return out
}

private func FindImplementation(targetDef: CustomTypeDef, interfaceMethod: Function): Option<Function> {
    for (method in targetDef.GetMethods()) {
        if (method.IsConstructor()) {
            continue
        }
        if (MethodNameMatches(method, interfaceMethod.GetSrcCodeIdentifier()) ||
            MethodNameMatches(method, interfaceMethod.GetIdentifierWithoutPrefix())) {
            return Some(method)
        }
    }
    if (let Some(classDef) <- (targetDef as ClassDef)) {
        if (let Some(superDef) <- classDef.GetSuperClassDef()) {
            return FindImplementation(superDef, interfaceMethod)
        }
    }
    return DefaultMethodOrNone(interfaceMethod)
}

private func DefaultMethodOrNone(method: Function): Option<Function> {
    if (!method.TestAttr(Attribute.ABSTRACT) && method.GetBody().isSome()) {
        return Some(method)
    }
    return None
}

private func MethodNameMatches(method: Function, name: String): Bool {
    return method.GetSrcCodeIdentifier() == name || method.GetIdentifierWithoutPrefix() == name ||
        method.GetRawMangledName() == name
}

private func FunctionAsI8Ptr(cgMod: CGModule, targetType: Type, inheritedType: ClassType,
    entry: InterfaceFunctionEntry, i8PtrType: LLVMTypeRef): LLVMValueRef {
    if (let Some(method) <- entry.implementation) {
        if (method.TestAttr(Attribute.ABSTRACT)) {
            return unsafe { LLVMConstNull(i8PtrType) }
        }
        if (let Some(expected) <- entry.expected) {
            if (NeedsExpectedSlotWrapper(method, expected, targetType, inheritedType)) {
                return unsafe { LLVMConstBitCast(GetOrCreateExpectedSlotWrapper(cgMod, method, expected), i8PtrType) }
            }
        }
        return unsafe { LLVMConstBitCast(cgMod.GetOrInsertCGFunction(method).GetRawFunction(), i8PtrType) }
    }
    return unsafe { LLVMConstNull(i8PtrType) }
}

private func NeedsExpectedSlotWrapper(method: Function, expected: Function, selfTy: Type,
    instParentTy: ClassType): Bool {
    if (!selfTy.IsClassOrArray() && !method.TestAttr(Attribute.STATIC)) {
        return true
    }
    if (let Some(parentType) <- method.GetParentCustomTypeOrExtendedType()) {
        if (!parentType.IsEqual(selfTy) && parentType.IsGenericRelated() &&
            !IsEqualOrSubTypeOfWrapperParent(parentType, instParentTy)) {
            return true
        }
    }
    let methodTy = method.GetFuncType() ?? return false
    let expectedTy = expected.GetFuncType() ?? return false
    return !VirtualFuncTypeMatches(expectedTy, methodTy)
}

private func VirtualFuncTypeMatches(parentFuncType: Type, curFuncType: Type): Bool {
    let parentTy = (parentFuncType as FuncType) ?? return parentFuncType.IsEqual(curFuncType)
    let curTy = (curFuncType as FuncType) ?? return false
    let parentParams = parentTy.GetParamTypes()
    let curParams = curTy.GetParamTypes()
    if (parentParams.size != curParams.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < parentParams.size) {
        if (!VirtualParamTypeMatches(parentParams[idx], curParams[idx])) {
            return false
        }
        idx++
    }
    return VirtualReturnTypeMatches(parentTy.GetReturnType(), curTy.GetReturnType())
}

private func VirtualParamTypeMatches(left: Type, right: Type): Bool {
    if ((left.IsGeneric() || left.IsRef() || left.IsCJFunc()) &&
        (right.IsGeneric() || right.IsRef() || right.IsCJFunc())) {
        return true
    }
    return VirtualStructuralTypeMatches(left, right)
}

private func VirtualReturnTypeMatches(left: Type, right: Type): Bool {
    if (left.IsGeneric() && right.IsGeneric()) {
        return true
    }
    if ((left.IsRef() || left.IsCJFunc()) && (right.IsRef() || right.IsCJFunc())) {
        return true
    }
    return VirtualStructuralTypeMatches(left, right)
}

private func VirtualStructuralTypeMatches(left: Type, right: Type): Bool {
    if (TypeKindIndex(left.GetTypeKind()) != TypeKindIndex(right.GetTypeKind())) {
        return false
    }
    let leftArgs = left.GetTypeArgs()
    let rightArgs = right.GetTypeArgs()
    if (leftArgs.size != rightArgs.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < leftArgs.size) {
        if (!VirtualStructuralTypeMatches(leftArgs[idx], rightArgs[idx])) {
            return false
        }
        idx++
    }
    return true
}

private func IsEqualOrSubTypeOfWrapperParent(parentType: Type, instParentTy: ClassType): Bool {
    if (parentType.IsEqual(instParentTy)) {
        return true
    }
    let parentClassTy = (parentType.StripAllRefs() as ClassType) ?? return false
    if (parentClassTy.GetClassDef().nodeId == instParentTy.GetClassDef().nodeId) {
        return true
    }
    return ClassTypeHasInterface(parentClassTy, instParentTy)
}

private func ClassTypeHasInterface(sourceTy: ClassType, targetTy: ClassType): Bool {
    let sourceDef = sourceTy.GetClassDef()
    if (let Some(superTy) <- sourceTy.GetSuperClassTy()) {
        if (superTy.GetClassDef().nodeId == targetTy.GetClassDef().nodeId || ClassTypeHasInterface(superTy, targetTy)) {
            return true
        }
    }
    for (interfaceTy in sourceDef.GetImplementedInterfaceTys()) {
        if (interfaceTy.GetClassDef().nodeId == targetTy.GetClassDef().nodeId ||
            ClassTypeHasInterface(interfaceTy, targetTy)) {
            return true
        }
    }
    return false
}

private func GetOrCreateExpectedSlotWrapper(cgMod: CGModule, method: Function, expected: Function): LLVMValueRef {
    let expectedCGType = (CGType.GetOrCreateWithNode(cgMod, expected, allowBasePtr: true,
        forWrapper: true) as CGFunctionType) ?? return cgMod.GetOrInsertCGFunction(method).GetRawFunction()
    let wrapperName = GetCodeGenGlobalName(method) + "$ifwrap$" + GetCodeGenGlobalName(expected)
    let wrapper = cgMod.GetOrInsertFunction(wrapperName, expectedCGType.GetLLVMFunctionType())
    if (unsafe { LLVMIsDeclaration(wrapper) } == 0) {
        return wrapper
    }
    unsafe { LLVMSetLinkage(wrapper, LLVMLinkageValue(LLVMLinkage.Private)) }
    if (expectedCGType.HasSRet()) {
        if (let Some(expectedTy) <- expected.GetFuncType()) {
            let expectedRetCGType = CGType.GetOrCreate(cgMod, expectedTy.GetReturnType())
            AddSRetAttribute(wrapper, expectedRetCGType.GetLLVMType())
            AddNoAliasAttribute(wrapper)
        } else {
            AddSRetAttribute(wrapper)
            AddNoAliasAttribute(wrapper)
        }
    }
    SetCangjieGC(wrapper)
    let entry = IRBuilder2(cgMod)
    let block = entry.CreateEntryBasicBlock(wrapper, "entry")
    entry.SetInsertPoint(block)
    EmitExpectedSlotWrapperBody(entry, wrapper, method, expectedCGType)
    entry.close()
    return wrapper
}

private func EmitExpectedSlotWrapperBody(irBuilder: IRBuilder2, wrapper: LLVMValueRef, method: Function,
    expectedCGType: CGFunctionType): Unit {
    let expectedTy = if (let Some(fnTy) <- (expectedCGType.GetOriginal() as FuncType)) {
        fnTy
    } else {
        irBuilder.CreateRetVoid()
        return
    }
    let methodTy = if (let Some(fnTy) <- method.GetFuncType()) {
        fnTy
    } else {
        irBuilder.CreateRetVoid()
        return
    }
    let methodCGFunc = irBuilder.GetCGModule().GetOrInsertCGFunction(method)
    let methodCGType = if (let Some(fnTy) <- methodCGFunc.GetCGFunctionType()) {
        fnTy
    } else {
        irBuilder.CreateRetVoid()
        return
    }
    let expectedArgIndices = expectedCGType.GetRealArgIndices()
    let expectedParamTys = expectedTy.GetParamTypes()
    let methodParamTys = methodTy.GetParamTypes()
    let callArgs = ArrayList<CGValue>()
    var idx: Int64 = 0
    while (idx < methodParamTys.size && idx < expectedArgIndices.size && idx < expectedParamTys.size) {
        let rawArg = unsafe { LLVMGetParam(wrapper, UInt32(expectedArgIndices[idx])) }
        let (convertedArg, convertedTy) = ConvertExpectedArgForMethod(irBuilder, rawArg, expectedParamTys[idx],
            methodParamTys[idx], idx)
        callArgs.add(CGValue(convertedArg, CGType.GetOrCreate(irBuilder.GetCGModule(), convertedTy)))
        idx++
    }
    let methodTypeInfoArg = GetWrapperMethodTypeInfoArg(expectedCGType, wrapper)
    let result = irBuilder.CreateCallOrInvokeWithMethodTypeInfo(methodCGType, methodCGFunc.GetRawFunction(),
        callArgs, methodTypeInfoArg, name: "ifwrap.call")
    EmitExpectedSlotWrapperReturn(irBuilder, wrapper, expectedCGType, expectedTy.GetReturnType(),
        methodTy.GetReturnType(), result)
}

private func GetWrapperMethodTypeInfoArg(expectedCGType: CGFunctionType, wrapper: LLVMValueRef): Option<LLVMValueRef> {
    if (let Some(index) <- expectedCGType.GetMethodTypeInfoIndex()) {
        return Some(unsafe { LLVMGetParam(wrapper, UInt32(index)) })
    }
    if (let Some(index2) <- expectedCGType.GetStaticMethodTypeInfoIndex()) {
        return Some(unsafe { LLVMGetParam(wrapper, UInt32(index2)) })
    }
    return None
}

private func ConvertExpectedArgForMethod(irBuilder: IRBuilder2, rawArg: LLVMValueRef, expectedParamTy: Type,
    methodParamTy: Type, idx: Int64): (LLVMValueRef, Type) {
    if (methodParamTy.IsGeneric()) {
        return (rawArg, expectedParamTy)
    }
    if (ShouldUnboxObjectForTarget(expectedParamTy, methodParamTy)) {
        return (UnboxObjectValue(irBuilder, rawArg, methodParamTy, true, "ifwrap.arg.${idx}"), methodParamTy)
    }
    if (expectedParamTy.IsEqual(methodParamTy) || VirtualParamTypeMatches(expectedParamTy, methodParamTy)) {
        return (rawArg, expectedParamTy)
    }
    let targetLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), methodParamTy).GetLLVMType()
    return (CastValueToType(irBuilder, rawArg, expectedParamTy, methodParamTy, targetLLVMType), methodParamTy)
}

private func EmitExpectedSlotWrapperReturn(irBuilder: IRBuilder2, wrapper: LLVMValueRef,
    expectedCGType: CGFunctionType, expectedRetTy: Type, methodRetTy: Type, result: LLVMValueRef): Unit {
    if (expectedCGType.HasSRet()) {
        let returnSlot = unsafe { LLVMGetParam(wrapper, 0u32) }
        irBuilder.CreateStore(ConvertReturnForExpectedSlot(irBuilder, result, methodRetTy, expectedRetTy), returnSlot)
        irBuilder.CreateRetVoid()
        return
    }
    if (expectedRetTy.IsNothing() || expectedRetTy.IsVoid()) {
        irBuilder.CreateRetVoid()
        return
    }
    irBuilder.CreateRet(ConvertReturnForDirectReturn(irBuilder, result, methodRetTy, expectedRetTy))
}

private func ConvertReturnForExpectedSlot(irBuilder: IRBuilder2, result: LLVMValueRef, methodRetTy: Type,
    expectedRetTy: Type): LLVMValueRef {
    if (expectedRetTy.IsGeneric()) {
        return BoxValueForGenericSlot(irBuilder, result, methodRetTy)
    }
    if (ShouldUnboxObjectForTarget(methodRetTy, expectedRetTy)) {
        return UnboxObjectValue(irBuilder, result, expectedRetTy, false, "ifwrap.ret")
    }
    if (methodRetTy.IsEqual(expectedRetTy) || VirtualReturnTypeMatches(expectedRetTy, methodRetTy)) {
        return result
    }
    return CastValueToType(irBuilder, result, methodRetTy, expectedRetTy,
        CGType.GetOrCreate(irBuilder.GetCGModule(), expectedRetTy).GetLLVMType())
}

private func ConvertReturnForDirectReturn(irBuilder: IRBuilder2, result: LLVMValueRef, methodRetTy: Type,
    expectedRetTy: Type): LLVMValueRef {
    if (expectedRetTy.IsGeneric()) {
        return BoxValueForGenericSlot(irBuilder, result, methodRetTy)
    }
    if (ShouldUnboxObjectForTarget(methodRetTy, expectedRetTy)) {
        return UnboxObjectValue(irBuilder, result, expectedRetTy, false, "ifwrap.ret")
    }
    if (methodRetTy.IsEqual(expectedRetTy) || VirtualReturnTypeMatches(expectedRetTy, methodRetTy)) {
        return result
    }
    return CastValueToType(irBuilder, result, methodRetTy, expectedRetTy,
        CGType.GetOrCreate(irBuilder.GetCGModule(), expectedRetTy).GetLLVMType())
}

private func BoxValueForGenericSlot(irBuilder: IRBuilder2, result: LLVMValueRef, resultTy: Type): LLVMValueRef {
    let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
    if (resultTy.IsReferenceType() || resultTy.IsRef() || resultCGType.IsReference()) {
        return result
    }
    let objectValue = irBuilder.CallValueIntrinsicAlloc(resultTy)
    irBuilder.StoreValueToObjectPayload(objectValue, result, resultTy)
    return objectValue
}

private func ShouldUnboxObjectForTarget(sourceTy: Type, targetTy: Type): Bool {
    if (!IsObjectReferenceType(sourceTy)) {
        return false
    }
    let targetBase = targetTy.StripAllRefs()
    return targetBase.IsValueType() || targetBase.IsGeneric()
}

private func IsObjectReferenceType(ty: Type): Bool {
    if (ty.IsGeneric()) {
        return true
    }
    let baseTy = ty.StripAllRefs()
    return baseTy.IsClassOrArray() || baseTy.IsBox() || baseTy.IsThis()
}

private func UnboxObjectValue(irBuilder: IRBuilder2, objectValue: LLVMValueRef, targetTy: Type, forArgument: Bool,
    name: String): LLVMValueRef {
    let valueTy = targetTy.StripAllRefs()
    let valueCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), valueTy)
    let payload = irBuilder.GetPayloadFromObject(objectValue)
    let payloadType = unsafe { LLVMPointerType(valueCGType.GetLLVMType(), 1u32) }
    let typedPayload = irBuilder.CreateBitCast(payload, payloadType, name: name + ".payload")
    if (forArgument && targetTy.IsRef()) {
        return typedPayload
    }
    return irBuilder.CreateLoad(valueCGType.GetLLVMType(), typedPayload, name: name + ".value")
}

private func OuterTypeInfoForFunction(cgMod: CGModule, targetType: Type, entry: InterfaceFunctionEntry,
    i8PtrType: LLVMTypeRef): LLVMValueRef {
    if (let Some(method) <- entry.implementation) {
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

private func RequireCustomType(def: CustomTypeDef): Type {
    if (let Some(ty) <- def.GetType()) {
        return ty
    }
    throw IllegalStateException("custom def has no type: " + def.GetIdentifier())
}

private func ExtensionDefName(targetType: Type, inheritedType: ClassType): String {
    return CGType.GetRuntimeTypeName(targetType) + ".ed." + CGType.GetRuntimeTypeName(inheritedType)
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
