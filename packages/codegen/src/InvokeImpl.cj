package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.DynamicDispatch
import cangjie_compiler::chir.DynamicDispatchWithException
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.FuncKind
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.Invoke
import cangjie_compiler::chir.InvokeStatic
import cangjie_compiler::chir.InvokeStaticWithException
import cangjie_compiler::chir.InvokeWithException
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeKindIndex
import cangjie_compiler::chir.Value

private let GET_VTABLE_FUNC_INTRINSIC_NAME: String = "llvm.cj.get.vtable.func"
private let GET_MTABLE_FUNC_INTRINSIC_NAME: String = "llvm.cj.get.mtable.func"
private let GET_METHOD_OUTERTYPE_INTRINSIC_NAME: String = "llvm.cj.get.method.outertype"
private let GENERIC_VIRTUAL_FUNC: String = "$GenericVirtualFunc"
private let INST_VIRTUAL_FUNC: String = "$InstVirtualFunc"

private class ClassVTable {
    public let parentDef: ClassDef
    public let slots: ArrayList<Option<Function>>

    public init(parentDef: ClassDef, slots: ArrayList<Option<Function>>) {
        this.parentDef = parentDef
        this.slots = slots
    }
}

public func GenerateInvokeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(invokeExpr) <- (chirExpr as Invoke)) {
        return GenerateResolvedInvoke(irBuilder, invokeExpr.GetObject(), invokeExpr.GetMethodName(),
            invokeExpr.GetArgs(), invokeExpr.GetThisType(), invokeExpr.GetMethodType(),
            invokeExpr.GetVirtualMethodOffset(), invokeExpr.GetInstantiatedTypeArgs())
    }
    if (let Some(invokeWithExceptionExpr) <- (chirExpr as InvokeWithException)) {
        return GenerateResolvedInvoke(irBuilder, invokeWithExceptionExpr.GetObject(),
            invokeWithExceptionExpr.GetMethodName(), invokeWithExceptionExpr.GetArgs(),
            invokeWithExceptionExpr.GetThisType(), invokeWithExceptionExpr.GetMethodType(),
            invokeWithExceptionExpr.GetVirtualMethodOffset(), invokeWithExceptionExpr.GetInstantiatedTypeArgs())
    }
    if (let Some(invokeStaticExpr) <- (chirExpr as InvokeStatic)) {
        return GenerateResolvedStaticInvoke(irBuilder, invokeStaticExpr, invokeStaticExpr.GetArgs())
    }
    if (let Some(invokeStaticWithExceptionExpr) <- (chirExpr as InvokeStaticWithException)) {
        return GenerateResolvedStaticInvoke(irBuilder, invokeStaticWithExceptionExpr,
            invokeStaticWithExceptionExpr.GetArgs())
    }
    return LLVMNullValue()
}

private func GenerateResolvedInvoke(irBuilder: IRBuilder2, objectValue: Value, methodName: String,
    args: ArrayList<Value>, thisType: Option<Type>, methodType: FuncType,
    virtualMethodOffset: Option<UInt64>, instTypeArgs: ArrayList<Type>): LLVMValueRef {
    let ownerType = SelectInvokeOwnerType(thisType, objectValue.GetType())
    if (let Some(ownerTy) <- ownerType) {
        if (let Some(callee) <- FindMethodByName(ownerTy, methodName)) {
            return GenerateVirtualApply(irBuilder, ownerTy, methodName, callee, args, methodType, virtualMethodOffset,
                instTypeArgs)
        }
    }
    return LLVMNullValue()
}

private func SelectInvokeOwnerType(thisType: Option<Type>, objectType: Option<Type>): Option<Type> {
    if (let Some(thisTy) <- thisType) {
        if (let Some(objTy) <- objectType) {
            if (let Some(thisCustom) <- (thisTy.StripAllRefs() as CustomType)) {
                if (let Some(objCustom) <- (objTy.StripAllRefs() as CustomType)) {
                    if (ShouldPreferObjectOwnerType(thisCustom, objCustom)) {
                        return Some(objTy)
                    }
                }
            }
        }
        return Some(thisTy)
    }
    return objectType
}

private func ShouldPreferObjectOwnerType(thisCustom: CustomType, objCustom: CustomType): Bool {
    if (thisCustom.GetCustomTypeDef().nodeId != objCustom.GetCustomTypeDef().nodeId) {
        return false
    }
    let thisArgs = thisCustom.GetTypeArgs()
    let objArgs = objCustom.GetTypeArgs()
    if (thisArgs.isEmpty()) {
        return !objArgs.isEmpty()
    }
    if (thisArgs.size != objArgs.size) {
        return false
    }
    var sawGenericThisArg = false
    var idx: Int64 = 0
    while (idx < thisArgs.size) {
        if (thisArgs[idx].IsGenericRelated()) {
            sawGenericThisArg = true
            if (objArgs[idx].IsGenericRelated()) {
                return false
            }
        }
        idx++
    }
    return sawGenericThisArg
}

private func InstantiateVirtualOwnerType(ownerTy: Type, callee: Function, methodType: FuncType): Type {
    let classTy = (ownerTy.StripAllRefs() as ClassType) ?? return ownerTy
    if (!classTy.GetClassDef().IsInterface() || !classTy.GetTypeArgs().isEmpty()) {
        return ownerTy
    }
    let genericParams = classTy.GetClassDef().GetGenericTypeParams()
    if (genericParams.isEmpty()) {
        return ownerTy
    }
    let calleeTy = callee.GetFuncType() ?? return ownerTy
    let replacements = ArrayList<Option<Type>>()
    for (_ in genericParams) {
        replacements.add(None)
    }
    CollectGenericReplacements(calleeTy, methodType, genericParams, replacements)
    let typeArgs = ArrayList<Type>()
    for (replacement in replacements) {
        match (replacement) {
            case Some(ty) => typeArgs.add(ty)
            case None => return ownerTy
        }
    }
    return ClassType(classTy.GetClassDef(), typeArgs)
}

private func CollectGenericReplacements(pattern: Type, actual: Type, genericParams: ArrayList<GenericType>,
    replacements: ArrayList<Option<Type>>): Unit {
    if (let Some(genericTy) <- (pattern as GenericType)) {
        var idx: Int64 = 0
        while (idx < genericParams.size && idx < replacements.size) {
            if (genericTy.IsEqual(genericParams[idx])) {
                replacements[idx] = Some(actual)
                return
            }
            idx++
        }
        return
    }
    if (let Some(patternFunc) <- (pattern as FuncType)) {
        if (let Some(actualFunc) <- (actual as FuncType)) {
            let patternParams = patternFunc.GetParamTypes()
            let actualParams = actualFunc.GetParamTypes()
            var idx: Int64 = 0
            while (idx < patternParams.size && idx < actualParams.size) {
                CollectGenericReplacements(patternParams[idx], actualParams[idx], genericParams, replacements)
                idx++
            }
            CollectGenericReplacements(patternFunc.GetReturnType(), actualFunc.GetReturnType(), genericParams,
                replacements)
        }
        return
    }
    if (TypeKindIndex(pattern.GetTypeKind()) != TypeKindIndex(actual.GetTypeKind())) {
        return
    }
    let patternArgs = pattern.GetTypeArgs()
    let actualArgs = actual.GetTypeArgs()
    var idx: Int64 = 0
    while (idx < patternArgs.size && idx < actualArgs.size) {
        CollectGenericReplacements(patternArgs[idx], actualArgs[idx], genericParams, replacements)
        idx++
    }
}

private func GenerateVirtualApply(irBuilder: IRBuilder2, ownerTy: Type, methodName: String, callee: Function,
    args: ArrayList<Value>, methodType: FuncType, virtualMethodOffset: Option<UInt64>,
    instTypeArgs: ArrayList<Type>): LLVMValueRef {
    let callMethodType = SelectVirtualCallMethodType(ownerTy, callee, methodType)
    let typeExtra = TypeExtraInfo(0u32, true, false, true, instTypeArgs)
    let cgFuncType = (CGType.GetOrCreate(irBuilder.GetCGModule(), callMethodType, extraInfo: typeExtra) as
        CGFunctionType) ?? return LLVMNullValue()
    if (args.isEmpty()) {
        return LLVMNullValue()
    }
    let argValues = ArrayList<CGValue>()
    for (arg in args) {
        argValues.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, arg))
    }
    let virtualOwnerTy = InstantiateVirtualOwnerType(ownerTy, callee, methodType)
    let (introTy, methodIndex) = ResolveVirtualMethod(virtualOwnerTy, methodName, callee, virtualMethodOffset)
    let (calleePtr, methodTypeInfoArg) = BuildVirtualCallee(irBuilder, argValues[0], introTy, methodName,
        methodIndex, cgFuncType)
    return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(cgFuncType, calleePtr, argValues,
        Some(methodTypeInfoArg), instTypeArgs, name: "call")
}

private func SelectVirtualCallMethodType(ownerTy: Type, callee: Function, methodType: FuncType): FuncType {
    if (IsInterfaceOwnerType(ownerTy)) {
        if (let Some(calleeTy) <- callee.GetFuncType()) {
            if (calleeTy.IsGenericRelated()) {
                return calleeTy
            }
        }
    }
    return methodType
}

private func BuildVirtualCallee(irBuilder: IRBuilder2, objectValue: CGValue, ownerTy: Type, methodName: String,
    methodIndex: Int64, cgFuncType: CGFunctionType): (LLVMValueRef, LLVMValueRef) {
    let llvmContext = irBuilder.GetLLVMContext().raw
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(llvmContext), 0u32) }
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
    let typeInfoSlotType = unsafe { LLVMPointerType(typeInfoPtrType, 1u32) }
    let objectTypeInfoSlot = irBuilder.CreateBitCast(objectValue.GetRawValue(), typeInfoSlotType, name: "invoke.ti.slot")
    let objectTypeInfo = irBuilder.CreateLoad(typeInfoPtrType, objectTypeInfoSlot, name: "invoke.ti")
    let objectTypeInfoRaw = irBuilder.CreateBitCast(objectTypeInfo, i8PtrType, name: "invoke.ti.raw")
    if (IsAutoEnvObjectValue(objectValue)) {
        let payload = irBuilder.GetPayloadFromObject(objectValue.GetRawValue())
        let typedPayload = irBuilder.CreateBitCast(payload, unsafe { LLVMPointerType(i8PtrType, 1u32) },
            name: "invoke.autoenv.payload")
        let indices = ArrayList<LLVMValueRef>()
        indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(llvmContext), AutoEnvMethodIndex(methodName), 0) })
        let slot = irBuilder.CreateGEP(i8PtrType, typedPayload, indices, name: "invoke.autoenv.fn.addr")
        let rawCallee = irBuilder.CreateLoad(i8PtrType, slot, name: "invoke.autoenv.fn")
        return (irBuilder.CreateBitCast(rawCallee,
            unsafe { LLVMPointerType(cgFuncType.GetLLVMFunctionType(), 0u32) }, name: "invoke.fn.cast"),
            objectTypeInfo)
    }
    let strippedOwnerTy = ownerTy.StripAllRefs()
    let ownerCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), strippedOwnerTy)
    let ownerTypeInfo = if (ownerCGType.IsDynamicGI()) {
        irBuilder.CreateTypeInfo(strippedOwnerTy)
    } else {
        ownerCGType.GetOrCreateTypeInfo()
    }
    let ownerTypeInfoRaw = irBuilder.CreateBitCast(ownerTypeInfo, i8PtrType, name: "invoke.owner.ti")
    let isInterfaceCall = IsInterfaceOwnerType(ownerTy)
    let rawCallee = if (isInterfaceCall) {
        let intrinsicArgs = ArrayList<LLVMValueRef>()
        intrinsicArgs.add(objectTypeInfoRaw)
        intrinsicArgs.add(ownerTypeInfoRaw)
        intrinsicArgs.add(irBuilder.GetInt64(methodIndex))
        irBuilder.CreateIntrinsicCall(GET_MTABLE_FUNC_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), intrinsicArgs,
            name: "invoke.fn")
    } else {
        let introTypeIndex = VTableSizeOf(ownerTy) - 1
        let intrinsicArgs = ArrayList<LLVMValueRef>()
        intrinsicArgs.add(objectTypeInfoRaw)
        intrinsicArgs.add(irBuilder.GetInt64(introTypeIndex))
        intrinsicArgs.add(irBuilder.GetInt64(methodIndex))
        intrinsicArgs.add(ownerTypeInfoRaw)
        irBuilder.CreateIntrinsicCall(GET_VTABLE_FUNC_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), intrinsicArgs,
            name: "invoke.fn")
    }
    if (isInterfaceCall && ownerTy.StripAllRefs().GetTypeArgs().isEmpty()) {
        return (irBuilder.CreateBitCast(rawCallee,
            unsafe { LLVMPointerType(cgFuncType.GetLLVMFunctionType(), 0u32) }, name: "invoke.fn.cast"),
            unsafe { LLVMConstNull(typeInfoPtrType) })
    }
    let outerTypeInfoArgs = ArrayList<LLVMValueRef>()
    outerTypeInfoArgs.add(objectTypeInfoRaw)
    outerTypeInfoArgs.add(ownerTypeInfoRaw)
    outerTypeInfoArgs.add(irBuilder.GetInt64(methodIndex))
    let rawOuterTypeInfo = irBuilder.CreateIntrinsicCall(GET_METHOD_OUTERTYPE_INTRINSIC_NAME,
        ArrayList<LLVMTypeRef>(), outerTypeInfoArgs, name: "invoke.outer.ti.raw")
    let outerTypeInfo = irBuilder.CreateBitCast(rawOuterTypeInfo, typeInfoPtrType, name: "invoke.outer.ti")
    return (irBuilder.CreateBitCast(rawCallee,
        unsafe { LLVMPointerType(cgFuncType.GetLLVMFunctionType(), 0u32) }, name: "invoke.fn.cast"), outerTypeInfo)
}

private func IsAutoEnvObjectValue(objectValue: CGValue): Bool {
    if (let Some(cgType) <- objectValue.GetCGType()) {
        return IsAutoEnvType(cgType.GetOriginal())
    }
    return false
}

private func AutoEnvMethodIndex(methodName: String): UInt64 {
    if (methodName == GENERIC_VIRTUAL_FUNC) {
        return 0u64
    }
    if (methodName == INST_VIRTUAL_FUNC) {
        return 1u64
    }
    throw IllegalArgumentException("unexpected AutoEnv method: " + methodName)
}

private func VTableSizeOf(ownerTy: Type): Int64 {
    if (let Some(classTy) <- (ownerTy.StripAllRefs() as ClassType)) {
        let classDef = classTy.GetClassDef()
        if (classDef.IsInterface()) {
            return 0
        }
        if (IsCoreObjectDef(classDef)) {
            return 1
        }
        var count: Int64 = 2
        var current = classDef.GetSuperClassDef()
        while (let Some(def) <- current) {
            count++
            current = def.GetSuperClassDef()
        }
        return count
    }
    return 1
}

private func IsInterfaceOwnerType(ownerTy: Type): Bool {
    if (let Some(customTy) <- (ownerTy.StripAllRefs() as CustomType)) {
        return customTy.GetCustomTypeDef().IsInterface()
    }
    return false
}

private func GenerateResolvedStaticInvoke(irBuilder: IRBuilder2, dispatch: DynamicDispatch,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(thisTy) <- dispatch.GetThisType()) {
        if (let Some(callee) <- FindMethodByName(thisTy, dispatch.GetMethodName())) {
            return GenerateApply(irBuilder, callee, args, callType: Some(dispatch.GetMethodType()),
                isMethodType: false, isStaticMethodType: true, instTypeArgs: dispatch.GetInstantiatedTypeArgs())
        }
    }
    return LLVMNullValue()
}

private func GenerateResolvedStaticInvoke(irBuilder: IRBuilder2, dispatch: DynamicDispatchWithException,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(thisTy) <- dispatch.GetThisType()) {
        if (let Some(callee) <- FindMethodByName(thisTy, dispatch.GetMethodName())) {
            return GenerateApply(irBuilder, callee, args, callType: Some(dispatch.GetMethodType()),
                isMethodType: false, isStaticMethodType: true, instTypeArgs: dispatch.GetInstantiatedTypeArgs())
        }
    }
    return LLVMNullValue()
}

private func FindMethodByName(ownerTy: Type, methodName: String): Option<Function> {
    if (let Some(customTy) <- (ownerTy.StripAllRefs() as CustomType)) {
        return FindMethodByName(customTy.GetCustomTypeDef(), methodName)
    }
    return None
}

private func FindMethodByName(def: CustomTypeDef, methodName: String): Option<Function> {
    for (method in def.GetMethods()) {
        if (MethodNameMatches(method, methodName)) {
            return Some(method)
        }
    }
    if (let Some(classDef) <- (def as ClassDef)) {
        if (let Some(superDef) <- classDef.GetSuperClassDef()) {
            return FindMethodByName(superDef, methodName)
        }
    }
    return None
}

private func ResolveVirtualMethod(ownerTy: Type, methodName: String, callee: Function,
    virtualMethodOffset: Option<UInt64>): (Type, Int64) {
    if (let Some(offset) <- virtualMethodOffset) {
        return (ownerTy, Int64(offset))
    }
    if (let Some(resolved) <- ComputeVirtualMethod(ownerTy, methodName, callee)) {
        return resolved
    }
    throw IllegalStateException("virtual invoke has no vtable offset: " + methodName)
}

private func ComputeVirtualMethod(ownerTy: Type, methodName: String, callee: Function): Option<(Type, Int64)> {
    if (let Some(customTy) <- (ownerTy.StripAllRefs() as CustomType)) {
        if (let Some(classDef) <- (customTy.GetCustomTypeDef() as ClassDef)) {
            for (table in BuildClassVTables(classDef)) {
                var idx: Int64 = 0
                while (idx < table.slots.size) {
                    if (let Some(slotMethod) <- table.slots[idx]) {
                        if (VirtualSlotMatches(slotMethod, callee, methodName)) {
                            return Some((InstantiateIntroType(ownerTy, table.parentDef), idx))
                        }
                    }
                    idx++
                }
            }
        }
    }
    return None
}

private func InstantiateIntroType(ownerTy: Type, introDef: ClassDef): Type {
    if (let Some(ownerClassTy) <- (ownerTy.StripAllRefs() as ClassType)) {
        if (ownerClassTy.GetClassDef().nodeId == introDef.nodeId) {
            return ClassType(introDef, ownerClassTy.GetGenericArgs())
        }
    }
    return ClassType(introDef, ArrayList<Type>())
}

private func BuildClassVTables(def: ClassDef): ArrayList<ClassVTable> {
    let tables = ArrayList<ClassVTable>()
    if (!IsCoreObjectDef(def)) {
        if (let Some(superDef) <- def.GetSuperClassDef()) {
            for (table in BuildClassVTables(superDef)) {
                tables.add(table)
            }
        } else {
            tables.add(ClassVTable(CoreObjectClassDef(def), ArrayList<Option<Function>>()))
        }
    }
    for (method in def.GetMethods()) {
        if (!FuncMayBeInVTable(method)) {
            continue
        }
        if (let Some((table, slotIdx)) <- FindMatchingVirtualSlot(tables, method)) {
            table.slots[slotIdx] = Some(method)
        } else if (IsVirtualFunctionForVTable(method)) {
            let table = GetOrCreateClassVTable(tables, def)
            table.slots.add(Some(method))
        }
    }
    return tables
}

private func GetOrCreateClassVTable(tables: ArrayList<ClassVTable>, def: ClassDef): ClassVTable {
    for (table in tables) {
        if (table.parentDef.nodeId == def.nodeId) {
            return table
        }
    }
    let slots = ArrayList<Option<Function>>()
    let table = ClassVTable(def, slots)
    tables.add(table)
    return table
}

private func FindMatchingVirtualSlot(tables: ArrayList<ClassVTable>, method: Function): Option<(ClassVTable, Int64)> {
    for (table in tables) {
        var idx: Int64 = 0
        while (idx < table.slots.size) {
            if (let Some(slotMethod) <- table.slots[idx]) {
                if (VirtualMethodsHaveSameSlot(slotMethod, method)) {
                    return Some((table, idx))
                }
            }
            idx++
        }
    }
    return None
}

private func CoreObjectClassDef(def: ClassDef): ClassDef {
    var current = def
    while (let Some(superDef) <- current.GetSuperClassDef()) {
        current = superDef
    }
    return current
}

private func VirtualSlotMatches(slotMethod: Function, callee: Function, methodName: String): Bool {
    return (VirtualMethodsHaveSameSlot(slotMethod, callee) || MethodNameMatches(slotMethod, methodName)) &&
        VirtualFuncTypesMatch(slotMethod, callee)
}

private func VirtualMethodsHaveSameSlot(left: Function, right: Function): Bool {
    if (left.TestAttr(Attribute.STATIC) != right.TestAttr(Attribute.STATIC)) {
        return false
    }
    if (!MethodNameMatches(left, right.GetSrcCodeIdentifier()) &&
        !MethodNameMatches(left, right.GetIdentifierWithoutPrefix()) &&
        !MethodNameMatches(right, left.GetSrcCodeIdentifier()) &&
        !MethodNameMatches(right, left.GetIdentifierWithoutPrefix())) {
        return false
    }
    return VirtualFuncTypesMatch(left, right)
}

private func VirtualFuncTypesMatch(left: Function, right: Function): Bool {
    let leftTy = left.GetFuncType() ?? return true
    let rightTy = right.GetFuncType() ?? return true
    let leftParams = VirtualParamTypes(left, leftTy)
    let rightParams = VirtualParamTypes(right, rightTy)
    if (leftParams.size != rightParams.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < leftParams.size) {
        if (!leftParams[idx].IsGeneric() && !rightParams[idx].IsGeneric() && !leftParams[idx].IsEqual(rightParams[idx])) {
            return false
        }
        idx++
    }
    return true
}

private func VirtualParamTypes(fn: Function, funcTy: FuncType): ArrayList<Type> {
    let params = funcTy.GetParamTypes()
    if (!fn.TestAttr(Attribute.STATIC) && !params.isEmpty()) {
        params.remove(at: 0)
    }
    return params
}

private func FuncMayBeInVTable(fn: Function): Bool {
    if (fn.IsConstructor() || fn.IsFinalizer() || fn.GetFuncKind() == FuncKind.ANNOFACTORY_FUNC ||
        fn.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
        return false
    }
    return fn.TestAttr(Attribute.PUBLIC) || fn.TestAttr(Attribute.PROTECTED) ||
        (fn.TestAttr(Attribute.STATIC) && !fn.TestAttr(Attribute.PRIVATE))
}

private func IsVirtualFunctionForVTable(fn: Function): Bool {
    let parentDef = fn.GetParentCustomTypeDef() ?? return false
    let parentClass = (parentDef as ClassDef) ?? return false
    if (parentClass.IsInterface()) {
        return true
    }
    if (!parentClass.CanBeInherited()) {
        return false
    }
    if (fn.TestAttr(Attribute.STATIC)) {
        return true
    }
    if (fn.IsConstructor() || fn.IsFinalizer() || fn.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
        return false
    }
    if (!fn.TestAttr(Attribute.PUBLIC) && !fn.TestAttr(Attribute.PROTECTED)) {
        return false
    }
    return fn.TestAttr(Attribute.VIRTUAL) || fn.TestAttr(Attribute.ABSTRACT)
}

private func IsCoreObjectDef(def: CustomTypeDef): Bool {
    return def.GetPackageName() == "std.core" && def.GetSrcCodeIdentifier() == "Object"
}

private func MethodNameMatches(method: Function, methodName: String): Bool {
    return method.GetIdentifierWithoutPrefix() == methodName || method.GetSrcCodeIdentifier() == methodName ||
        method.GetRawMangledName() == methodName
}
