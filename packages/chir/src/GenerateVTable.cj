package cangjie_compiler::chir

import std.collection.*
import std.sort.*
import cangjie_compiler::basic.Linkage as BasicLinkage
import cangjie_compiler::incremental_compilation.{CompilationCache, IncreKind, VirtualWrapperDepMap}
import cangjie_compiler::option.{GlobalOptions, OSType}
import cangjie_compiler::utils.{CJC_ASSERT, CJC_ABORT, OverflowStrategy, ProfileRecorder, TaskQueue}

private let OVERFLOW_OPERATOR_NAMES: Array<String> = ["+", "-", "*", "/"]
private let SPLIT_OPERATOR_NAME_PREFIX: Array<String> = ["&", "~", "%"]
private let OVF_STRATEGIES: Array<OverflowStrategy> =
    [OverflowStrategy.WRAPPING, OverflowStrategy.THROWING, OverflowStrategy.SATURATING]

public func IsVirtualFunction(funcDecl: Function): Bool {
    let parent = funcDecl.GetParentCustomTypeDef() ?? return false
    let parentClass = (parent as ClassDef) ?? return false
    if (parentClass.IsInterface()) {
        return true
    }
    if (!parentClass.CanBeInherited()) {
        return false
    }
    if (funcDecl.TestAttr(Attribute.STATIC)) {
        return true
    }
    if (funcDecl.GetFuncKind() == FuncKind.CLASS_CONSTRUCTOR || funcDecl.GetFuncKind() == FuncKind.FINALIZER) {
        return false
    }
    if (funcDecl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
        return false
    }
    if (!funcDecl.TestAttr(Attribute.PUBLIC) && !funcDecl.TestAttr(Attribute.PROTECTED)) {
        return false
    }
    return funcDecl.TestAttr(Attribute.VIRTUAL) || funcDecl.TestAttr(Attribute.ABSTRACT) ||
        funcDecl.TestAttr(Attribute.OVERRIDE)
}

private func HasGenericInNonFuncScope(ty: Type): Bool {
    let hasGenericInNonFuncScope = ArrayList<Bool>()
    hasGenericInNonFuncScope.add(false)
    ty.VisitTypeRecursively({ current: Type =>
        if (current.IsFunc()) {
            return false
        }
        if (current.IsGeneric()) {
            hasGenericInNonFuncScope[0] = true
        }
        return true
    })
    return hasGenericInNonFuncScope[0]
}

private func TypeCastIfNeeded(value: Value, expectedTy: Type, builder: CHIRBuilder, parentBlock: Block,
    needCheck!: Bool = true): Value {
    let valueTy = value.GetType() ?? return value
    if (valueTy.IsNothing()) {
        return value
    }
    if (!valueTy.IsEqual(expectedTy)) {
        var tmpValue = value
        if (valueTy.StripAllRefs().IsGeneric() && valueTy.IsRef()) {
            let load = builder.CreateLoad(valueTy.StripAllRefs(), value, parentBlock)
            tmpValue = load.GetResult().getOrThrow()
        }
        let ret = builder.CreateTypeCast(expectedTy, tmpValue, parentBlock)
        let _ = needCheck
        return ret.GetResult().getOrThrow()
    }
    return value
}

private func TransformGenericIfNeeded(value: Value, expectedTy: Type, builder: CHIRBuilder, parentBlock: Block,
    needCheck!: Bool = true): Option<Value> {
    let valueTy = value.GetType() ?? return None
    if (valueTy.IsEnum() && (expectedTy.IsTuple() || expectedTy.IsUnsignedInteger())) {
        return None
    }
    if ((valueTy.IsTuple() || valueTy.IsUnsignedInteger()) && expectedTy.IsEnum()) {
        return None
    }
    if (valueTy.IsStructArray() && expectedTy.IsStructArray()) {
        return None
    }
    if (HasGenericInNonFuncScope(expectedTy) && !HasGenericInNonFuncScope(valueTy)) {
        let ret = builder.CreateTransformToGeneric(expectedTy, value, parentBlock)
        let _ = needCheck
        return ret.GetResult().getOrThrow()
    } else if (HasGenericInNonFuncScope(valueTy) && !HasGenericInNonFuncScope(expectedTy)) {
        let ret = builder.CreateTransformToConcrete(expectedTy, value, parentBlock)
        let _ = needCheck
        return ret.GetResult().getOrThrow()
    }
    return None
}

private func LeftTypeIsBoxOfRightType(left: Type, right: Type): Bool {
    if (!left.IsRef()) {
        return false
    }
    let refTy = (left as RefType).getOrThrow()
    let boxType = (refTy.GetBaseType() as BoxType) ?? return false
    return right.IsEqual(boxType.GetBaseType())
}

private func BoxIfNeeded(value: Value, expectedTy: Type, builder: CHIRBuilder, parentBlock: Block,
    needCheck!: Bool = true): Option<Value> {
    let srcTy = value.GetType() ?? return None
    var srcIsValueTy = srcTy.IsValueType()
    if (let Some(refTy) <- (srcTy as RefType)) {
        CJC_ASSERT(!refTy.GetBaseType().IsRef())
        srcIsValueTy = refTy.GetBaseType().IsValueType()
    }
    let srcIsReferenceTy = srcTy.IsRef() && (srcTy as RefType).getOrThrow().GetBaseType().IsReferenceType()

    var dstIsValueTy = expectedTy.IsValueType()
    if (let Some(refTy) <- (expectedTy as RefType)) {
        CJC_ASSERT(!refTy.GetBaseType().IsRef())
        dstIsValueTy = refTy.GetBaseType().IsValueType()
    }
    let dstIsReferenceTy = expectedTy.IsRef() && (expectedTy as RefType).getOrThrow().GetBaseType().IsReferenceType()
    if (srcIsValueTy && dstIsReferenceTy) {
        var boxSrcVal = value
        if (srcTy.IsRef()) {
            let loadSrc = builder.CreateLoad((srcTy as RefType).getOrThrow().GetBaseType(), boxSrcVal, parentBlock)
            boxSrcVal = loadSrc.GetResult().getOrThrow()
        }
        let ret = builder.CreateBox(expectedTy, boxSrcVal, parentBlock)
        let _ = needCheck
        return ret.GetResult().getOrThrow()
    } else if (srcIsReferenceTy && dstIsValueTy) {
        if (expectedTy.IsRef()) {
            let ret = builder.CreateUnBoxToRef(expectedTy, value, parentBlock)
            let _ = needCheck
            return ret.GetResult().getOrThrow()
        } else {
            let ret = builder.CreateUnBox(expectedTy, value, parentBlock)
            let _ = needCheck
            return ret.GetResult().getOrThrow()
        }
    } else if (LeftTypeIsBoxOfRightType(srcTy, expectedTy)) {
        let ret = builder.CreateUnBox(expectedTy, value, parentBlock)
        let _ = needCheck
        return ret.GetResult().getOrThrow()
    } else if (LeftTypeIsBoxOfRightType(expectedTy, srcTy)) {
        let ret = builder.CreateBox(expectedTy, value, parentBlock)
        let _ = needCheck
        return ret.GetResult().getOrThrow()
    }
    return None
}

public func TypeCastOrBoxIfNeeded(value: Value, expectedTy: Type, builder: CHIRBuilder, parentBlock: Block,
    needCheck!: Bool = true): Value {
    if (let Some(ret) <- BoxIfNeeded(value, expectedTy, builder, parentBlock, needCheck: needCheck)) {
        return ret
    }
    if (let Some(ret) <- TransformGenericIfNeeded(value, expectedTy, builder, parentBlock, needCheck: needCheck)) {
        return ret
    }
    return TypeCastIfNeeded(value, expectedTy, builder, parentBlock, needCheck: needCheck)
}

private func CollectNonExtendParentDefs(cur: ClassDef, allParents: HashSet<Int64>): Unit {
    if (allParents.contains(cur.nodeId)) {
        return
    }
    allParents.add(cur.nodeId)
    for (parent in cur.GetImplementedInterfaceDefs()) {
        CollectNonExtendParentDefs(parent, allParents)
    }
    if (let Some(superDef) <- cur.GetSuperClassDef()) {
        CollectNonExtendParentDefs(superDef, allParents)
    }
}

public func ParentDefIsFromExtend(cur: CustomTypeDef, parent: ClassDef): Bool {
    let allParents = HashSet<Int64>()
    for (parentDef in cur.GetImplementedInterfaceDefs()) {
        CollectNonExtendParentDefs(parentDef, allParents)
    }
    if (let Some(clsDef) <- (cur as ClassDef)) {
        if (let Some(superDef) <- clsDef.GetSuperClassDef()) {
            CollectNonExtendParentDefs(superDef, allParents)
        }
    }
    return cur.nodeId != parent.nodeId && !allParents.contains(parent.nodeId)
}

public func GetInstSubType(genericSubType: Type, instParentType: ClassType, builder: CHIRBuilder): Type {
    if (!genericSubType.IsGenericRelated()) {
        return genericSubType
    }
    if (genericSubType.objectId == instParentType.objectId) {
        return genericSubType
    }
    var pair = genericSubType.CalculateGenericTyMapping(instParentType)
    var res = pair[0]
    var replaceTable = pair[1]
    if (!res) {
        for (parent in genericSubType.GetSuperTypesRecusively(builder)) {
            pair = parent.CalculateGenericTyMapping(instParentType)
            res = pair[0]
            replaceTable = pair[1]
            if (res) {
                break
            }
        }
    }
    CJC_ASSERT(res)
    return ReplaceRawGenericArgType(genericSubType, replaceTable, builder)
}

public func RemoveBoxTypeShellIfNeed(ty: Type): Type {
    if (!ty.IsRef()) {
        return ty
    }
    let baseType = (ty as RefType).getOrThrow().GetBaseType()
    if (!baseType.IsBox()) {
        return ty
    }
    return (baseType as BoxType).getOrThrow().GetBaseType()
}

public func CreateBoxRefTypeIfNeed(baseType: Type, builder: CHIRBuilder): Type {
    if (baseType.IsRef()) {
        return baseType
    }
    return builder.context.GetRefTy(builder.context.GetBoxTy(baseType))
}

public func IsOverflowOperator(name: String): Bool {
    for (operatorName in OVERFLOW_OPERATOR_NAMES) {
        if (operatorName == name) {
            return true
        }
    }
    return false
}

public func CanBeIntegerType(ty: Type): Bool {
    return ty.IsInteger() || ty.IsGeneric()
}

public func IsOverflowOperator(name: String, funcTy: FuncType): Bool {
    let params = funcTy.GetParamTypes()
    if (params.size == 1 && IsOverflowOperator(name)) {
        return CanBeIntegerType(params[0]) && CanBeIntegerType(funcTy.GetReturnType())
    }
    if (params.size == 0 && name == "-") {
        return CanBeIntegerType(funcTy.GetReturnType())
    }
    return false
}

public func OverflowStrategyPrefix(ovf: OverflowStrategy): String {
    return match (ovf) {
        case OverflowStrategy.WRAPPING => "&"
        case OverflowStrategy.THROWING => "~"
        case _ => "%"
    }
}

private func GetInstMapFromDefAndExtends(customTy: CustomType): HashMap<Int64, Type> {
    let replaceTable = HashMap<Int64, Type>()
    let def = customTy.GetCustomTypeDef()
    if (!def.TestAttr(Attribute.GENERIC)) {
        return replaceTable
    }
    let genericParams = def.GetGenericTypeParams()
    let instantiatedArgs = customTy.GetTypeArgs()
    if (!genericParams.isEmpty()) {
        CJC_ASSERT(genericParams.size == instantiatedArgs.size)
    }
    var idx: Int64 = 0
    while (idx < genericParams.size) {
        replaceTable[genericParams[idx].objectId] = instantiatedArgs[idx]
        idx++
    }
    for (exDef in def.GetExtends()) {
        let genericParamsInExtendTy = exDef.GetExtendedType().getOrThrow().GetTypeArgs()
        CJC_ASSERT(genericParamsInExtendTy.size == instantiatedArgs.size)
        var extendIdx: Int64 = 0
        while (extendIdx < genericParamsInExtendTy.size) {
            if (let Some(genericTy) <- (genericParamsInExtendTy[extendIdx] as GenericType)) {
                replaceTable[genericTy.objectId] = instantiatedArgs[extendIdx]
            }
            extendIdx++
        }
    }
    return replaceTable
}

private func FuncMayBeInVtable(fn: Function): Bool {
    if (fn.IsConstructor() || fn.IsFinalizer()) {
        return false
    }
    if (fn.GetFuncKind() == FuncKind.ANNOFACTORY_FUNC) {
        return false
    }
    if (fn.GetWrappedRawMethod().isSome()) {
        return false
    }
    if (fn.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
        return false
    }
    return fn.TestAttr(Attribute.PUBLIC) || fn.TestAttr(Attribute.PROTECTED) ||
        (fn.TestAttr(Attribute.STATIC) && !fn.TestAttr(Attribute.PRIVATE))
}

private func UpdateInstanceAttr(vtable: VTableInDef): Unit {
    for (vtableIt in vtable.GetModifiableTypeVTables()) {
        for (infoIt in vtableIt.GetModifiableVirtualMethods()) {
            let method = infoIt.GetVirtualMethod().getOrThrow()
            if (method.IsPureAbstract()) {
                continue
            }
            if (!method.TestAttr(Attribute.VIRTUAL)) {
                method.EnableAttr(Attribute.FINAL)
            }
        }
    }
}

private func TypeIsMatchedForVTable(type1: Type, type2: Type): Bool {
    if (type1.objectId == type2.objectId) {
        return true
    }
    if (type1.IsGeneric() || type2.IsGeneric()) {
        return true
    }
    if (!type1.IsSameTypeKind(type2)) {
        return false
    }
    if (let Some(customType1) <- (type1 as CustomType)) {
        let customType2 = (type2 as CustomType).getOrThrow()
        if (customType1.GetCustomTypeDef().nodeId != customType2.GetCustomTypeDef().nodeId) {
            return false
        }
    }
    let type1Args = type1.GetTypeArgs()
    let type2Args = type2.GetTypeArgs()
    if (type1Args.size != type2Args.size) {
        return false
    }
    var idx: Int64 = 0
    while (idx < type1Args.size) {
        if (!TypeIsMatchedForVTable(type1Args[idx], type2Args[idx])) {
            return false
        }
        idx++
    }
    return true
}

private func CollectBrotherDefs(curExtend: ExtendDef, builder: CHIRBuilder): ArrayList<CustomTypeDef> {
    let extendDefs = curExtend.GetExtendedType().getOrThrow().GetExtends(builder)
    CJC_ASSERT(!extendDefs.isEmpty())
    let brotherDefs = ArrayList<CustomTypeDef>()
    for (def in extendDefs) {
        if (def.nodeId != curExtend.nodeId &&
            TypeIsMatchedForVTable(def.GetExtendedType().getOrThrow(), curExtend.GetExtendedType().getOrThrow())) {
            brotherDefs.add(def)
        }
    }
    if (let Some(extendedTy) <- (curExtend.GetExtendedType().getOrThrow() as CustomType)) {
        brotherDefs.add(extendedTy.GetCustomTypeDef())
    }
    return brotherDefs
}

private func CloneFuncSigInfo(info: FuncSigInfo): FuncSigInfo {
    return FuncSigInfo(info.funcType, funcName: info.funcName, genericTypeParams: info.GetGenericTypeParams())
}

private func CloneVirtualMethodInfo(info: VirtualMethodInfo): VirtualMethodInfo {
    return VirtualMethodInfo(CloneFuncSigInfo(info.GetCondition()), info.GetVirtualMethod(), info.GetAttributeInfo(),
        info.GetOriginalFuncType(), info.GetInstParentType(), info.GetMethodInstRetType())
}

public class VTableGenerator {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    private func GetAllMethods(ty: Type): ArrayList<Function> {
        let methods = ArrayList<Function>()
        if (let Some(customTy) <- (ty as CustomType)) {
            for (method in customTy.GetCustomTypeDef().GetMethods()) {
                methods.add(method)
            }
        }
        for (extendDef in ty.GetExtends(builder)) {
            for (method in extendDef.GetMethods()) {
                methods.add(method)
            }
        }
        return methods
    }

    private func GetAllMethods(def: CustomTypeDef): ArrayList<Function> {
        if (let Some(extendDef) <- (def as ExtendDef)) {
            if (let Some(ty) <- extendDef.GetExtendedType()) {
                return GetAllMethods(ty)
            }
            return ArrayList<Function>()
        }
        return GetAllMethods(def.GetType().getOrThrow())
    }

    private func CollectCurDefMethodsMayBeInVtable(def: CustomTypeDef, publicFuncs: ArrayList<Function>): Unit {
        for (fn in GetAllMethods(def)) {
            if (FuncMayBeInVtable(fn)) {
                publicFuncs.add(fn)
            }
        }
    }

    private func CreateVirtualFuncInfo(method: Function, originalParentType: Type,
        replaceTable: HashMap<Int64, Type>): VirtualMethodInfo {
        let originalFuncType = method.GetFuncType().getOrThrow()
        let originalParamTypes = originalFuncType.GetParamTypes()
        if (!method.TestAttr(Attribute.STATIC)) {
            originalParamTypes.remove(at: 0)
        }
        let instParamTypes = ArrayList<Type>()
        for (paramTy in originalParamTypes) {
            instParamTypes.add(ReplaceRawGenericArgType(paramTy, replaceTable, builder))
        }
        let sigType = builder.context.GetFuncTy(instParamTypes, builder.context.GetUnitTy())
        let instParentType = ReplaceRawGenericArgType(originalParentType, replaceTable, builder)
        let instRetType = ReplaceRawGenericArgType(originalFuncType.GetReturnType(), replaceTable, builder)
        let condition = FuncSigInfo(sigType, funcName: method.GetSrcCodeIdentifier(),
            genericTypeParams: method.GetGenericTypeParams())
        return VirtualMethodInfo(condition, method, method.GetAttributeInfo(), originalFuncType, instParentType,
            instRetType)
    }

    private func IsSigTypeMatched(curFuncInfo: VirtualMethodInfo, funcInfoInVtable: VirtualMethodInfo): Bool {
        if (curFuncInfo.GetAttributeInfo().Test(Attribute.STATIC) !=
            funcInfoInVtable.GetAttributeInfo().Test(Attribute.STATIC)) {
            return false
        }
        if (curFuncInfo.GetVirtualMethod().getOrThrow().IsPureAbstract() &&
            !funcInfoInVtable.GetVirtualMethod().getOrThrow().IsPureAbstract()) {
            return false
        }
        return funcInfoInVtable.FuncSigIsMatched(curFuncInfo.GetCondition(), builder)
    }

    private func VirtualFuncShouldAddToVTableInItsOwnParent(ownParent: ClassType, alreadyIn: ClassType): Bool {
        let inheritanceList = ArrayList<ClassType>()
        let res = ownParent.GetCustomTypeDef().GetType().getOrThrow().CalculateGenericTyMapping(ownParent)
        CJC_ASSERT(res[0])
        for (ty in ownParent.GetCustomTypeDef().GetImplementedInterfaceTys()) {
            let instTy = (ReplaceRawGenericArgType(ty, res[1], builder) as ClassType).getOrThrow()
            GetAllInstantiatedParentType(instTy, builder, inheritanceList)
        }
        if (let Some(superClass) <- ownParent.GetSuperClassTy(builder: builder)) {
            GetAllInstantiatedParentType(superClass, builder, inheritanceList)
        }
        for (parent in inheritanceList) {
            if (parent.objectId == alreadyIn.objectId) {
                return false
            }
        }
        return true
    }

    private func UpdateVtable(curFuncInfo: VirtualMethodInfo, vtable: VTableInDef): Bool {
        var maybeAddNewItemToVtable = true
        for (vtableIt in vtable.GetModifiableTypeVTables()) {
            for (funcInfo in vtableIt.GetModifiableVirtualMethods()) {
                if (IsSigTypeMatched(curFuncInfo, funcInfo)) {
                    funcInfo.UpdateMethodInfo(curFuncInfo)
                    let parentTy = curFuncInfo.GetInstParentType() as ClassType
                    if (parentTy.isNone()) {
                        maybeAddNewItemToVtable = false
                    } else {
                        maybeAddNewItemToVtable = maybeAddNewItemToVtable &&
                            VirtualFuncShouldAddToVTableInItsOwnParent(parentTy.getOrThrow(),
                                vtableIt.GetSrcParentType().getOrThrow())
                    }
                    break
                }
            }
        }
        return maybeAddNewItemToVtable
    }

    private func MergeVtable(instParentTy: ClassType, vtable: VTableInDef): Unit {
        let replaceTable = GetInstMapFromDefAndExtends(instParentTy)
        let parentDef = instParentTy.GetClassDef()
        let funcsMayBeInVtable = ArrayList<Function>()
        CollectCurDefMethodsMayBeInVtable(parentDef, funcsMayBeInVtable)
        for (fn in funcsMayBeInVtable) {
            let parentType = fn.GetParentCustomTypeOrExtendedType().getOrThrow()
            let funcInfo = CreateVirtualFuncInfo(fn, parentType, replaceTable)
            let maybeAddNewItemToVtable = UpdateVtable(funcInfo, vtable)
            if (maybeAddNewItemToVtable && IsVirtualFunction(funcInfo.GetVirtualMethod().getOrThrow())) {
                vtable.AddNewItemToTypeVTable(instParentTy, funcInfo)
            }
        }
    }

    private func UpdateAbstractMethodWithImplementedMethod(vtable: VTableInDef, curParentTy: ClassType,
        abstractFuncInfo: VirtualMethodInfo): Unit {
        var done = false
        for (vtableIt in vtable.GetModifiableTypeVTables()) {
            let srcParent = vtableIt.GetSrcParentType().getOrThrow()
            if (srcParent.GetClassDef().IsClass() || srcParent.objectId == curParentTy.objectId) {
                continue
            }
            for (funcInfo in vtableIt.GetModifiableVirtualMethods()) {
                if (funcInfo.GetVirtualMethod().getOrThrow().IsPureAbstract()) {
                    continue
                }
                if (IsSigTypeMatched(funcInfo, abstractFuncInfo)) {
                    abstractFuncInfo.UpdateMethodInfo(funcInfo)
                    done = true
                    break
                }
            }
            if (done) {
                break
            }
        }
    }

    private func UpdateAbstractMethodInVtable(vtable: VTableInDef): Unit {
        for (vtableIt in vtable.GetModifiableTypeVTables()) {
            for (funcInfo in vtableIt.GetModifiableVirtualMethods()) {
                if (!funcInfo.GetVirtualMethod().getOrThrow().IsPureAbstract()) {
                    continue
                }
                UpdateAbstractMethodWithImplementedMethod(vtable, vtableIt.GetSrcParentType().getOrThrow(), funcInfo)
            }
        }
    }

    private func GetInstMapFromDefIncludeParents(def: CustomTypeDef, curType: Type): HashMap<Int64, Type> {
        let inheritanceList = def.GetSuperTypesRecusively(builder)
        let replaceTable = HashMap<Int64, Type>()
        for (parent in inheritanceList) {
            let fromParent = GetInstMapFromDefAndExtends(parent)
            for ((key, value) in fromParent) {
                if (!replaceTable.contains(key)) {
                    replaceTable[key] = value
                }
            }
        }
        let res = def.GetType().getOrThrow().CalculateGenericTyMapping(curType)
        for ((key, value) in replaceTable) {
            replaceTable[key] = ReplaceRawGenericArgType(value, res[1], builder)
        }
        for ((key, value) in res[1]) {
            if (!replaceTable.contains(key)) {
                replaceTable[key] = value
            }
        }
        return replaceTable
    }

    private func CollectMethodsFromAncestorInterfaceMayBeInVTable(curDef: CustomTypeDef,
        methods: ArrayList<Function>): Unit {
        for (parent in curDef.GetImplementedInterfaceDefs()) {
            CollectCurDefMethodsMayBeInVtable(parent, methods)
            CollectMethodsFromAncestorInterfaceMayBeInVTable(parent, methods)
        }
    }

    private func CollectMethodsIncludeParentsMayBeInVtable(curDef: CustomTypeDef): ArrayList<Function> {
        let methods = ArrayList<Function>()
        CollectMethodsFromAncestorInterfaceMayBeInVTable(curDef, methods)
        if (let Some(clsDef) <- (curDef as ClassDef)) {
            var superOpt = clsDef.GetSuperClassDef()
            while (let Some(superDef) <- superOpt) {
                CollectCurDefMethodsMayBeInVtable(superDef, methods)
                CollectMethodsFromAncestorInterfaceMayBeInVTable(superDef, methods)
                superOpt = superDef.GetSuperClassDef()
            }
        }
        for (fn in curDef.GetMethods()) {
            if (FuncMayBeInVtable(fn)) {
                methods.add(fn)
            }
        }
        return methods
    }

    private func CollectAllPublicAndProtectedMethods(curDef: CustomTypeDef): ArrayList<VirtualMethodInfo> {
        let allMethods = ArrayList<VirtualMethodInfo>()
        if (let Some(extendDef) <- (curDef as ExtendDef)) {
            let brotherDefs = CollectBrotherDefs(extendDef, builder)
            for (brotherDef in brotherDefs) {
                let replaceTable = GetInstMapFromDefIncludeParents(brotherDef, extendDef.GetExtendedType().getOrThrow())
                let publicFuncs = CollectMethodsIncludeParentsMayBeInVtable(brotherDef)
                for (fn in publicFuncs) {
                    let parentType = fn.GetParentCustomTypeOrExtendedType().getOrThrow()
                    let funcInfo = CreateVirtualFuncInfo(fn, parentType, replaceTable)
                    allMethods.add(funcInfo)
                }
            }
        }
        let emptyTable = HashMap<Int64, Type>()
        for (fn in curDef.GetMethods()) {
            if (FuncMayBeInVtable(fn)) {
                let parentType = fn.GetParentCustomTypeOrExtendedType().getOrThrow()
                let funcInfo = CreateVirtualFuncInfo(fn, parentType, emptyTable)
                allMethods.add(funcInfo)
            }
        }
        return allMethods
    }

    public func GenerateVTable(customTypeDef: CustomTypeDef): Unit {
        if (customTypeDef.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            return
        }
        let inheritanceList = customTypeDef.GetSuperTypesRecusively(builder)
        let vtable = VTableInDef()
        for (parent in inheritanceList) {
            MergeVtable(parent, vtable)
        }
        UpdateAbstractMethodInVtable(vtable)
        let publicAndProtectedMethods = CollectAllPublicAndProtectedMethods(customTypeDef)
        for (funcInfo in publicAndProtectedMethods) {
            let maybeAddNewItemToVtable = UpdateVtable(funcInfo, vtable)
            if (!maybeAddNewItemToVtable) {
                continue
            }
            if (customTypeDef.IsClassLike() && IsVirtualFunction(funcInfo.GetVirtualMethod().getOrThrow())) {
                let srcParentType = (funcInfo.GetVirtualMethod().getOrThrow().GetParentCustomTypeOrExtendedType()
                    .getOrThrow() as ClassType).getOrThrow()
                vtable.AddNewItemToTypeVTable(srcParentType, funcInfo)
            }
        }
        UpdateInstanceAttr(vtable)
        customTypeDef.SetVTable(vtable)
    }
}

private func FuncTypeMatch(parentFuncType: FuncType, curFuncType: FuncType): Bool {
    let parentFuncParamTypes = parentFuncType.GetParamTypes()
    let curFuncParamTypes = curFuncType.GetParamTypes()
    CJC_ASSERT(parentFuncParamTypes.size == curFuncParamTypes.size)
    var idx: Int64 = 0
    while (idx < parentFuncParamTypes.size) {
        if (!VirMethodParamTypeIsMatched(parentFuncParamTypes[idx], curFuncParamTypes[idx])) {
            return false
        }
        idx++
    }
    return VirMethodReturnTypeIsMatched(parentFuncType.GetReturnType(), curFuncType.GetReturnType())
}

private func JudgeIfNeedVirtualWrapper(parentFuncInfo: VirtualMethodInfo, virtualFunc: Function, selfTy: Type,
    builder: CHIRBuilder): Bool {
    if (!selfTy.IsClassOrArray() && !virtualFunc.TestAttr(Attribute.STATIC)) {
        return true
    }
    let funcParentType = virtualFunc.GetParentCustomTypeDef().getOrThrow().GetType().getOrThrow()
    if (funcParentType.objectId != selfTy.objectId && funcParentType.IsGenericRelated() &&
        !funcParentType.IsEqualOrSubTypeOf(parentFuncInfo.GetInstParentType(), builder)) {
        return true
    }
    let parentFuncType = parentFuncInfo.GetOriginalFuncType()
    return !FuncTypeMatch(parentFuncType, virtualFunc.GetFuncType().getOrThrow())
}

private func TryDeleteVirtuallWrapperFunc(customTypeDef: CustomTypeDef, finalFunc: Function,
    builder: CHIRBuilder): Unit {
    if (!customTypeDef.TestAttr(Attribute.SPECIFIC)) {
        return
    }
    if (!finalFunc.TestAttr(Attribute.FINAL)) {
        return
    }
    for (method in customTypeDef.GetMethods()) {
        if (!method.TestAttr(Attribute.DESERIALIZED) || !method.TestAttr(Attribute.VIRTUAL)) {
            continue
        }
        if (finalFunc.GetWrappedRawMethod().getOrThrow().GetSrcCodeIdentifier() !=
            method.GetWrappedRawMethod().getOrThrow().GetSrcCodeIdentifier()) {
            continue
        }
        if (finalFunc.GetFuncType().getOrThrow().IsEqualOrSubTypeOf(method.GetFuncType().getOrThrow(), builder)) {
            method.DestroySelf()
            return
        }
    }
}

private class WrapperFuncGenericTable {
    public let funcGenericTypeParams: ArrayList<GenericType> = ArrayList<GenericType>()
    public let replaceTable: HashMap<Int64, Type> = HashMap<Int64, Type>()
    public let inverseReplaceTable: HashMap<Int64, Type> = HashMap<Int64, Type>()

    public init() {}
}

public class WrapVirtualFunc {
    private let builder: CHIRBuilder
    private let increCachedInfo: CompilationCache
    private let incrementalKind: IncreKind
    private let targetIsWin: Bool
    private let wrapperCache: HashMap<String, Function> = HashMap<String, Function>()
    private let curVirtFuncWrapDep: VirtualWrapperDepMap = VirtualWrapperDepMap()
    private let delVirtFuncWrapForIncr: VirtualWrapperDepMap = VirtualWrapperDepMap()

    public init(builder: CHIRBuilder, increCachedInfo: CompilationCache, incrementalKind: IncreKind,
        targetIsWin: Bool) {
        this.builder = builder
        this.increCachedInfo = increCachedInfo
        this.incrementalKind = incrementalKind
        this.targetIsWin = targetIsWin
    }

    public func CheckAndWrap(customTypeDef: CustomTypeDef): Unit {
        let selfTy = customTypeDef.GetType().getOrThrow()
        for (vtableIt in customTypeDef.GetDefVTable().GetTypeVTables()) {
            let parentTy = vtableIt.GetSrcParentType().getOrThrow()
            if (parentTy.objectId == selfTy.objectId) {
                continue
            }
            let parentDef = parentTy.GetClassDef()
            let parentDefType = (parentDef.GetType().getOrThrow() as ClassType).getOrThrow()
            let parentVTable = parentDef.GetDefVTable().GetExpectedTypeVTable(parentDefType)
            CJC_ASSERT(!parentVTable.IsEmpty())
            CJC_ASSERT(parentVTable.GetMethodNum() == vtableIt.GetMethodNum())
            var idx: Int64 = 0
            while (idx < vtableIt.GetMethodNum()) {
                let curVirMethodInfo = vtableIt.GetVirtualMethods()[idx]
                if (curVirMethodInfo.GetVirtualMethod().getOrThrow().IsPureAbstract()) {
                    idx++
                    continue
                }
                let parentVirMethodInfo = parentVTable.GetVirtualMethods()[idx]
                let wrapper = CreateVirtualWrapperIfNeeded(curVirMethodInfo, parentVirMethodInfo, selfTy,
                    customTypeDef, parentTy)
                if (incrementalKind != IncreKind.INVALID) {
                    HandleVirtualFuncWrapperForIncrCompilation(wrapper, curVirMethodInfo.GetVirtualMethod().getOrThrow())
                }
                if (let Some(wrapperFunc) <- wrapper) {
                    customTypeDef.UpdateVtableItem(parentTy, idx, wrapperFunc, selfTy, "")
                }
                idx++
            }
        }
    }

    private func HandleVirtualFuncWrapperForIncrCompilation(wrapper: Option<Function>, curFunc: Function): Unit {
        CJC_ASSERT(!curFunc.GetSrcCodeIdentifier().isEmpty())
        let cachedVirDep = increCachedInfo.virtualFuncDep
        let rawMangleName = curFunc.GetRawMangledName()
        if (curFunc.TestAttr(Attribute.COMPILER_ADD) && rawMangleName.isEmpty()) {
            return
        }
        if (rawMangleName.isEmpty()) {
            CJC_ABORT()
            return
        }
        if (let Some(wrapperFunc) <- wrapper) {
            curVirtFuncWrapDep[rawMangleName] = wrapperFunc.GetIdentifierWithoutPrefix()
        }
        if (incrementalKind != IncreKind.INCR || cachedVirDep.isEmpty()) {
            return
        }
        if (let Some(cachedWrapper) <- cachedVirDep.get(rawMangleName)) {
            if (let Some(wrapperFunc) <- wrapper) {
                if (cachedWrapper != wrapperFunc.GetIdentifierWithoutPrefix()) {
                    delVirtFuncWrapForIncr[rawMangleName] = cachedWrapper
                }
            } else {
                delVirtFuncWrapForIncr[rawMangleName] = cachedWrapper
            }
        }
    }

    private func GetReplaceTableForVirtualFunc(parentTy: ClassType, funcIdentifier: String,
        parentFuncInfo: VirtualMethodInfo): WrapperFuncGenericTable {
        let genericParentTypeArgs = parentTy.GetCustomTypeDef().GetGenericTypeParams()
        let instParentTypeArgs = parentTy.GetTypeArgs()
        if (!genericParentTypeArgs.isEmpty()) {
            CJC_ASSERT(genericParentTypeArgs.size == instParentTypeArgs.size)
        }
        let resultTable = WrapperFuncGenericTable()
        var newGenericIdx: Int64 = 0
        var idx: Int64 = 0
        while (idx < genericParentTypeArgs.size) {
            resultTable.replaceTable[genericParentTypeArgs[idx].objectId] = instParentTypeArgs[idx]
            idx++
        }
        let parentMethodGenericTys = parentFuncInfo.GetGenericTypeParams()
        for (parentMethodGenericTy in parentMethodGenericTys) {
            let srcIdentifier = "fT" + newGenericIdx.toString()
            newGenericIdx++
            let tyIdentifier = funcIdentifier + "_" + srcIdentifier
            let funcGenericParam = builder.context.GetGenericTy(tyIdentifier, srcIdentifier)
            resultTable.funcGenericTypeParams.add(funcGenericParam)
            resultTable.replaceTable[parentMethodGenericTy.objectId] = funcGenericParam
        }
        CJC_ASSERT(resultTable.funcGenericTypeParams.size == parentMethodGenericTys.size)
        var boundIdx: Int64 = 0
        while (boundIdx < resultTable.funcGenericTypeParams.size) {
            let newUpperBounds = ArrayList<Type>()
            for (ty in parentMethodGenericTys[boundIdx].GetUpperBounds()) {
                newUpperBounds.add(ReplaceRawGenericArgType(ty, resultTable.replaceTable, builder))
            }
            resultTable.funcGenericTypeParams[boundIdx].SetUpperBounds(newUpperBounds)
            boundIdx++
        }
        return resultTable
    }

    private func CreateWrapperFuncBody(wrapperFunc: Function, childFuncInfo: VirtualMethodInfo, selfTy: Type,
        genericTable: WrapperFuncGenericTable): Unit {
        let rawFunc = childFuncInfo.GetVirtualMethod().getOrThrow()
        let wrapperFuncType = wrapperFunc.GetFuncType().getOrThrow()
        let wrapperRetTy = wrapperFuncType.GetReturnType()
        let body = builder.CreateBlockGroup(wrapperFunc)
        wrapperFunc.InitBody(body)
        let args = ArrayList<Value>()
        for (ty in wrapperFuncType.GetParamTypes()) {
            args.add(builder.CreateParameter(ty, DebugLocation(), wrapperFunc))
        }
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let ret = builder.CreateAllocate(builder.context.GetRefTy(wrapperRetTy), wrapperRetTy, entry)
        wrapperFunc.SetReturnValue(ret.GetResult().getOrThrow())

        var instParentType = childFuncInfo.GetInstParentType()
        if (instParentType.IsClassOrArray() || (instParentType.IsStruct() && rawFunc.TestAttr(Attribute.MUT))) {
            instParentType = builder.context.GetRefTy(instParentType)
        }
        let expectedParamTypes = wrapperFuncType.GetParamTypes()
        var expectedIdx: Int64 = 0
        while (expectedIdx < expectedParamTypes.size) {
            expectedParamTypes[expectedIdx] = RemoveBoxTypeShellIfNeed(expectedParamTypes[expectedIdx])
            expectedIdx++
        }
        if (!rawFunc.TestAttr(Attribute.STATIC)) {
            expectedParamTypes[0] = instParentType
        }

        var applyRetTy = rawFunc.GetFuncType().getOrThrow().GetReturnType()
        if (applyRetTy.IsGenericRelated()) {
            applyRetTy = RemoveBoxTypeShellIfNeed(wrapperRetTy)
        }
        CJC_ASSERT(args.size == expectedParamTypes.size)
        var argIdx: Int64 = 0
        while (argIdx < expectedParamTypes.size) {
            args[argIdx] = TypeCastOrBoxIfNeeded(args[argIdx], expectedParamTypes[argIdx], builder, entry)
            argIdx++
        }
        let instArgTypes = ArrayList<Type>()
        for (funcGenericParam in genericTable.funcGenericTypeParams) {
            instArgTypes.add(funcGenericParam)
        }
        var thisInstTy = selfTy
        if (thisInstTy.IsClassOrArray()) {
            thisInstTy = builder.context.GetRefTy(thisInstTy)
        }
        let apply = builder.CreateApply(applyRetTy, rawFunc,
            FuncCallContext(args: args, instTypeArgs: instArgTypes, thisType: Some(thisInstTy)), entry)
        apply.SetDebugLocation(rawFunc.GetDebugLocation())
        let res = TypeCastOrBoxIfNeeded(apply.GetResult().getOrThrow(), wrapperRetTy, builder, entry)
        builder.CreateStore(res, wrapperFunc.GetReturnValue().getOrThrow(), entry)
        builder.CreateExit(None, entry)
    }

    private func GetWrapperFuncType(parentFuncTyWithoutThisArg: FuncType, selfTy: Type,
        replaceTable: HashMap<Int64, Type>, isStatic: Bool): FuncType {
        let erasedFuncTy = (ReplaceRawGenericArgType(parentFuncTyWithoutThisArg, replaceTable, builder) as FuncType)
            .getOrThrow()
        let wrapperParamTypes = erasedFuncTy.GetParamTypes()
        var wrapperRetTy = erasedFuncTy.GetReturnType()
        let parentParamTypes = parentFuncTyWithoutThisArg.GetParamTypes()
        let parentRetType = parentFuncTyWithoutThisArg.GetReturnType()
        CJC_ASSERT(wrapperParamTypes.size == parentParamTypes.size)
        var idx: Int64 = 0
        while (idx < wrapperParamTypes.size) {
            if (!VirMethodParamTypeIsMatched(wrapperParamTypes[idx], parentParamTypes[idx])) {
                wrapperParamTypes[idx] = CreateBoxRefTypeIfNeed(wrapperParamTypes[idx], builder)
            }
            idx++
        }
        if (!VirMethodReturnTypeIsMatched(wrapperRetTy, parentRetType)) {
            wrapperRetTy = CreateBoxRefTypeIfNeed(wrapperRetTy, builder)
        }
        if (!isStatic) {
            var thisArgTy: Type = builder.context.GetRefTy(selfTy)
            if (!selfTy.IsClassOrArray()) {
                thisArgTy = builder.context.GetRefTy(builder.context.GetAnyTy().getOrThrow())
            }
            wrapperParamTypes.add(thisArgTy, at: 0)
        }
        return builder.context.GetFuncTy(wrapperParamTypes, wrapperRetTy)
    }

    private func RemoveThisArg(funcTy: FuncType): FuncType {
        let paramTys = funcTy.GetParamTypes()
        let retTy = funcTy.GetReturnType()
        paramTys.remove(at: 0)
        return builder.context.GetFuncTy(paramTys, retTy)
    }

    private func CreateVirtualWrapperIfNeeded(funcInfo: VirtualMethodInfo, parentFuncInfo: VirtualMethodInfo,
        selfTy: Type, customTypeDef: CustomTypeDef, parentTy: ClassType): Option<Function> {
        let curFunc = funcInfo.GetVirtualMethod().getOrThrow()
        if (!JudgeIfNeedVirtualWrapper(parentFuncInfo, curFunc, selfTy, builder)) {
            return None
        }
        let isStatic = curFunc.TestAttr(Attribute.STATIC)
        let parentFuncTy = parentFuncInfo.GetOriginalFuncType()
        let parentFuncTyWithoutThisArg = if (!isStatic) { RemoveThisArg(parentFuncTy) } else { parentFuncTy }
        let funcIdentifier = GenerateVirtualFuncMangleName(curFunc, customTypeDef, parentTy, true)
        if (let Some(cached) <- wrapperCache.get(funcIdentifier)) {
            return cached
        }
        let genericTable = GetReplaceTableForVirtualFunc(parentTy, funcIdentifier, parentFuncInfo)
        let wrapperTy = GetWrapperFuncType(parentFuncTyWithoutThisArg, selfTy, genericTable.replaceTable, isStatic)
        let packageName = customTypeDef.GetPackageName()
        let isImported = customTypeDef.TestAttr(Attribute.IMPORTED) &&
            parentTy.GetCustomTypeDef().TestAttr(Attribute.IMPORTED)
        let parentIsFromExtend = ParentDefIsFromExtend(customTypeDef, parentTy.GetClassDef())
        let wrapperFunc = builder.CreateFunction(wrapperTy, funcIdentifier, srcCodeIdentifier: "",
            rawMangledName: "", packageName: packageName, genericTypeParams: genericTable.funcGenericTypeParams)
        wrapperFunc.SetWrappedRawMethod(curFunc)
        wrapperFunc.AppendAttributeInfo(curFunc.GetAttributeInfo())
        wrapperFunc.EnableAttr(Attribute.NO_REFLECT_INFO)
        wrapperFunc.EnableAttr(Attribute.NO_DEBUG_INFO)
        if (isImported && !parentIsFromExtend) {
            wrapperFunc.EnableAttr(Attribute.IMPORTED)
        } else {
            wrapperFunc.DisableAttr(Attribute.IMPORTED)
        }
        customTypeDef.AddMethod(wrapperFunc)
        TryDeleteVirtuallWrapperFunc(customTypeDef, wrapperFunc, builder)
        wrapperFunc.SetLinkTypeInfo(BasicLinkage.EXTERNAL)
        if (parentIsFromExtend) {
            if (targetIsWin) {
                wrapperFunc.SetLinkTypeInfo(BasicLinkage.INTERNAL)
            } else {
                wrapperFunc.SetLinkTypeInfo(BasicLinkage.WEAK_ODR)
            }
        }
        wrapperCache[funcIdentifier] = wrapperFunc
        if (isImported && !parentIsFromExtend) {
            return wrapperFunc
        }
        CreateWrapperFuncBody(wrapperFunc, funcInfo, selfTy, genericTable)
        return wrapperFunc
    }

    public func GetCurVirtFuncWrapDep(): VirtualWrapperDepMap {
        return curVirtFuncWrapDep
    }

    public func GetDelVirtFuncWrapForIncr(): VirtualWrapperDepMap {
        return delVirtFuncWrapForIncr
    }
}

private func FindPathToTarget(cur: ClassType, targetParent: ClassType, builder: CHIRBuilder,
    replaceTable: HashMap<Int64, Type>, outPath: ArrayList<ClassType>, onPath: HashSet<Int64>): Bool {
    if (cur.objectId == targetParent.objectId) {
        outPath.add((ReplaceRawGenericArgType(cur, replaceTable, builder) as ClassType).getOrThrow())
        return true
    }
    if (onPath.contains(cur.objectId)) {
        return false
    }
    onPath.add(cur.objectId)
    for (ex in cur.GetCustomTypeDef().GetExtends()) {
        let res = ex.GetExtendedType().getOrThrow().CalculateGenericTyMapping(cur)
        if (!res[0]) {
            continue
        }
        for (interfaceTy in ex.GetImplementedInterfaceTys()) {
            if (FindPathToTarget(interfaceTy, targetParent, builder, res[1], outPath, onPath)) {
                outPath.add((ReplaceRawGenericArgType(cur, replaceTable, builder) as ClassType).getOrThrow())
                onPath.remove(cur.objectId)
                return true
            }
        }
    }
    for (interfaceTy in cur.GetImplementedInterfaceTys(builder)) {
        if (FindPathToTarget(interfaceTy, targetParent, builder, replaceTable, outPath, onPath)) {
            outPath.add((ReplaceRawGenericArgType(cur, replaceTable, builder) as ClassType).getOrThrow())
            onPath.remove(cur.objectId)
            return true
        }
    }
    if (let Some(superClass) <- cur.GetSuperClassTy(builder: builder)) {
        if (FindPathToTarget(superClass, targetParent, builder, replaceTable, outPath, onPath)) {
            outPath.add((ReplaceRawGenericArgType(cur, replaceTable, builder) as ClassType).getOrThrow())
            onPath.remove(cur.objectId)
            return true
        }
    }
    onPath.remove(cur.objectId)
    return false
}

private func GetTargetInheritanceList(curDef: CustomTypeDef, targetParent: ClassType,
    builder: CHIRBuilder): ArrayList<ClassType> {
    let path = ArrayList<ClassType>()
    let onPath = HashSet<Int64>()
    let emptyTable = HashMap<Int64, Type>()
    let structTy = (curDef.GetType().getOrThrow() as StructType).getOrThrow()
    for (interfaceTy in structTy.GetImplementedInterfaceTys(builder)) {
        path.clear()
        onPath.clear()
        if (FindPathToTarget(interfaceTy, targetParent, builder, emptyTable, path, onPath)) {
            return path
        }
    }
    CJC_ASSERT(false)
    return path
}

private func CollectReplaceTable(curDef: CustomTypeDef, targetParent: ClassType, rawFunc: Function,
    builder: CHIRBuilder): HashMap<Int64, Type> {
    let inheritanceList = GetTargetInheritanceList(curDef, targetParent, builder)
    var replaceTable = HashMap<Int64, Type>()
    let targetParentDef = rawFunc.GetParentCustomTypeDef().getOrThrow()
    for (parent in inheritanceList) {
        if (parent.GetCustomTypeDef().nodeId != targetParentDef.nodeId) {
            continue
        }
        let res = parent.GetCustomTypeDef().GetType().getOrThrow().CalculateGenericTyMapping(parent)
        CJC_ASSERT(res[0])
        replaceTable = res[1]
        break
    }
    return replaceTable
}

public class WrapMutFunc {
    private let builder: CHIRBuilder
    private let wrapperFuncs: HashMap<String, Function> = HashMap<String, Function>()

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    private func CreateMutFuncWrapper(rawFunc: Function, curDef: CustomTypeDef, srcClassTy: ClassType): Unit {
        let replaceTable = CollectReplaceTable(curDef, srcClassTy, rawFunc, builder)
        let instFuncTy = (ReplaceRawGenericArgType(rawFunc.GetFuncType().getOrThrow(), replaceTable, builder) as FuncType)
            .getOrThrow()
        let wrapperParamsTy = instFuncTy.GetParamTypes()
        let parentDefType = curDef.GetType().getOrThrow()
        wrapperParamsTy[0] = builder.context.GetRefTy(parentDefType)
        let retTy = instFuncTy.GetReturnType()
        let wrapperFuncTy = builder.context.GetFuncTy(wrapperParamsTy, retTy)
        let funcIdentifier = GenerateVirtualFuncMangleName(rawFunc, curDef, srcClassTy, false)
        let pkgName = curDef.GetPackageName()
        let wrapperFn = builder.CreateFunction(wrapperFuncTy, funcIdentifier, srcCodeIdentifier: "",
            rawMangledName: "", packageName: pkgName)
        wrapperFuncs[funcIdentifier] = wrapperFn
        wrapperFn.SetWrappedRawMethod(rawFunc)
        wrapperFn.AppendAttributeInfo(rawFunc.GetAttributeInfo())
        wrapperFn.DisableAttr(Attribute.VIRTUAL)
        wrapperFn.EnableAttr(Attribute.NO_REFLECT_INFO)
        curDef.AddMethod(wrapperFn)
        if (curDef.TestAttr(Attribute.IMPORTED)) {
            wrapperFn.EnableAttr(Attribute.IMPORTED)
            return
        }
        wrapperFn.DisableAttr(Attribute.IMPORTED)
        let body = builder.CreateBlockGroup(wrapperFn)
        wrapperFn.InitBody(body)
        let args = ArrayList<Value>()
        for (paramTy in wrapperParamsTy) {
            args.add(builder.CreateParameter(paramTy, DebugLocation(), wrapperFn))
        }
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let ret = builder.CreateAllocate(builder.context.GetRefTy(retTy), retTy, entry)
        wrapperFn.SetReturnValue(ret.GetResult().getOrThrow())
        let rawFuncFirstArgType = rawFunc.GetFuncType().getOrThrow().GetParamTypes()[0].StripAllRefs()
        var firstArgType = GetInstSubType(rawFuncFirstArgType, srcClassTy, builder)
        if (!firstArgType.IsValueType() || rawFunc.TestAttr(Attribute.MUT)) {
            firstArgType = builder.context.GetRefTy(firstArgType)
        }
        args[0] = TypeCastOrBoxIfNeeded(args[0], firstArgType, builder, entry)
        let apply = builder.CreateApply(retTy, rawFunc,
            FuncCallContext(args: args, thisType: Some(curDef.GetType().getOrThrow())), entry)
        builder.CreateStore(apply.GetResult().getOrThrow(), wrapperFn.GetReturnValue().getOrThrow(), entry)
        let tempThis = TypeCastOrBoxIfNeeded(args[0], wrapperParamsTy[0], builder, entry)
        let load = builder.CreateLoad(parentDefType, tempThis, entry).GetResult().getOrThrow()
        let structMemberTypes = (parentDefType as StructType).getOrThrow().GetInstantiatedMemberTys()
        var idx: Int64 = 0
        while (idx < structMemberTypes.size) {
            let path = ArrayList<UInt64>()
            path.add(UInt64(idx))
            let field = builder.CreateField(structMemberTypes[idx], load, path, entry).GetResult().getOrThrow()
            builder.CreateStoreElementRef(field, wrapperFn.GetParam(0), path, entry)
            idx++
        }
        builder.CreateExit(None, entry)
    }

    public func Run(customTypeDef: CustomTypeDef): Unit {
        var structTy: Option<Type> = None
        if (customTypeDef.GetCustomKind() == CustomDefKind.TYPE_EXTEND &&
            customTypeDef.GetType().getOrThrow().IsStruct()) {
            structTy = customTypeDef.GetType().getOrThrow()
        } else if (customTypeDef.GetCustomKind() == CustomDefKind.TYPE_STRUCT &&
            (customTypeDef as StructDef).getOrThrow().GetImplementedInterfacesNum() > 0) {
            structTy = customTypeDef.GetType().getOrThrow()
        }
        if (structTy.isNone()) {
            return
        }
        for (vtableIt in customTypeDef.GetDefVTable().GetTypeVTables()) {
            for (methodInfo in vtableIt.GetVirtualMethods()) {
                if (methodInfo.GetVirtualMethod().getOrThrow().IsPureAbstract()) {
                    continue
                }
                var rawFunc = methodInfo.GetVirtualMethod().getOrThrow()
                while (let Some(base) <- rawFunc.GetWrappedRawMethod()) {
                    rawFunc = base
                }
                if (!rawFunc.TestAttr(Attribute.MUT) ||
                    rawFunc.GetParentCustomTypeDef().getOrThrow().nodeId == customTypeDef.nodeId) {
                    continue
                }
                if (let Some(ex) <- (customTypeDef as ExtendDef)) {
                    if (let Some(extendedDef) <- ex.GetExtendedCustomTypeDef()) {
                        if (extendedDef.nodeId == rawFunc.GetParentCustomTypeDef().getOrThrow().nodeId) {
                            continue
                        }
                    }
                }
                CreateMutFuncWrapper(rawFunc, customTypeDef, vtableIt.GetSrcParentType().getOrThrow())
            }
        }
    }

    public func GetWrappers(): HashMap<String, Function> {
        return wrapperFuncs
    }
}

private func IsPossiblyOverflowOperator(info: VirtualMethodInfo): Bool {
    let name = info.GetMethodName()
    let paramTypes = info.GetMethodSigType().GetParamTypes()
    if (paramTypes.size == 1 && IsOverflowOperator(name)) {
        return CanBeIntegerType(paramTypes[0]) && CanBeIntegerType(info.GetMethodInstRetType())
    }
    if (paramTypes.size == 0 && name == "-") {
        return CanBeIntegerType(info.GetMethodInstRetType())
    }
    return false
}

private func IsBuiltinOverflowOperator(def: CustomTypeDef, info: VirtualMethodInfo): Bool {
    let defType = def.GetType().getOrThrow()
    let builtinDefType = (defType as BuiltinType) ?? return false
    if (!builtinDefType.IsInteger()) {
        return false
    }
    let name = info.GetMethodName()
    let paramTypes = info.GetMethodSigType().GetParamTypes()
    if (paramTypes.size == 1 && paramTypes[0].IsEqual(defType) && paramTypes[0].IsInteger() &&
        paramTypes[0].IsEqual(info.GetMethodInstRetType())) {
        return IsOverflowOperator(name)
    }
    if (paramTypes.size == 0 && info.GetMethodInstRetType().IsInteger()) {
        return name == "-"
    }
    return false
}

private func ToExprKind(name: String): ExprKind {
    if (name == "+") {
        return ExprKind.ADD
    }
    if (name == "-") {
        return ExprKind.SUB
    }
    if (name == "*") {
        return ExprKind.MUL
    }
    CJC_ASSERT(name == "/")
    return ExprKind.DIV
}

private class RewriteVtableInfo {
    public let ov: HashSet<Int64> = HashSet<Int64>()
    public init() {}
}

public class UpdateOperatorVTable {
    private let pkg: Package
    private let builder: CHIRBuilder
    private let interRewriteInfo: HashMap<Int64, RewriteVtableInfo> = HashMap<Int64, RewriteVtableInfo>()
    private let interRewriteDefs: ArrayList<ClassDef> = ArrayList<ClassDef>()
    private let cache: HashMap<String, Function> = HashMap<String, Function>()
    private let vtableUsers: HashMap<Int64, ArrayList<CustomTypeDef>> = HashMap<Int64, ArrayList<CustomTypeDef>>()

    public init(pkg: Package, builder: CHIRBuilder) {
        this.pkg = pkg
        this.builder = builder
    }

    private func CollectOverflowOperators(): Unit {
        for (def in pkg.GetClasses()) {
            if (def.IsInterface()) {
                CollectOverflowOperatorsOnInterface(def)
            }
        }
        for (def in pkg.GetImportedClasses()) {
            if (def.IsInterface()) {
                CollectOverflowOperatorsOnInterface(def)
            }
        }
    }

    private func AddRewriteInfo(def: ClassDef, index: Int64): Unit {
        if (!interRewriteInfo.contains(def.nodeId)) {
            interRewriteInfo[def.nodeId] = RewriteVtableInfo()
            interRewriteDefs.add(def)
        }
        interRewriteInfo[def.nodeId].ov.add(index)
    }

    private func CollectOverflowOperatorsOnInterface(def: ClassDef): Unit {
        for (vtableIt in def.GetDefVTable().GetTypeVTables()) {
            if (vtableIt.GetSrcParentType().getOrThrow().GetClassDef().nodeId != def.nodeId) {
                continue
            }
            var idx: Int64 = 0
            while (idx < vtableIt.GetMethodNum()) {
                let entry = vtableIt.GetVirtualMethods()[idx]
                if (IsPossiblyOverflowOperator(entry)) {
                    AddRewriteInfo(def, idx)
                }
                idx++
            }
        }
    }

    private func GenerateBuiltinOverflowOperatorFunc(name: String, ovf: OverflowStrategy, user: ExtendDef,
        isBinary: Bool): Function {
        let ty = (user.GetExtendedType().getOrThrow() as BuiltinType).getOrThrow()
        let mangledName = GenerateOverflowOperatorFuncMangleName(name, ovf, isBinary, ty)
        if (let Some(found) <- cache.get(mangledName)) {
            return found
        }
        let rawMangledName = OverflowStrategyPrefix(ovf) + name
        let packageName = user.GetPackageName()
        let paramTypes = ArrayList<Type>()
        paramTypes.add(ty)
        if (isBinary) {
            paramTypes.add(ty)
        }
        let funcType = builder.context.GetFuncTy(paramTypes, ty)
        let fn = builder.CreateFunction(funcType, mangledName, srcCodeIdentifier: rawMangledName,
            rawMangledName: "", packageName: packageName)
        cache[mangledName] = fn
        fn.EnableAttr(Attribute.NO_REFLECT_INFO)
        fn.EnableAttr(Attribute.NO_DEBUG_INFO)
        fn.EnableAttr(Attribute.COMPILER_ADD)
        fn.EnableAttr(Attribute.OPERATOR)
        fn.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        let body = builder.CreateBlockGroup(fn)
        fn.InitBody(body)
        let block = builder.CreateBlock(body)
        body.SetEntryBlock(block)
        let retValue = builder.CreateAllocate(builder.context.GetRefTy(ty), ty, block)
        fn.SetReturnValue(retValue.GetResult().getOrThrow())
        if (isBinary) {
            let p1 = builder.CreateParameter(ty, DebugLocation(), fn)
            let p2 = builder.CreateParameter(ty, DebugLocation(), fn)
            let add = builder.CreateBinaryExpression(ToExprKind(name), ty, p1, p2, block, overflowStrategy: ovf)
            builder.CreateStore(add.GetResult().getOrThrow(), retValue.GetResult().getOrThrow(), block)
        } else {
            let p1 = builder.CreateParameter(ty, DebugLocation(), fn)
            CJC_ASSERT(name == "-")
            let add = builder.CreateUnaryExpression(ExprKind.NEG, ty, p1, block, overflowStrategy: ovf)
            builder.CreateStore(add.GetResult().getOrThrow(), retValue.GetResult().getOrThrow(), block)
        }
        builder.CreateExit(None, block)
        fn.EnableAttr(Attribute.VIRTUAL)
        fn.EnableAttr(Attribute.FINAL)
        return fn
    }

    private func RewriteOneVtableEntry(infType: ClassType, user: CustomTypeDef, methodInfo: VirtualMethodInfo,
        index: Int64): Unit {
        if (IsBuiltinOverflowOperator(user, methodInfo)) {
            let extDef = (user as ExtendDef).getOrThrow()
            var idx: Int64 = 0
            while (idx < SPLIT_OPERATOR_NAME_PREFIX.size) {
                let newName = SPLIT_OPERATOR_NAME_PREFIX[idx] + methodInfo.GetMethodName()
                let ovfFunc = GenerateBuiltinOverflowOperatorFunc(methodInfo.GetMethodName(), OVF_STRATEGIES[idx],
                    extDef, methodInfo.GetMethodSigType().GetNumOfParams() == 1)
                extDef.AddMethod(ovfFunc)
                if (idx == SPLIT_OPERATOR_NAME_PREFIX.size - 1) {
                    let vt = user.GetDefVTable().GetExpectedTypeVTable(infType).GetVirtualMethods()[index]
                    CJC_ASSERT(vt.GetMethodName() == methodInfo.GetMethodName())
                    CJC_ASSERT(vt.GetMethodSigType().IsEqual(methodInfo.GetMethodSigType()))
                    user.UpdateVtableItem(infType, index, ovfFunc, extDef.GetExtendedType().getOrThrow(), newName)
                } else {
                    let newFuncInfo = CloneVirtualMethodInfo(methodInfo)
                    newFuncInfo.SetFuncName(newName)
                    newFuncInfo.SetVirtualMethod(ovfFunc)
                    newFuncInfo.SetInstParentType(extDef.GetExtendedType().getOrThrow())
                    newFuncInfo.SetOriginalFuncType(ovfFunc.GetFuncType().getOrThrow())
                    user.AddVtableItem(infType, newFuncInfo)
                }
                idx++
            }
        } else {
            var idx: Int64 = 0
            while (idx < SPLIT_OPERATOR_NAME_PREFIX.size) {
                let newName = SPLIT_OPERATOR_NAME_PREFIX[idx] + methodInfo.GetMethodName()
                if (idx == SPLIT_OPERATOR_NAME_PREFIX.size - 1) {
                    let vt = user.GetDefVTable().GetExpectedTypeVTable(infType).GetVirtualMethods()[index]
                    CJC_ASSERT(vt.GetMethodName() == methodInfo.GetMethodName())
                    CJC_ASSERT(vt.GetMethodSigType().IsEqual(methodInfo.GetMethodSigType()))
                    user.UpdateVtableItem(infType, index, methodInfo.GetVirtualMethod(), None, newName)
                } else {
                    let newMethodInfo = CloneVirtualMethodInfo(methodInfo)
                    newMethodInfo.SetFuncName(newName)
                    user.AddVtableItem(infType, newMethodInfo)
                }
                idx++
            }
        }
    }

    private func RewriteVtableEntryRec(inf: ClassDef, user: CustomTypeDef, info: RewriteVtableInfo): Unit {
        for (vtableIt in user.GetDefVTable().GetTypeVTables()) {
            if (vtableIt.GetSrcParentType().getOrThrow().GetClassDef().nodeId != inf.nodeId) {
                continue
            }
            let indices = ArrayList<Int64>()
            for (idx in info.ov) {
                indices.add(idx)
            }
            sort(indices, by: { left: Int64, right: Int64 =>
                if (left < right) { Ordering.LT } else if (left > right) { Ordering.GT } else { Ordering.EQ }
            })
            for (idx in indices) {
                let funcInfo = CloneVirtualMethodInfo(vtableIt.GetVirtualMethods()[idx])
                RewriteOneVtableEntry(vtableIt.GetSrcParentType().getOrThrow(), user, funcInfo, idx)
            }
        }
    }

    private func RewriteVtable(): Unit {
        sort(interRewriteDefs, by: { left: ClassDef, right: ClassDef =>
            if (left.GetIdentifier() < right.GetIdentifier()) {
                Ordering.LT
            } else if (left.GetIdentifier() > right.GetIdentifier()) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        })
        for (inf in interRewriteDefs) {
            let info = interRewriteInfo[inf.nodeId]
            if (let Some(users) <- vtableUsers.get(inf.nodeId)) {
                for (user in users) {
                    RewriteVtableEntryRec(inf, user, info)
                }
            }
        }
    }

    private func CollectVTableUsers(): Unit {
        for (def in pkg.GetAllCustomTypeDef()) {
            if (def.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            for (vtableIt in def.GetDefVTable().GetTypeVTables()) {
                let parentDef = vtableIt.GetSrcParentType().getOrThrow().GetClassDef()
                if (!vtableUsers.contains(parentDef.nodeId)) {
                    vtableUsers[parentDef.nodeId] = ArrayList<CustomTypeDef>()
                }
                var found = false
                for (user in vtableUsers[parentDef.nodeId]) {
                    if (user.nodeId == def.nodeId) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    vtableUsers[parentDef.nodeId].add(def)
                }
            }
        }
    }

    public func Update(): Unit {
        CollectOverflowOperators()
        CollectVTableUsers()
        RewriteVtable()
    }
}

private func CalleeIsMutFuncFromParent(thisType: Option<Type>, callee: Option<Function>,
    topLevelFunc: Function): Bool {
    if (thisType.isNone() || !thisType.getOrThrow().StripAllRefs().IsStruct()) {
        return false
    }
    if (callee.isNone() || !callee.getOrThrow().TestAttr(Attribute.MUT)) {
        return false
    }
    if (!callee.getOrThrow().GetParentCustomTypeOrExtendedType().getOrThrow().IsClass()) {
        return false
    }
    return topLevelFunc.GetWrappedRawMethod().isNone()
}

public class GenerateVTable {
    private let pkg: Package
    private let candidateDefs: ArrayList<CustomTypeDef>
    private let builder: CHIRBuilder
    private let opts: GlobalOptions
    private let passName: String
    private var mutFuncWrappers: HashMap<String, Function> = HashMap<String, Function>()

    public init(pkg: Package, defs: ArrayList<CustomTypeDef>, builder: CHIRBuilder, opts: GlobalOptions,
        passName: String) {
        this.pkg = pkg
        candidateDefs = defs
        this.builder = builder
        this.opts = opts
        this.passName = passName
    }

    public func CreateVTable(): Unit {
        try (recorder = ProfileRecorder(passName, "CreateVTable")) {
            let threadNum = opts.GetJobs()
            if (threadNum == 1u64) {
                let vtableGenerator = VTableGenerator(builder)
                for (customDef in candidateDefs) {
                    vtableGenerator.GenerateVTable(customDef)
                }
            } else {
                let taskQueue = TaskQueue(Int64(threadNum))
                let vtableGeneratorList = ArrayList<VTableGenerator>()
                for (customDef in candidateDefs) {
                    let vtableGenerator = VTableGenerator(builder)
                    vtableGeneratorList.add(vtableGenerator)
                    { generatorPtr: VTableGenerator, customDefPtr: CustomTypeDef =>
                        taskQueue.AddTask<Unit>({ =>
                            generatorPtr.GenerateVTable(customDefPtr)
                        })
                    }(vtableGenerator, customDef)
                }
                taskQueue.RunAndWaitForAllTasksCompleted()
            }
        }
    }

    public func UpdateOperatorVirFunc(): Unit {
        try (recorder = ProfileRecorder(passName, "UpdateOperatorVirFunc")) {
            UpdateOperatorVTable(pkg, builder).Update()
        }
    }

    public func CreateVirtualFuncWrapper(kind: IncreKind, increCachedInfo: CompilationCache,
        curVirtFuncWrapDep: VirtualWrapperDepMap, delVirtFuncWrapForIncr: VirtualWrapperDepMap): Unit {
        try (recorder = ProfileRecorder(passName, "CreateVirtualFuncWrapper")) {
            let targetIsWin = opts.target.os == OSType.WINDOWS
            let tempKind = if (opts.enIncrementalCompilation) { kind } else { IncreKind.INVALID }
            let wrapper = WrapVirtualFunc(builder, increCachedInfo, tempKind, targetIsWin)
            for (customDef in candidateDefs) {
                if (customDef.TestAttr(Attribute.SKIP_ANALYSIS)) {
                    continue
                }
                wrapper.CheckAndWrap(customDef)
            }
            curVirtFuncWrapDep.clear()
            for ((key, value) in wrapper.GetCurVirtFuncWrapDep()) {
                curVirtFuncWrapDep[key] = value
            }
            delVirtFuncWrapForIncr.clear()
            for ((key, value) in wrapper.GetDelVirtFuncWrapForIncr()) {
                delVirtFuncWrapForIncr[key] = value
            }
        }
    }

    public func SetSrcFuncType(): Unit {
        try (recorder = ProfileRecorder(passName, "SetSrcFuncType")) {
            for (customTypeDef in candidateDefs) {
                let vtable = customTypeDef.GetDefVTable().GetTypeVTables()
                for (it in vtable) {
                    var idx: Int64 = 0
                    while (idx < it.GetMethodNum()) {
                        let funcInfo = it.GetVirtualMethods()[idx]
                        let instance = funcInfo.GetVirtualMethod().getOrThrow()
                        if (!instance.IsPureAbstract()) {
                            let parentDef = it.GetSrcParentType().getOrThrow().GetClassDef()
                            let parentType = (parentDef.GetType().getOrThrow() as ClassType).getOrThrow()
                            let parentVtable = parentDef.GetDefVTable().GetExpectedTypeVTable(parentType)
                            CJC_ASSERT(!parentVtable.IsEmpty())
                            CJC_ASSERT(idx < parentVtable.GetMethodNum())
                            instance.SetOverrideSrcFuncType(parentVtable.GetVirtualMethods()[idx].GetOriginalFuncType())
                        }
                        idx++
                    }
                }
            }
        }
    }

    public func CreateMutFuncWrapper(): Unit {
        try (recorder = ProfileRecorder(passName, "CreateMutFuncWrapper")) {
            let wrapper = WrapMutFunc(builder)
            for (customDef in candidateDefs) {
                if (customDef.TestAttr(Attribute.SKIP_ANALYSIS)) {
                    continue
                }
                wrapper.Run(customDef)
            }
            mutFuncWrappers = wrapper.GetWrappers()
        }
    }

    private func GetMutFuncWrapper(thisType: Type, args: ArrayList<Value>, instTypeArgs: ArrayList<Type>,
        retType: Type, callee: Function): Function {
        let paramTypes = ArrayList<Type>()
        for (arg in args) {
            paramTypes.add(arg.GetType().getOrThrow())
        }
        if (!callee.TestAttr(Attribute.STATIC)) {
            paramTypes.remove(at: 0)
        }
        let funcCallType = FuncCallType(builder.context.GetFuncTy(paramTypes, retType),
            funcName: callee.GetSrcCodeIdentifier(), genericTypeArgs: instTypeArgs)
        let vtableRes = GetFuncIndexInVTable(thisType.StripAllRefs(), funcCallType, builder)
        CJC_ASSERT(vtableRes.size == 1)
        let wrapperName = GenerateVirtualFuncMangleName(callee, vtableRes[0].originalDef.getOrThrow(),
            vtableRes[0].halfInstSrcParentType.getOrThrow(), false)
        let wrapperFunc = mutFuncWrappers.get(wrapperName).getOrThrow()
        return wrapperFunc
    }

    private func VisitExpression(expr: Expression): Unit {
        if (let Some(dyExpr) <- (expr as DynamicDispatch)) {
            dyExpr.SetVirtualMethodOffset(dyExpr.GetVirtualMethodOffset(builder))
        } else if (let Some(dyExprE) <- (expr as DynamicDispatchWithException)) {
            dyExprE.SetVirtualMethodOffset(dyExprE.GetVirtualMethodOffset(builder))
        } else if (let Some(apply) <- (expr as Apply)) {
            let callee = apply.GetCallee() as Function
            if (CalleeIsMutFuncFromParent(apply.GetThisType(), callee, expr.GetTopLevelFunc().getOrThrow())) {
                let wrapperFunc = GetMutFuncWrapper(apply.GetThisType().getOrThrow(), apply.GetArgs(),
                    apply.GetInstantiatedTypeArgs(), apply.GetResult().getOrThrow().GetType().getOrThrow(),
                    callee.getOrThrow())
                apply.ReplaceOperand(callee.getOrThrow(), wrapperFunc)
            }
        } else if (let Some(applyE) <- (expr as ApplyWithException)) {
            let callee = applyE.GetCallee() as Function
            if (CalleeIsMutFuncFromParent(applyE.GetThisType(), callee, expr.GetTopLevelFunc().getOrThrow())) {
                let wrapperFunc = GetMutFuncWrapper(applyE.GetThisType().getOrThrow(), applyE.GetArgs(),
                    applyE.GetInstantiatedTypeArgs(), applyE.GetResult().getOrThrow().GetType().getOrThrow(),
                    callee.getOrThrow())
                applyE.ReplaceOperand(callee.getOrThrow(), wrapperFunc)
            }
        }
        for (group in expr.GetBlockGroups()) {
            VisitBlockGroup(group)
        }
    }

    private func VisitBlockGroup(group: BlockGroup): Unit {
        for (block in group.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                VisitExpression(expr)
            }
        }
    }

    public func UpdateFuncCall(): Unit {
        try (recorder = ProfileRecorder(passName, "UpdateFuncCall")) {
            for (fn in pkg.GetGlobalFuncsWithBody()) {
                if (let Some(body) <- fn.GetBody()) {
                    VisitBlockGroup(body)
                }
            }
        }
    }
}
