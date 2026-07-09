package cangjie_compiler::codegen

import std.collection.*
import std.sort.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.CHIRBuilder
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.ExtendDef
import cangjie_compiler::chir.GenericType
import cangjie_compiler::chir.ReplaceRawGenericArgType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.VirtualMethodInfo
import cangjie_compiler::chir.VTableInType
import cangjie_compiler::mangle.GetTypeQualifiedName
import cangjie_compiler::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG}

private let EXTENSION_DEFS_NAME: String = "NonExternalExtensionDefs"
private let EXTERNAL_EXTENSION_DEFS_NAME: String = "ExternalExtensionDefs"

public func GenerateInterfaceExtensionDefs(cgMod: CGModule): Unit {
    for (def in cgMod.GetCGContext().GetSubCHIRPackage().chirCustomDefs) {
        if (!ShouldCollectExtensionDef(cgMod, def)) {
            continue
        }
        CGExtensionDef(cgMod, def).Emit()
    }
    EmitNonExternalExtensionDefsTable(cgMod)
    EmitExternalExtensionDefsTable(cgMod)
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
    let _ = cgMod
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

private class InnerTiInfo {
    public let value: LLVMValueRef
    public let isTypeInfo: Bool

    public init(value: LLVMValueRef, isTypeInfo: Bool) {
        this.value = value
        this.isTypeInfo = isTypeInfo
    }
}

private class CGExtensionDef {
    private let cgMod: CGModule
    private let chirDef: CustomTypeDef
    private let targetType: Type
    private let isForExternalType: Bool
    private let typeMangle: String
    private var extendDefName: String = ""
    private var whereCondFn: LLVMValueRef = LLVMNullValue()
    private let genericParamsMap: HashMap<Int64, (IRBuilder2) -> LLVMValueRef> =
        HashMap<Int64, (IRBuilder2) -> LLVMValueRef>()
    private let innerTypeMap: HashMap<Int64, InnerTiInfo> = HashMap<Int64, InnerTiInfo>()
    private let gtAccessPathMap: HashMap<Int64, ArrayList<Int64>> = HashMap<Int64, ArrayList<Int64>>()
    private let generatedGenerics: HashMap<String, ArrayList<LLVMValueRef>> =
        HashMap<String, ArrayList<LLVMValueRef>>()
    private let extendInterfaces: ArrayList<MTableInterfaceInfo> = ArrayList<MTableInterfaceInfo>()

    public init(cgMod: CGModule, chirDef: CustomTypeDef) {
        this.cgMod = cgMod
        this.chirDef = chirDef
        targetType = RequireExtensionTargetType(chirDef)
        isForExternalType = IsExternalDefinedType(targetType)
        typeMangle = GetTypeQualifiedName(targetType)
    }

    public func Emit(): (Int64, ArrayList<MTableInterfaceInfo>) {
        var extensionDefsNum: Int64 = 0
        if (!chirDef.TestAttr(Attribute.IMPORTED) && !chirDef.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            CollectGenericParamIndicesMap()
            let orderedInheritedTypes = ArrayList<ClassType>()
            if (let Some(classDef) <- (chirDef as ClassDef)) {
                orderedInheritedTypes.add(RequireClassType(classDef))
            }
            GetOrderedParentTypesRecusively(chirDef, orderedInheritedTypes, cgMod.GetCGContext().GetCHIRBuilder())
            for (inheritedType in orderedInheritedTypes) {
                if (inheritedType.IsAny()) {
                    continue
                }
                if (CreateExtensionDefForType(inheritedType)) {
                    extensionDefsNum++
                    if (inheritedType.GetClassDef().IsInterface()) {
                        extendInterfaces.add(MTableInterfaceInfo(inheritedType,
                            if (chirDef.IsExtend()) { Some(targetType) } else { None }))
                    }
                }
            }
        }
        for (extendDef in chirDef.GetExtends()) {
            let rst = CGExtensionDef(cgMod, extendDef).Emit()
            extensionDefsNum += rst[0]
            for (interfaceInfo in rst[1]) {
                extendInterfaces.add(interfaceInfo)
            }
        }
        if (!isForExternalType && extensionDefsNum != 0) {
            let totalExtensionDefsNum = cgMod.GetNonExternalExtensionDefsNum()
            CJC_ASSERT(totalExtensionDefsNum >= extensionDefsNum)
            let startIdxOfNonExternalExtensionDef = totalExtensionDefsNum - extensionDefsNum
            let targetDefType = if (targetType.IsNominal()) {
                (targetType as CustomType).getOrThrow().GetCustomTypeDef().GetType().getOrThrow()
            } else {
                targetType
            }
            cgMod.RegisterExtensionDefStart(targetDefType, startIdxOfNonExternalExtensionDef)
            cgMod.RegisterExtensionDefInterfaces(targetDefType, extendInterfaces)
            if (let Some(customTy) <- (targetDefType as CustomType)) {
                RefreshSourceGenericTypeTemplateInitializer(cgMod, customTy)
            }
        }
        return (extensionDefsNum, extendInterfaces)
    }

    private func CreateExtensionDefForType(inheritedType: ClassType): Bool {
        let vTable = chirDef.GetDefVTable().GetExpectedTypeVTable(inheritedType)
        let funcTableSize = if (vTable.IsEmpty()) { 0 } else { vTable.GetMethodNum() }
        if (funcTableSize == 0 && inheritedType.GetClassDef().IsInterface() &&
            inheritedType.objectId == targetType.objectId) {
            return false
        }
        extendDefName = typeMangle + "_ed_" + GetTypeQualifiedName(inheritedType)
        let content = GetEmptyExtensionDefContent(cgMod, targetType)
        let iFn = GenerateInterfaceFn(inheritedType)
        content[5] = iFn[0]
        content[1] = unsafe {
            LLVMConstInt(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), if (iFn[1]) { 1u64 } else { 0u64 }, 0)
        }
        content[2] = unsafe {
            LLVMConstInt(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw),
                ExtensionDefFlag(targetType, inheritedType,
                    IsDirectSuperTypeOf(inheritedType, targetType, cgMod.GetCGContext().GetCHIRBuilder())), 0)
        }
        content[6] = GenerateWhereConditionFn()
        content[7] = GenerateFuncTableForType(inheritedType, vTable)
        content[3] = unsafe {
            LLVMConstInt(LLVMInt16TypeInContext(cgMod.GetLLVMContext().raw), UInt64(funcTableSize), 0)
        }
        return CreateExtensionDefForType(cgMod, extendDefName, content, inheritedType, isForExternalType)
    }

    private func GenerateInterfaceFn(inheritedType: ClassType): (LLVMValueRef, Bool) {
        CJC_ASSERT(!inheritedType.IsGeneric())
        let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
        if (!CGType.GetOrCreate(cgMod, inheritedType).IsDynamicGI()) {
            return (TypeInfoAsI8Ptr(cgMod, inheritedType, i8PtrTy), true)
        }
        let context = cgMod.GetLLVMContext().raw
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
        let params = ArrayList<LLVMTypeRef>()
        params.add(unsafe { LLVMInt32TypeInContext(context) })
        params.add(unsafe { LLVMPointerType(typeInfoPtrType, 0u32) })
        let fnType = BuildLLVMFunctionType(i8PtrTy, params)
        let fnName = extendDefName + "_iFn"
        let fn = cgMod.GetOrInsertFunction(fnName, fnType)
        if (unsafe { LLVMIsDeclaration(fn) } != 0) {
            unsafe { LLVMSetLinkage(fn, LLVMLinkageValue(LLVMLinkage.Private)) }
            AddFnAttr(fn, "native-interface-fn")
            unsafe { LLVMSetUnnamedAddress(fn, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr)) }
            let entry = IRBuilder2(cgMod)
            let block = entry.CreateEntryBasicBlock(fn, "entry")
            entry.SetInsertPoint(block)
            innerTypeMap[targetType.objectId] = InnerTiInfo(unsafe { LLVMGetParam(fn, 1u32) }, false)
            let ti = entry.CreateTypeInfo(inheritedType.StripAllRefs(), genericParamsMap, canChangeBB: false)
            innerTypeMap.clear()
            entry.CreateRet(entry.CreateBitCast(ti, i8PtrTy))
            entry.close()
        }
        return (unsafe { LLVMConstBitCast(fn, i8PtrTy) }, false)
    }

    private func GenerateWhereConditionFn(): LLVMValueRef {
        if (!whereCondFn.isNull()) {
            return whereCondFn
        }
        let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
        if (!CGType.GetOrCreate(cgMod, targetType).IsDynamicGI() || !NeedGenerateFnForGenericType()) {
            return unsafe { LLVMConstNull(i8PtrTy) }
        }
        let context = cgMod.GetLLVMContext().raw
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
        let params = ArrayList<LLVMTypeRef>()
        params.add(unsafe { LLVMInt32TypeInContext(context) })
        params.add(unsafe { LLVMPointerType(typeInfoPtrType, 0u32) })
        let fnType = BuildLLVMFunctionType(unsafe { LLVMInt1TypeInContext(context) }, params)
        let fnName = extendDefName + "_cs"
        let fn = cgMod.GetOrInsertFunction(fnName, fnType)
        if (unsafe { LLVMIsDeclaration(fn) } != 0) {
            unsafe { LLVMSetLinkage(fn, LLVMLinkageValue(LLVMLinkage.Private)) }
            AddFnAttr(fn, "native-interface-fn")
            unsafe { LLVMSetUnnamedAddress(fn, LLVMUnnamedAddrValue(LLVMUnnamedAddr.GlobalUnnamedAddr)) }
            let entry = IRBuilder2(cgMod)
            let block = entry.CreateEntryBasicBlock(fn, "entry")
            entry.SetInsertPoint(block)
            let typeInfos = unsafe { LLVMGetParam(fn, 1u32) }
            innerTypeMap[targetType.objectId] = InnerTiInfo(typeInfos, false)
            var retVal = CreateCompareArgs(entry, typeInfos, targetType.GetTypeArgs(), prefix: "")
            retVal = CheckGenericParams(entry, retVal)
            entry.CreateRet(retVal)
            innerTypeMap.clear()
            entry.close()
        }
        whereCondFn = unsafe { LLVMConstBitCast(fn, i8PtrTy) }
        return whereCondFn
    }

    private func NeedGenerateFnForGenericType(): Bool {
        let genericTypes = ArrayList<Type>()
        for (gt in chirDef.GetGenericTypeParams()) {
            if (!gt.GetUpperBounds().isEmpty()) {
                return true
            }
            genericTypes.add(gt)
        }
        var isAllTypeArgsGeneric = true
        for (typeArg in targetType.GetTypeArgs()) {
            if (!typeArg.IsGeneric()) {
                isAllTypeArgsGeneric = false
                break
            }
        }
        return !isAllTypeArgsGeneric && chirDef.IsExtend() &&
            !IsSameTypeArgs(genericTypes, targetType.GetTypeArgs())
    }

    private func CreateTypeComparison(irBuilder: IRBuilder2, typeInfo: LLVMValueRef, staticType: Type,
        prefix: String): LLVMValueRef {
        let derefType = DeRef(staticType)
        let cgType = CGType.GetOrCreate(cgMod, derefType)
        if (cgType.IsConcrete()) {
            return irBuilder.CreateICmp(LLVMIntPredicate.EQ, typeInfo, cgType.GetOrCreateTypeInfo())
        }
        if (cgType.IsStaticGI()) {
            return irBuilder.CallIntrinsicIsTypeEqualTo(ArrayList<LLVMValueRef>([typeInfo, cgType.GetOrCreateTypeInfo()]))
        }
        if (staticType.IsGeneric()) {
            let gt = (staticType as GenericType).getOrThrow()
            let gtName = gt.ToString()
            if (!generatedGenerics.contains(gtName)) {
                generatedGenerics[gtName] = ArrayList<LLVMValueRef>()
            }
            generatedGenerics[gtName].add(typeInfo)
            let fixedUppers = ArrayList<Type>()
            for (upper in gt.GetUpperBounds()) {
                let upperDerefType = DeRef(upper)
                if (!upperDerefType.IsCType()) {
                    fixedUppers.add(upperDerefType)
                }
            }
            if (fixedUppers.isEmpty()) {
                return irBuilder.GetTrue()
            }
            var res = LLVMNullValue()
            var idx: Int64 = 0
            while (idx < fixedUppers.size) {
                if (idx != 0) {
                    HandleShortcutBranch(irBuilder, res, prefix + "_cs_" + idx.toString())
                }
                let upperBoundTypeInfo = irBuilder.CreateTypeInfo(fixedUppers[idx], genericParamsMap, canChangeBB: false)
                res = irBuilder.CallIntrinsicIsSubtype(ArrayList<LLVMValueRef>([typeInfo, upperBoundTypeInfo]))
                idx++
            }
            return res
        }
        let typeInfoType = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
        let realTypeTemplatePtr = irBuilder.CreateStructGEP(typeInfoType, typeInfo, 11u32)
        let realTypeTemplate = irBuilder.CreateLoad(i8PtrType, realTypeTemplatePtr, name: prefix + "_tt")
        let typeCmp = irBuilder.CreateICmp(LLVMIntPredicate.EQ, realTypeTemplate, GetTargetType(cgMod, derefType))
        HandleShortcutBranch(irBuilder, typeCmp, prefix + "_tt")
        let backupBB = irBuilder.GetInsertBlock()
        irBuilder.SetInsertPointForPreparingTypeInfo()
        let typeInfosPtr = irBuilder.CreateStructGEP(typeInfoType, typeInfo, 12u32)
        let typeInfosRaw = irBuilder.CreateLoad(i8PtrType, typeInfosPtr)
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
        let typeInfos = irBuilder.CreateBitCast(typeInfosRaw, unsafe { LLVMPointerType(typeInfoPtrType, 0u32) })
        irBuilder.SetInsertPoint(backupBB)
        return CreateCompareArgs(irBuilder, typeInfos, derefType.GetTypeArgs(), prefix: prefix)
    }

    private func CreateCompareArgs(irBuilder: IRBuilder2, typeInfos: LLVMValueRef, typeArgs: ArrayList<Type>,
        prefix!: String = ""): LLVMValueRef {
        CJC_ASSERT(!typeArgs.isEmpty())
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
        var retVal = LLVMNullValue()
        var idx: Int64 = 0
        while (idx < typeArgs.size) {
            let backupBB = irBuilder.GetInsertBlock()
            irBuilder.SetInsertPointForPreparingTypeInfo()
            let tiPtr = irBuilder.CreateConstGEP1_32(typeInfoPtrType, typeInfos, UInt32(idx))
            let ti = irBuilder.CreateLoad(typeInfoPtrType, tiPtr, name: idx.toString() + "ti")
            let chirType = typeArgs[idx]
            innerTypeMap[chirType.objectId] = InnerTiInfo(ti, true)
            irBuilder.SetInsertPoint(backupBB)
            let idxStr = prefix + "_" + idx.toString()
            if (idx == 0) {
                retVal = CreateTypeComparison(irBuilder, ti, chirType, idxStr)
            } else {
                HandleShortcutBranch(irBuilder, retVal, idxStr)
                retVal = CreateTypeComparison(irBuilder, ti, chirType, idxStr)
            }
            idx++
        }
        return retVal
    }

    private func CheckGenericParams(irBuilder: IRBuilder2, retVal: LLVMValueRef): LLVMValueRef {
        let removedKeys = ArrayList<String>()
        for ((key, values) in generatedGenerics) {
            if (values.size <= 1) {
                removedKeys.add(key)
            }
        }
        for (key in removedKeys) {
            generatedGenerics.remove(key)
        }
        if (generatedGenerics.isEmpty()) {
            return retVal
        }
        let keys = ArrayList<String>()
        for (key in generatedGenerics.keys()) {
            keys.add(key)
        }
        sort(keys, by: { left: String, right: String =>
            if (left < right) {
                Ordering.LT
            } else if (left > right) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        var newRet = retVal
        for (key in keys) {
            let values = generatedGenerics[key]
            CJC_ASSERT(!values.isEmpty())
            var idx: Int64 = 0
            while (idx + 1 < values.size) {
                HandleShortcutBranch(irBuilder, newRet, "type_cs")
                newRet = irBuilder.CallIntrinsicIsTypeEqualTo(ArrayList<LLVMValueRef>([values[idx], values[idx + 1]]))
                idx++
            }
        }
        CJC_ASSERT(newRet.toUIntNative() != retVal.toUIntNative())
        return newRet
    }

    private func FoundGenericTypeAndCollectPath(srcType: Type, gt: GenericType, path: ArrayList<Int64>): Bool {
        if (srcType.objectId == gt.objectId) {
            return true
        }
        let typeArgs = DeRef(srcType).GetTypeArgs()
        var idx: Int64 = 0
        while (idx < typeArgs.size) {
            path.add(idx)
            if (FoundGenericTypeAndCollectPath(typeArgs[idx], gt, path)) {
                return true
            }
            path.remove(at: path.size - 1)
            idx++
        }
        return false
    }

    private func GetTypeInfoWithPath(irBuilder: IRBuilder2, chirTy: Type, entryTypeArgs: LLVMValueRef,
        remainPath: ArrayList<Int64>, innerTypeMap: HashMap<Int64, InnerTiInfo>): LLVMValueRef {
        let typeInfoType = CGType.GetOrCreateTypeInfoType(irBuilder.GetLLVMContext())
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
        var curType = chirTy
        var typeArgs = entryTypeArgs
        var pathIdx: Int64 = 0
        while (pathIdx < remainPath.size) {
            let idx = remainPath[pathIdx]
            let backupBB = irBuilder.GetInsertBlock()
            let backupIt = unsafe { LLVMSelfhostGetInsertPointInstruction(irBuilder.GetBuilder().raw) }
            irBuilder.SetInsertPointForPreparingTypeInfo()
            let indices = ArrayList<LLVMValueRef>()
            indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(idx), 0) })
            let curTiPtr = irBuilder.CreateGEP(typeInfoPtrType, typeArgs, indices)
            let curTi = irBuilder.CreateLoad(typeInfoPtrType, curTiPtr)
            curType = DeRef(curType).GetTypeArgs()[idx]
            innerTypeMap[curType.objectId] = InnerTiInfo(curTi, true)
            irBuilder.SetInsertPoint(backupBB, backupIt)
            if (pathIdx + 1 < remainPath.size) {
                let typeInfosPtr = irBuilder.CreateStructGEP(typeInfoType, curTi, 12u32)
                let typeInfosRaw = irBuilder.CreateLoad(i8PtrType, typeInfosPtr)
                typeArgs = irBuilder.CreateBitCast(typeInfosRaw, unsafe { LLVMPointerType(typeInfoPtrType, 0u32) })
            }
            pathIdx++
        }
        return innerTypeMap[curType.objectId].value
    }

    private func GetTypeInfoOfGeneric(irBuilder: IRBuilder2, gt: GenericType): LLVMValueRef {
        let accessPath = gtAccessPathMap[gt.objectId]
        let candidateTypes = ArrayList<Type>()
        let candidateStarts = ArrayList<Int64>()
        var currentType = targetType
        candidateTypes.add(currentType)
        candidateStarts.add(0)
        var pathIdx: Int64 = 0
        while (pathIdx < accessPath.size) {
            let argType = DeRef(currentType).GetTypeArgs()[accessPath[pathIdx]]
            candidateTypes.add(argType)
            candidateStarts.add(pathIdx + 1)
            currentType = DeRef(argType)
            pathIdx++
        }
        var candidateIdx = candidateTypes.size - 1
        while (candidateIdx >= 0) {
            let typeArg = candidateTypes[candidateIdx]
            if (innerTypeMap.contains(typeArg.objectId)) {
                let found = innerTypeMap[typeArg.objectId]
                let typeArgs = if (found.isTypeInfo) {
                    irBuilder.GetTypeArgsFromTypeInfo(found.value)
                } else {
                    found.value
                }
                let remainPath = ArrayList<Int64>()
                var remainIdx = candidateStarts[candidateIdx]
                while (remainIdx < accessPath.size) {
                    remainPath.add(accessPath[remainIdx])
                    remainIdx++
                }
                return GetTypeInfoWithPath(irBuilder, typeArg, typeArgs, remainPath, innerTypeMap)
            }
            candidateIdx--
        }
        throw IllegalStateException("failed to load generic type info for extended type: " + targetType.ToString())
    }

    private func CollectGenericParamIndicesMap(): Unit {
        for (gt in chirDef.GetGenericTypeParams()) {
            let path = ArrayList<Int64>()
            if (!FoundGenericTypeAndCollectPath(targetType, gt, path)) {
                throw IllegalStateException("generic type of extend def is not found in target type")
            }
            gtAccessPathMap[gt.objectId] = path
        }
        for (gt2 in chirDef.GetGenericTypeParams()) {
            genericParamsMap[gt2.objectId] = { irBuilder: IRBuilder2 => GetTypeInfoOfGeneric(irBuilder, gt2) }
        }
    }

    private func GenerateOuterTi(funcInfo: VirtualMethodInfo): LLVMValueRef {
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
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

    private func GenerateOuterTiFn(funcInfo: VirtualMethodInfo): LLVMValueRef {
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
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
            innerTypeMap[targetType.objectId] = InnerTiInfo(unsafe { LLVMGetParam(fn, 0u32) }, true)
            let outerTi = entry.CreateTypeInfo(funcInfo.GetInstParentType().StripAllRefs(), genericParamsMap,
                canChangeBB: false)
            innerTypeMap.clear()
            entry.CreateRet(entry.CreateBitCast(outerTi, typeInfoPtrType))
            entry.close()
        } else {
            CJC_ASSERT_WITH_MSG(false,
                "GenerateOuterTiFn should not be called multiple times for the same function. Something is wrong.")
        }
        return unsafe { LLVMConstBitCast(fn, i8PtrType) }
    }

    private func GenerateFuncTableForType(inheritedType: ClassType, vTable: VTableInType): LLVMValueRef {
        let _ = inheritedType
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
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
                    values.add(unsafe {
                        LLVMConstBitCast(cgMod.GetOrInsertCGFunction(method).GetRawFunction(), i8PtrType)
                    })
                } else {
                    values.add(unsafe { LLVMConstNull(i8PtrType) })
                }
            }
            for (funcInfo2 in virtualMethods) {
                values.add(if (targetType.GetTypeArgs().isEmpty()) {
                    GenerateOuterTi(funcInfo2)
                } else {
                    GenerateOuterTiFn(funcInfo2)
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
}

private func HandleShortcutBranch(irBuilder: IRBuilder2, condition: LLVMValueRef, prefix: String): Unit {
    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>(
        [GenNameForBB(prefix + "_true"), GenNameForBB(prefix + "_false")]))
    CJC_ASSERT(blocks.size == 2)
    irBuilder.CreateCondBr(condition, blocks[0], blocks[1])
    irBuilder.SetInsertPoint(blocks[1])
    irBuilder.CreateRet(irBuilder.GetFalse())
    irBuilder.SetInsertPoint(blocks[0])
}

private func GetTargetType(cgMod: CGModule, chirTy: Type): LLVMValueRef {
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
    let cgType = CGType.GetOrCreate(cgMod, chirTy)
    let res = if (cgType.IsDynamicGI()) {
        if (let Some(customTy) <- (chirTy as CustomType)) {
            CGType.GetOrCreate(cgMod, customTy.GetCustomTypeDef().GetType().getOrThrow()).GetOrCreateTypeTemplate()
        } else {
            cgType.GetOrCreateTypeTemplate()
        }
    } else {
        cgType.GetOrCreateTypeInfo()
    }
    return unsafe { LLVMConstBitCast(res, i8PtrType) }
}

private func GetEmptyExtensionDefContent(cgMod: CGModule, targetType: Type): ArrayList<LLVMValueRef> {
    let context = cgMod.GetLLVMContext().raw
    let i8Type = unsafe { LLVMInt8TypeInContext(context) }
    let i16Type = unsafe { LLVMInt16TypeInContext(context) }
    let i32Type = unsafe { LLVMInt32TypeInContext(context) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let defConstants = ArrayList<LLVMValueRef>()
    defConstants.add(unsafe {
        LLVMConstInt(i32Type,
            if (CGType.GetOrCreate(cgMod, targetType).IsDynamicGI()) { UInt64(targetType.GetTypeArgs().size) } else { 0u64 },
            0)
    })
    defConstants.add(unsafe { LLVMConstNull(i8Type) })
    defConstants.add(unsafe { LLVMConstNull(i8Type) })
    defConstants.add(unsafe { LLVMConstNull(i16Type) })
    defConstants.add(GetTargetType(cgMod, targetType))
    defConstants.add(unsafe { LLVMConstNull(i8PtrType) })
    defConstants.add(unsafe { LLVMConstNull(i8PtrType) })
    defConstants.add(unsafe { LLVMConstNull(i8PtrType) })
    return defConstants
}

private func CreateExtensionDefForType(cgMod: CGModule, extensionDefName: String,
    content: ArrayList<LLVMValueRef>, inheritedType: ClassType, isForExternalType: Bool): Bool {
    let extensionDefType = CGType.GetOrCreateExtensionDefType(cgMod.GetLLVMContext())
    let extensionDef = GetOrInsertCodeGenGlobal(cgMod, extensionDefName, extensionDefType)
    CJC_ASSERT(!extensionDef.isNull())
    if (unsafe { LLVMIsDeclaration(extensionDef) } == 0) {
        return false
    }
    unsafe {
        LLVMSetInitializer(extensionDef, ConstNamedStruct(extensionDefType, content))
        LLVMSetLinkage(extensionDef, LLVMLinkageValue(LLVMLinkage.Private))
    }
    addAttribute(extensionDef, GC_MTABLE_ATTR)
    let typeArgs = inheritedType.GetTypeArgs()
    if (typeArgs.size == 1) {
        LLVMSetGlobalMetadata(cgMod.GetLLVMContext(), extensionDef, "inheritedType",
            LLVMCreateMDTuple(cgMod.GetLLVMContext(), UnwindGenericRelateType(cgMod.GetLLVMContext(), inheritedType)))
    } else if (typeArgs.isEmpty()) {
        LLVMSetGlobalStringMetadata(cgMod.GetLLVMContext(), extensionDef, "inheritedType",
            CGType.GetNameOfTypeInfoGV(inheritedType))
    }
    if (isForExternalType) {
        cgMod.AddExternalExtensionDef(extensionDef)
    } else {
        cgMod.AddNonExternalExtensionDef(extensionDef)
    }
    return true
}

private func GetOrderedParentTypesRecusively(classType: ClassType, parents: ArrayList<ClassType>,
    builder: CHIRBuilder): Unit {
    if (let Some(superClass) <- classType.GetSuperClassTy(builder: builder)) {
        let copied = parents.clone()
        parents.clear()
        parents.add(superClass)
        for (parent in copied) {
            parents.add(parent)
        }
        GetOrderedParentTypesRecusively(superClass, parents, builder)
    }
    let classDef = classType.GetClassDef()
    let res = classDef.GetType().getOrThrow().CalculateGenericTyMapping(classType)
    CJC_ASSERT(res[0])
    for (interfaceTy in classDef.GetImplementedInterfaceTys()) {
        let instType = (ReplaceRawGenericArgType(interfaceTy, res[1], builder) as ClassType).getOrThrow()
        var found = false
        for (parentType in parents) {
            if (parentType.objectId == instType.objectId) {
                found = true
                break
            }
        }
        if (found) {
            continue
        }
        parents.add(instType)
        GetOrderedParentTypesRecusively(instType, parents, builder)
    }
}

private func GetOrderedParentTypesRecusively(def: CustomTypeDef, parents: ArrayList<ClassType>,
    builder: CHIRBuilder): Unit {
    if (let Some(classDef) <- (def as ClassDef)) {
        if (let Some(superClass) <- classDef.GetSuperClassTy()) {
            let copied = parents.clone()
            parents.clear()
            parents.add(superClass)
            for (parent in copied) {
                parents.add(parent)
            }
            GetOrderedParentTypesRecusively(superClass, parents, builder)
        }
    }
    for (interfaceTy in def.GetImplementedInterfaceTys()) {
        var found = false
        for (parentType in parents) {
            if (parentType.objectId == interfaceTy.objectId) {
                found = true
                break
            }
        }
        if (found) {
            continue
        }
        parents.add(interfaceTy)
        if (def.TestAttr(Attribute.COMPILER_ADD) && def.IsExtend()) {
            continue
        }
        GetOrderedParentTypesRecusively(interfaceTy, parents, builder)
    }
}

private func IsSameTypeArgs(left: ArrayList<Type>, right: ArrayList<Type>): Bool {
    if (left.size != right.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < left.size) {
        if (left[idx].objectId != right[idx].objectId) {
            return false
        }
        idx++
    }
    return true
}

private func IsDirectSuperTypeOf(inheritedType: ClassType, targetType: Type, builder: CHIRBuilder): Bool {
    if (let Some(classTy) <- (targetType.StripAllRefs() as ClassType)) {
        if (let Some(superTy) <- classTy.GetSuperClassTy(builder: builder)) {
            if (superTy.GetClassDef().nodeId == inheritedType.GetClassDef().nodeId) {
                return true
            }
        }
        for (interfaceTy in classTy.GetClassDef().GetImplementedInterfaceTys()) {
            if (interfaceTy.GetClassDef().nodeId == inheritedType.GetClassDef().nodeId) {
                return true
            }
        }
        return false
    }
    if (let Some(customTy) <- (targetType.StripAllRefs() as CustomType)) {
        for (interfaceTy in customTy.GetCustomTypeDef().GetImplementedInterfaceTys()) {
            if (interfaceTy.GetClassDef().nodeId == inheritedType.GetClassDef().nodeId) {
                return true
            }
        }
    }
    return false
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

private func IsCoreObjectDef(def: CustomTypeDef): Bool {
    return def.GetPackageName() == "std.core" && def.GetSrcCodeIdentifier() == "Object"
}

private func SentinelI8Ptr(cgMod: CGModule, i8PtrType: LLVMTypeRef): LLVMValueRef {
    let i64Type = unsafe { LLVMInt64TypeInContext(cgMod.GetLLVMContext().raw) }
    return unsafe { LLVMConstIntToPtr(LLVMConstInt(i64Type, 1u64, 0), i8PtrType) }
}

private func TypeInfoAsI8Ptr(cgMod: CGModule, ty: Type, i8PtrType: LLVMTypeRef): LLVMValueRef {
    return unsafe { LLVMConstBitCast(CGType.GetOrCreate(cgMod, ty.StripAllRefs()).GetOrCreateTypeInfo(), i8PtrType) }
}

private func RequireClassType(def: ClassDef): ClassType {
    if (let Some(ty) <- def.GetType()) {
        if (let Some(classTy) <- (ty as ClassType)) {
            return classTy
        }
    }
    throw IllegalStateException("class-like def has no class type: " + def.GetIdentifier())
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
    addAttribute(table, "InnerTypeExtensions")
    cgMod.GetCGContext().AddLLVMUsedVars(EXTENSION_DEFS_NAME)
}

private func EmitExternalExtensionDefsTable(cgMod: CGModule): Unit {
    let defs = cgMod.GetExternalExtensionDefs()
    if (defs.isEmpty()) {
        return
    }
    let extensionDefPtrType = CGType.GetOrCreateExtensionDefPtrType(cgMod.GetLLVMContext())
    let values = ArrayList<LLVMValueRef>()
    for (def in defs) {
        values.add(def)
    }
    let arrayType = unsafe { LLVMArrayType(extensionDefPtrType, UInt32(values.size)) }
    let table = GetOrInsertCodeGenGlobal(cgMod, EXTERNAL_EXTENSION_DEFS_NAME, arrayType)
    unsafe {
        LLVMSetInitializer(table, ConstArray(extensionDefPtrType, values))
        LLVMSetLinkage(table, LLVMLinkageValue(LLVMLinkage.Private))
        LLVMSetGlobalConstant(table, 0)
    }
    addAttribute(table, "OuterTypeExtensions")
    cgMod.GetCGContext().AddLLVMUsedVars(EXTERNAL_EXTENSION_DEFS_NAME)
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
