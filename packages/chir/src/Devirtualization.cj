package cjcj::chir

import std.collection.*
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK}

// C++ Devirtualization.cpp:19-31.
private func GetEntryBlock(oldBG: BlockGroup, blocks: ArrayList<Block>): Block {
    let oldBlocks = oldBG.GetBlocks()
    CJC_ASSERT(oldBlocks.size == blocks.size)
    CJC_ASSERT(!blocks.isEmpty())
    var index: Int64 = 0
    while (index < oldBlocks.size) {
        if (oldBlocks[index] == oldBG.GetEntryBlock().getOrThrow()) {
            return blocks[index]
        }
        index++
    }
    CJC_ABORT()
    return blocks[0]
}

// C++ Devirtualization.h:28-34.
public class RewriteInfo {
    public let invoke: Invoke
    public let realCallee: Function
    public let thisType: Type
    public let typeArgs: ArrayList<Type>
    public var newApply: Option<Apply> = None

    public init(invoke: Invoke, realCallee: Function, thisType: Type, typeArgs: ArrayList<Type>) {
        this.invoke = invoke
        this.realCallee = realCallee
        this.thisType = thisType
        this.typeArgs = typeArgs
    }
}

// C++ Devirtualization.h:68-72.
public class FuncSig {
    public let name: String
    public let types: ArrayList<Type>
    public let typeArgs: ArrayList<Type>

    public init(name: String, types: ArrayList<Type>, typeArgs: ArrayList<Type>) {
        this.name = name
        this.types = types
        this.typeArgs = typeArgs
    }
}

// C++ Devirtualization.cpp:113-120.
private class BuiltinOpInfo {
    let funcInfo: FuncInfo
    let targetExprKind: ExprKind
    let operandsNum: Int64

    init(info: FuncInfo, exprKind: ExprKind, operandsNum: Int64) {
        funcInfo = info
        targetExprKind = exprKind
        this.operandsNum = operandsNum
    }
}

// C++ Devirtualization.cpp:122-130.
private let COMPARABLE_FUNC_LISTS: Array<BuiltinOpInfo> = [
    BuiltinOpInfo(FuncInfo(">", NOT_CARE, [NOT_CARE], ANY_TYPE, "std.core"), ExprKind.GT, 2),
    BuiltinOpInfo(FuncInfo("<", NOT_CARE, [NOT_CARE], ANY_TYPE, "std.core"), ExprKind.LT, 2),
    BuiltinOpInfo(FuncInfo(">=", NOT_CARE, [NOT_CARE], ANY_TYPE, "std.core"), ExprKind.GE, 2),
    BuiltinOpInfo(FuncInfo("<=", NOT_CARE, [NOT_CARE], ANY_TYPE, "std.core"), ExprKind.LE, 2),
    BuiltinOpInfo(FuncInfo("==", NOT_CARE, [NOT_CARE], ANY_TYPE, "std.core"), ExprKind.EQUAL, 2),
    BuiltinOpInfo(FuncInfo("!=", NOT_CARE, [NOT_CARE], ANY_TYPE, "std.core"), ExprKind.NOTEQUAL, 2),
    BuiltinOpInfo(FuncInfo("next", NOT_CARE, [NOT_CARE], ANY_TYPE, "std.core"), ExprKind.APPLY, 2)
]

// C++ Devirtualization.cpp:132-142.
private func BuiltinOpCreateNewApply(builder: CHIRBuilder, oriInvoke: Invoke, fn: Function,
    thisValue: Value, args: ArrayList<Value>): Apply {
    let applyArgs = ArrayList<Value>()
    applyArgs.add(thisValue)
    applyArgs.add(all: args)
    let thisType = builder.context.GetRefTy(thisValue.GetType().getOrThrow())
    return builder.CreateApply(oriInvoke.GetResultType().getOrThrow(), fn,
        FuncCallContext(args: applyArgs, thisType: Some(thisType)), oriInvoke.GetParentBlock().getOrThrow())
}

// C++ Devirtualization.cpp:144-152.
private func BuiltinOpCreateNewBinary(builder: CHIRBuilder, oriInvoke: Invoke, kind: ExprKind,
    thisValue: Value, args: ArrayList<Value>): BinaryExpression {
    CJC_ASSERT(args.size == 1)
    let binary = builder.CreateBinaryExpression(kind, oriInvoke.GetResultType().getOrThrow(), thisValue, args[0],
        oriInvoke.GetParentBlock().getOrThrow())
    binary.SetDebugLocation(oriInvoke.GetDebugLocation())
    return binary
}

// C++ Devirtualization.cpp:283-301.
private func CreateInstFuncMangleName(oriIdentifer: String, apply: Apply, builder: CHIRBuilder): String {
    let genericTypes = ArrayList<Type>()
    let fn = apply.GetCallee().AsFunction().getOrThrow()
    if (let Some(customDef) <- fn.GetParentCustomTypeDef()) {
        if (customDef.IsGenericDef()) {
            var funcInCustomType = GetInstParentCustomTyOfCallee(apply.GetCallee(), apply.GetArgs(),
                apply.GetThisType(), builder).getOrThrow()
            while (funcInCustomType.IsRef()) {
                funcInCustomType = (funcInCustomType as RefType).getOrThrow().GetBaseType()
            }
            genericTypes.add(all: funcInCustomType.GetTypeArgs())
        }
    }
    let funcArgs = apply.GetInstantiatedTypeArgs()
    if (!funcArgs.isEmpty()) {
        genericTypes.add(all: funcArgs)
    }
    return GenerateInstantiateFuncMangleName(oriIdentifer, genericTypes)
}

// C++ Devirtualization.cpp:373-380. The C++ parameter is const, so this traversal intentionally does not mutate it.
private func BuildOrphanTypeReplaceTable(mayBeGeneric: Type, replaceTable: HashMap<GenericType, Type>): Unit {
    for (genericTypeArg in mayBeGeneric.GetTypeArgs()) {
        BuildOrphanTypeReplaceTable(genericTypeArg, replaceTable)
    }
}

// C++ Devirtualization.cpp:382-433.
private func FindFunctionInVtable(parentTy: ClassType, infos: ArrayList<VirtualMethodInfo>, method: FuncSig,
    builder: CHIRBuilder): Option<Function> {
    let parentReplaceTable = HashMap<GenericType, Type>()
    let paramTypes = method.types.clone()
    paramTypes.remove(at: 0)
    if (!parentTy.GetTypeArgs().isEmpty()) {
        let instParentTypeArgs = parentTy.GetTypeArgs()
        let genericParentTypeArgs = parentTy.GetCustomTypeDef().GetGenericTypeParams()
        var index: Int64 = 0
        while (index < genericParentTypeArgs.size) {
            parentReplaceTable[genericParentTypeArgs[index]] = instParentTypeArgs[index]
            index++
        }
    }
    for (info in infos) {
        if (info.GetMethodName() != method.name) {
            continue
        }
        let sigParamTys = info.GetMethodSigType().GetParamTypes()
        if (sigParamTys.size != paramTypes.size) {
            continue
        }
        if (info.GetGenericTypeParams().size != method.typeArgs.size) {
            continue
        }
        var isSigSame = true
        let freeGenericReplaceTable = HashMap<GenericType, Type>()
        var index: Int64 = 0
        while (index < sigParamTys.size) {
            BuildOrphanTypeReplaceTable(sigParamTys[index], freeGenericReplaceTable)
            BuildOrphanTypeReplaceTable(paramTypes[index], freeGenericReplaceTable)
            index++
        }
        let methodGenerics = info.GetGenericTypeParams()
        index = 0
        while (index < methodGenerics.size) {
            freeGenericReplaceTable[methodGenerics[index]] = method.typeArgs[index]
            index++
        }
        index = 0
        while (index < paramTypes.size) {
            if (isSigSame) {
                let lhs = ReplaceRawGenericArgType(sigParamTys[index], freeGenericReplaceTable, builder)
                var rhs = ReplaceRawGenericArgType(paramTypes[index], parentReplaceTable, builder)
                rhs = ReplaceRawGenericArgType(rhs, freeGenericReplaceTable, builder)
                isSigSame = lhs == rhs
            } else {
                break
            }
            index++
        }
        if (!isSigSame) {
            continue
        }
        let virtualMethod = info.GetVirtualMethod() ?? return None
        return if (virtualMethod.IsPureAbstract()) { None } else { Some(virtualMethod) }
    }
    return None
}

// C++ Devirtualization.h:18-115 and Devirtualization.cpp:33-659.
public class Devirtualization {
    private let analysisWrapper: AnalysisWrapper<TypeAnalysis, TypeDomain>
    private let devirtFuncInfo: DevirtualizationInfo
    private let rewriteInfos: ArrayList<RewriteInfo> = ArrayList<RewriteInfo>()
    private let frozenInstFuns: ArrayList<Function> = ArrayList<Function>()
    private let frozenStates: HashMap<Function, Results<TypeDomain>> = HashMap<Function, Results<TypeDomain>>()
    private let frozenInstFuncMap: HashMap<String, Function> = HashMap<String, Function>()

    public init(typeAnalysisWrapper: AnalysisWrapper<TypeAnalysis, TypeDomain>,
        devirtFuncInfo: DevirtualizationInfo) {
        analysisWrapper = typeAnalysisWrapper
        this.devirtFuncInfo = devirtFuncInfo
    }

    // C++ Devirtualization.cpp:39-47.
    public func RunOnFuncs(funcs: ArrayList<Function>, builder: CHIRBuilder, isDebug: Bool): Unit {
        rewriteInfos.clear()
        for (fn in funcs) {
            RunOnFunc(fn, builder)
        }
        RewriteToApply(builder, rewriteInfos, isDebug)
        InstantiateFuncIfPossible(builder, rewriteInfos)
    }

    // C++ Devirtualization.cpp:49-110.
    private func RunOnFunc(fn: Function, builder: CHIRBuilder): Unit {
        var result = analysisWrapper.CheckFuncResult(fn)
        if (result.isNone()) {
            result = frozenStates.get(fn)
        }
        let analysisResult = result ?? return
        var visibleGenericTypes: Option<HashSet<GenericType>> = None
        let actionBeforeVisitExpr = { state: TypeDomain, expr: Expression, _: Int64 =>
            if (expr.GetExprKind() != ExprKind.INVOKE) {
                return
            }
            let invoke = (expr as Invoke).getOrThrow()
            let invokeAbsObject = state.CheckAbstractObjectRefBy(invoke.GetObject()) ?? return
            let resVal = state.CheckAbstractValue(invokeAbsObject) ?? return
            let paramTys = ArrayList<Type>()
            for (param in invoke.GetOperands()) {
                paramTys.add(param.GetType().getOrThrow())
            }
            let found = FindRealCallee(builder, resVal,
                FuncSig(invoke.GetMethodName(), paramTys, invoke.GetInstantiatedTypeArgs()))
            let realCallee = found[0] ?? return
            let thisType = found[1].getOrThrow()
            if (thisType.IsGenericRelated()) {
                if (visibleGenericTypes.isNone()) {
                    let types = GetVisiableGenericTypes(fn)
                    let visible = HashSet<GenericType>()
                    for (ty in types) {
                        visible.add(ty)
                    }
                    visibleGenericTypes = Some(visible)
                }
                if (!CheckAllGenericTypeVisible(thisType, visibleGenericTypes.getOrThrow())) {
                    return
                }
            }
            rewriteInfos.add(RewriteInfo(invoke, realCallee, thisType, invoke.GetInstantiatedTypeArgs()))
        }
        let actionAfterVisitExpr = { _: TypeDomain, _: Expression, _: Int64 => }
        let actionOnTerminator = { _: TypeDomain, _: Terminator, _: Option<Block> => }
        analysisResult.VisitWith(actionBeforeVisitExpr, actionAfterVisitExpr, actionOnTerminator)
    }

    // C++ Devirtualization.cpp:155-216.
    private static func RewriteToBuiltinOp(builder: CHIRBuilder, info: RewriteInfo, isDebug: Bool): Bool {
        let invoke = info.invoke
        let fn = info.realCallee.GetWrappedRawMethod() ?? info.realCallee
        var targetExprKind = ExprKind.INVALID
        var operandsNum: Int64 = 0
        for (item in COMPARABLE_FUNC_LISTS) {
            if (IsExpectedFunction(fn, item.funcInfo)) {
                targetExprKind = item.targetExprKind
                operandsNum = item.operandsNum
            }
        }
        let args = invoke.GetArgs()
        args.remove(at: 0)
        if (targetExprKind == ExprKind.INVALID || args.size != operandsNum - 1) {
            return false
        }
        for (arg in args) {
            if (!arg.GetType().getOrThrow().IsPrimitive()) {
                return false
            }
        }
        var thisValue = invoke.GetObject()
        let castExprs = ArrayList<Expression>()
        if (thisValue.IsLocalVar() && !thisValue.GetType().getOrThrow().IsPrimitive()) {
            var tempVar = thisValue.AsLocalVar()
            while (let Some(localVar) <- tempVar) {
                let castExpr = localVar.GetExpr().getOrThrow()
                if (castExpr.GetExprKind() != ExprKind.BOX && castExpr.GetExprKind() != ExprKind.TYPECAST) {
                    break
                }
                castExprs.add(castExpr)
                thisValue = castExpr.GetOperand(0)
                tempVar = thisValue.AsLocalVar()
            }
        }
        if (!thisValue.GetType().getOrThrow().IsPrimitive()) {
            return false
        }
        let op: Expression = if (targetExprKind == ExprKind.APPLY) {
            BuiltinOpCreateNewApply(builder, invoke, fn, thisValue, args)
        } else {
            BuiltinOpCreateNewBinary(builder, invoke, targetExprKind, thisValue, args)
        }
        invoke.ReplaceWith(op)
        for (castExpr in castExprs) {
            if (castExpr.GetResult().getOrThrow().GetUsers().isEmpty()) {
                castExpr.RemoveSelfFromBlock()
            }
        }
        if (isDebug) {
            let callName = if (targetExprKind == ExprKind.APPLY) {
                fn.GetSrcCodeIdentifier()
            } else {
                op.GetExprKindName()
            }
            println("[Devirtualization] The function call to " + invoke.GetMethodName() +
                ToPosInfo(invoke.GetDebugLocation()) + " was optimized to builtin op " + callName + ".")
        }
        return true
    }

    // C++ Devirtualization.cpp:218-271.
    private static func RewriteToApply(builder: CHIRBuilder, rewriteInfos: ArrayList<RewriteInfo>,
        isDebug: Bool): Unit {
        var index = rewriteInfos.size - 1
        while (index >= 0) {
            let rewriteInfo = rewriteInfos[index]
            if (RewriteToBuiltinOp(builder, rewriteInfo, isDebug)) {
                index--
                continue
            }
            let invoke = rewriteInfo.invoke
            let parent = invoke.GetParentBlock().getOrThrow()
            var thisType: Type = builder.context.GetRefTy(rewriteInfo.thisType)
            var realFunc = rewriteInfo.realCallee
            if ((rewriteInfo.thisType.IsStruct() || rewriteInfo.thisType.IsEnum()) &&
                rewriteInfo.realCallee.GetWrappedRawMethod().isSome()) {
                thisType = rewriteInfo.thisType
                let isMutFunc = realFunc.TestAttr(Attribute.MUT) || realFunc.IsConstructor() ||
                    realFunc.IsInstanceVarInit()
                if (isMutFunc) {
                    thisType = builder.context.GetRefTy(thisType)
                }
                realFunc = rewriteInfo.realCallee.GetWrappedRawMethod().getOrThrow()
            }
            let args = invoke.GetOperands()
            let thisDerefType = thisType.StripAllRefs()
            var instThisType = GetInstParentType(thisDerefType,
                realFunc.GetFuncType().getOrThrow().GetParamTypes()[0].StripAllRefs(), builder)
            if (thisDerefType.IsClassOrArray() || realFunc.TestAttr(Attribute.MUT)) {
                instThisType = builder.context.GetRefTy(instThisType)
            }
            if (rewriteInfo.thisType.IsBuiltinType()) {
                instThisType = builder.context.GetRefTy(builder.context.GetAnyTy().getOrThrow())
            }
            let typecastRes = TypeCastOrBoxIfNeeded(args[0], instThisType, builder, parent, INVALID_LOCATION)
            if (typecastRes != args[0]) {
                typecastRes.AsLocalVar().getOrThrow().GetExpr().getOrThrow().MoveBefore(invoke)
                args[0] = typecastRes
            }
            let apply = builder.CreateApply(invoke.GetResultType().getOrThrow(), realFunc,
                FuncCallContext(args: args, instTypeArgs: rewriteInfo.typeArgs, thisType: Some(thisType)), parent)
            apply.SetDebugLocation(invoke.GetDebugLocation())
            rewriteInfo.newApply = Some(apply)
            invoke.ReplaceWith(apply)
            invoke.GetResult().getOrThrow().ReplaceWith(apply.GetResult().getOrThrow(),
                parent.GetParentBlockGroup())
            if (isDebug) {
                println("[Devirtualization] The function call to " + invoke.GetMethodName() +
                    ToPosInfo(invoke.GetDebugLocation()) + " was optimized.")
            }
            index--
        }
    }

    // C++ Devirtualization.cpp:273-276.
    public func GetFrozenInstFuns(): ArrayList<Function> {
        return frozenInstFuns
    }

    // C++ Devirtualization.cpp:278-281.
    public func AppendFrozenFuncState(fn: Function, analysisRes: Results<TypeDomain>): Unit {
        frozenStates[fn] = analysisRes
    }

    // C++ Devirtualization.cpp:303-370.
    private func InstantiateFuncIfPossible(builder: CHIRBuilder, rewriteInfoList: ArrayList<RewriteInfo>): Unit {
        var rewriteIndex = rewriteInfoList.size - 1
        while (rewriteIndex >= 0) {
            let rewriteInfo = rewriteInfoList[rewriteIndex]
            let callee = rewriteInfo.realCallee
            if (!callee.IsFuncWithBody() || !callee.IsInGenericContext() || callee.GetWrappedRawMethod().isSome()) {
                rewriteIndex--
                continue
            }
            let apply = rewriteInfo.newApply.getOrThrow()
            let parameterType = ArrayList<Type>()
            for (param in apply.GetArgs()) {
                parameterType.add(param.GetType().getOrThrow())
            }
            let retType = apply.GetResultType().getOrThrow()
            let instFuncType = builder.context.GetFuncTy(parameterType, retType)
            if (instFuncType.IsGenericRelated()) {
                rewriteIndex--
                continue
            }
            let newId = CreateInstFuncMangleName(callee.GetIdentifierWithoutPrefix(), apply, builder)
            var newFunc: Function
            if (let Some(found) <- frozenInstFuncMap.get(newId)) {
                newFunc = found
            } else {
                newFunc = builder.CreateFunction(instFuncType, newId,
                    srcCodeIdentifier: callee.GetSrcCodeIdentifier(), rawMangledName: callee.GetRawMangledName(),
                    packageName: callee.GetPackageName())
                newFunc.SetDebugLocation(callee.GetDebugLocation())
                newFunc.AppendAttributeInfo(callee.GetAttributeInfo())
                newFunc.DisableAttr(Attribute.GENERIC)
                if (!apply.GetInstantiatedTypeArgs().isEmpty()) {
                    newFunc.EnableAttr(Attribute.GENERIC_INSTANTIATED)
                }
                newFunc.SetLinkTypeInfo(BasicLinkage.INTERNAL)
                newFunc.SetGenericDecl(callee)
                let oriBlockGroup = callee.GetBody().getOrThrow()
                let copy = BlockGroupCopyHelper(builder)
                copy.GetInstMapFromApply(apply, newBodyOuterFunction: Some(newFunc))
                let newBody = builder.CreateBlockGroup(newFunc)
                newFunc.InitBody(newBody)
                let cloned = copy.CloneBlockGroup(oriBlockGroup, newBody)
                let newBlocks = cloned[0]
                let newBlockGroupRetValue = cloned[1].getOrThrow()
                newBody.SetEntryBlock(GetEntryBlock(oriBlockGroup, newBlocks))
                newFunc.SetReturnValue(newBlockGroupRetValue)
                CJC_ASSERT(parameterType.size == callee.GetParams().size)
                let paramMap = HashMap<Int64, Value>()
                var paramIndex: Int64 = 0
                while (paramIndex < parameterType.size) {
                    let arg = builder.CreateParameter(parameterType[paramIndex],
                        callee.GetParam(paramIndex).GetDebugLocation(), newFunc)
                    paramMap[callee.GetParam(paramIndex).nodeId] = arg
                    paramIndex++
                }
                BlockGroupCopyHelper.ReplaceExprOperands(newBlocks, paramMap)
                FixCastProblemAfterInst(newBlocks, builder)
                newFunc.SetReturnValue(newBlockGroupRetValue)
                frozenInstFuns.add(newFunc)
                frozenInstFuncMap[newId] = newFunc
            }
            let instApply = builder.CreateApply(retType, newFunc, FuncCallContext(args: apply.GetArgs()),
                apply.GetParentBlock().getOrThrow())
            instApply.SetDebugLocation(apply.GetDebugLocation())
            apply.ReplaceWith(instApply)
            rewriteIndex--
        }
    }

    // C++ Devirtualization.cpp:436-456.
    private func IsInstantiationOf(builder: CHIRBuilder, generic: GenericType, instantiated: Type): Bool {
        if (generic.GetUpperBounds().isEmpty()) {
            return true
        }
        let possibleParentTys = HashSet<Type>()
        for (def in devirtFuncInfo.defsMap.get(instantiated) ?? ArrayList<CustomTypeDef>()) {
            for (parentTy in def.GetSuperTypesInCurDef()) {
                possibleParentTys.add(all: parentTy.GetSuperTypesRecusively(builder))
            }
        }
        for (upperBound in generic.GetUpperBounds()) {
            if (!possibleParentTys.contains(upperBound)) {
                return false
            }
        }
        return true
    }

    // C++ Devirtualization.cpp:458-490.
    private func IsValidSubType(builder: CHIRBuilder, expected: Type, specific: Type,
        replaceTable: HashMap<GenericType, Type>): Bool {
        if (expected.GetTypeKind() != specific.GetTypeKind() && !expected.IsGeneric()) {
            return false
        }
        if (expected.IsGeneric()) {
            let generic = (expected as GenericType).getOrThrow()
            if (IsInstantiationOf(builder, generic, specific)) {
                replaceTable[generic] = specific
                return true
            }
            return false
        }
        if (expected.IsNominal()) {
            let specificCustomTy = (specific as CustomType).getOrThrow()
            if (!specificCustomTy.IsEqualOrSubTypeOf(expected, builder)) {
                return false
            }
        }
        let argsOfExpected = expected.GetTypeArgs()
        let argsOfSpecific = specific.GetTypeArgs()
        if (argsOfExpected.size != argsOfSpecific.size) {
            return false
        }
        var index: Int64 = 0
        while (index < argsOfExpected.size) {
            if (!IsValidSubType(builder, argsOfExpected[index].StripAllRefs(),
                argsOfSpecific[index].StripAllRefs(), replaceTable)) {
                return false
            }
            index++
        }
        return true
    }

    // C++ Devirtualization.cpp:492-530.
    private func FindRealCallee(builder: CHIRBuilder, typeState: TypeValue,
        method: FuncSig): (Option<Function>, Option<Type>) {
        let typeStateKind = typeState.GetTypeKind()
        let specificType = typeState.GetSpecificType()
        if (!specificType.IsClass() || typeStateKind == DevirtualTyKind.EXACTLY) {
            let extendsOrImplements = if (let Some(customType) <- (specificType as CustomType)) {
                devirtFuncInfo.defsMap.get(customType.GetCustomTypeDef().GetType().getOrThrow()) ??
                    ArrayList<CustomTypeDef>()
            } else {
                devirtFuncInfo.defsMap.get(specificType) ?? ArrayList<CustomTypeDef>()
            }
            var target: Option<Function> = None
            for (def in extendsOrImplements) {
                let mapping = def.GetType().getOrThrow().CalculateGenericTyMapping(specificType)
                if (!mapping[0]) {
                    continue
                }
                let paramTypes = method.types.clone()
                paramTypes.remove(at: 0)
                let funcType = builder.context.GetFuncTy(paramTypes, builder.context.GetUnitTy())
                let funcCallType = FuncCallType(funcType, funcName: method.name, genericTypeArgs: method.typeArgs)
                let result = def.GetFuncIndexInVTable(funcCallType, mapping[1], builder)
                if (!result.isEmpty()) {
                    if (let Some(instance) <- result[0].instance) {
                        if (!instance.IsPureAbstract()) {
                            target = Some(instance)
                            break
                        }
                    }
                }
            }
            CJC_NULLPTR_CHECK(target)
            return (target, Some(specificType))
        }
        let specificClass = (specificType as ClassType).getOrThrow()
        return CollectCandidates(builder, specificClass, (None, None), method)
    }

    // C++ Devirtualization.cpp:532-550.
    private func GetCandidateFromSpecificType(builder: CHIRBuilder, specific: ClassType,
        method: FuncSig): Option<Function> {
        let specificDef = specific.GetClassDef()
        if (specificDef.IsAbstract() || specificDef.IsInterface()) {
            return None
        }
        let customType = specificDef.GetType().getOrThrow()
        for (oriDef in devirtFuncInfo.defsMap.get(customType) ?? ArrayList<CustomTypeDef>()) {
            let genericDef = oriDef.GetGenericDecl() ?? oriDef
            for (item in genericDef.GetDefVTable().GetTypeVTables()) {
                if (let Some(target) <- FindFunctionInVtable(item.GetSrcParentType().getOrThrow(),
                    item.GetVirtualMethods(), method, builder)) {
                    return Some(target)
                }
            }
        }
        return None
    }

    // C++ Devirtualization.cpp:552-615. The returned pair is the Cangjie representation of C++'s pair& result.
    private func CollectCandidates(builder: CHIRBuilder, specific: ClassType,
        input: (Option<Function>, Option<Type>), method: FuncSig): (Option<Function>, Option<Type>) {
        var result = input
        let specificDef = specific.GetClassDef()
        if (specificDef.CanBeInherited() && !devirtFuncInfo.CheckCustomTypeInternal(specificDef)) {
            return result
        }
        if (let Some(targetFromSpecificType) <- GetCandidateFromSpecificType(builder, specific, method)) {
            if (result[0].isNone()) {
                result = (Some(targetFromSpecificType), Some(specific))
            } else if (result[0].getOrThrow() != targetFromSpecificType) {
                return (None, None)
            }
        }
        if (!specificDef.CanBeInherited()) {
            return result
        }
        let inheritInfos = devirtFuncInfo.GetSubtypeMap().get(specificDef) ?? return result
        for (inheritInfo in inheritInfos) {
            let expected = inheritInfo.parentType
            let replaceTable = HashMap<GenericType, Type>()
            if (!IsValidSubType(builder, expected, specific, replaceTable)) {
                continue
            }
            let subtype = ReplaceRawGenericArgType(inheritInfo.subType, replaceTable, builder)
            let subtypeCustom = subtype as CustomType
            if (subtypeCustom.isNone() ||
                (!subtypeCustom.getOrThrow().GetCustomTypeDef().IsInterface() &&
                    !subtypeCustom.getOrThrow().GetCustomTypeDef().TestAttr(Attribute.ABSTRACT))) {
                let definitions = if (let Some(customType) <- subtypeCustom) {
                    devirtFuncInfo.defsMap.get(customType) ?? ArrayList<CustomTypeDef>()
                } else {
                    ArrayList<CustomTypeDef>()
                }
                for (oriDef in definitions) {
                    let def = oriDef.GetGenericDecl() ?? oriDef
                    for (vtableIt in def.GetDefVTable().GetTypeVTables()) {
                        let srcParentType = vtableIt.GetSrcParentType().getOrThrow()
                        if (!expected.IsEqualOrSubTypeOf(srcParentType, builder)) {
                            continue
                        }
                        if (let Some(target) <- FindFunctionInVtable(srcParentType,
                            vtableIt.GetVirtualMethods(), method, builder)) {
                            if (result[0].isNone()) {
                                result = (Some(target), Some(subtypeCustom.getOrThrow()))
                            } else if (result[0].getOrThrow() != target) {
                                return (None, None)
                            }
                        }
                    }
                }
            }
            if (let Some(customType) <- subtypeCustom) {
                if (customType.IsClass()) {
                    result = CollectCandidates(builder, (customType as ClassType).getOrThrow(), result, method)
                }
            }
        }
        return result
    }

    // C++ Devirtualization.cpp:617-634.
    private static func CheckFuncHasInvoke(bg: BlockGroup): Bool {
        for (block in bg.GetBlocks()) {
            let expressions = block.GetNonTerminatorExpressions()
            var index: Int64 = 0
            while (index < expressions.size) {
                if (expressions[index].GetExprKind() == ExprKind.LAMBDA) {
                    if (CheckFuncHasInvoke((expressions[index] as Lambda).getOrThrow().GetBody().getOrThrow())) {
                        return true
                    }
                }
                if (expressions[index].GetExprKind() == ExprKind.INVOKE) {
                    return true
                }
                index++
            }
        }
        return false
    }

    // C++ Devirtualization.cpp:636-648.
    private static func CheckAllGenericTypeVisible(ty: Type, visibleSet: HashSet<GenericType>): Bool {
        if (ty.IsGeneric() && !visibleSet.contains((ty as GenericType).getOrThrow())) {
            return false
        }
        for (typeArg in ty.GetTypeArgs()) {
            if (!CheckAllGenericTypeVisible(typeArg, visibleSet)) {
                return false
            }
        }
        return true
    }

    // C++ Devirtualization.cpp:650-659.
    public static func CollectContainInvokeExprFuncs(chirPackage: Package): ArrayList<Function> {
        let funcs = ArrayList<Function>()
        for (fn in chirPackage.GetGlobalFuncsWithBody()) {
            if (CheckFuncHasInvoke(fn.GetBody().getOrThrow())) {
                funcs.add(fn)
            }
        }
        return funcs
    }
}
