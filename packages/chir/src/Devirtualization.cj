package cjcj::chir

import std.collection.*
import std.core.Box as CoreBox
import cjcj::basic.Linkage as BasicLinkage
import cjcj::modules.{GetPackageRelation, PackageRelation}
import cjcj::option.{GlobalOptions, OutputMode}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT}

// Upstream 6e125215 Devirtualization.cpp:34-80: resolve the invoke parent and slot.
private func CollectAllDefs(ty: Type, builder: CHIRBuilder): ArrayList<CustomTypeDef> {
    let defs = ArrayList<CustomTypeDef>()
    if (let Some(customTy) <- (ty as CustomType)) {
        let def = customTy.GetCustomTypeDef()
        defs.add(def)
        for (ex in def.GetExtends()) { defs.add(ex) }
    } else {
        for (ex in ty.GetExtends(builder)) { defs.add(ex) }
    }
    return defs
}

private func SearchRealCalleeInVtable(ty: Type, invoke: InvokeBase, builder: CHIRBuilder): Option<Function> {
    let allDefs = CollectAllDefs(ty, builder)
    let srcParentTypeInRT = invoke.GetInstSrcParentCustomTypeOfMethod(builder)
    var replaceTable = HashMap<GenericType, Type>()
    if (let Some(customTy) <- (ty as CustomType)) {
        replaceTable = GetInstMapFromCurDefAndExDefToCurType(customTy)
    }
    for (def in allDefs) {
        for (vtable in def.GetDefVTable().GetTypeVTables()) {
            let srcParentType = vtable.GetSrcParentType().getOrThrow()
            if (srcParentType.GetClassDef() != srcParentTypeInRT.GetClassDef()) { continue }
            if (ReplaceRawGenericArgType(srcParentType, replaceTable, builder) != srcParentTypeInRT) { continue }
            let methods = vtable.GetVirtualMethods()
            let offset = Int64(invoke.GetVirtualMethodOffset())
            CJC_ASSERT(methods.size > offset)
            let target = methods[offset].GetVirtualMethod().getOrThrow()
            if (!target.IsPureAbstract()) { return target.GetWrappedRawMethod() ?? target }
            break
        }
    }
    return None
}

private func HasUnknownGenericType(knownType: Type, unknownType: Type): Bool {
    let known = HashSet<GenericType>()
    knownType.VisitTypeRecursively({ ty =>
        if (let Some(generic) <- (ty as GenericType)) { known.add(generic) }
        return true
    })
    let unknown = CoreBox<Bool>(false)
    unknownType.VisitTypeRecursively({ ty =>
        if (let Some(generic) <- (ty as GenericType)) {
            if (!known.contains(generic)) { unknown.value = true; return false }
        }
        return true
    })
    return unknown.value
}

private func FindUpstreamThisValue(tempVar: LocalVar, casts: ArrayList<Expression>): Value {
    let expr = tempVar.GetExpr().getOrThrow()
    if (expr.GetExprKind() != ExprKind.BOX && expr.GetExprKind() != ExprKind.CLASS_STATIC_CAST) {
        return tempVar
    }
    casts.add(expr)
    let source = (expr as TypeCast).getOrThrow().GetSourceValue()
    if (let Some(local) <- source.AsLocalVar()) {
        return FindUpstreamThisValue(local, casts)
    }
    return source
}

private func CollectUpstreamTypeCasts(obj: LocalVar): (Value, ArrayList<Expression>) {
    let casts = ArrayList<Expression>()
    return (FindUpstreamThisValue(obj, casts), casts)
}

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


private func CreateInstFuncMangleName(identifier: String, fn: Function, context: FuncCallContext,
    builder: CHIRBuilder): String {
    let types = ArrayList<Type>()
    if (let Some(def) <- fn.GetParentCustomTypeDef()) {
        if (def.IsGenericDef()) {
            types.add(all: GetInstParentCustomTyOfCallee(fn, context.args, context.thisType, builder)
                .getOrThrow().StripAllRefs().GetTypeArgs())
        }
    }
    types.add(all: context.instTypeArgs)
    return GenerateInstantiateFuncMangleName(identifier, types)
}

private func GetInstFuncTypeFromContext(fn: Function, context: FuncCallContext, builder: CHIRBuilder): FuncType {
    var replaceTable = HashMap<GenericType, Type>()
    if (let Some(def) <- fn.GetParentCustomTypeDef()) {
        if (def.IsGenericDef()) {
            let parentTy = GetInstParentCustomTyOfCallee(fn, context.args, context.thisType, builder).getOrThrow()
            let mapping = def.GetType().getOrThrow().CalculateGenericTyMapping(parentTy)
            CJC_ASSERT(mapping[0])
            replaceTable = mapping[1]
        }
    }
    let generics = fn.GetGenericTypeParams()
    CJC_ASSERT(generics.size == context.instTypeArgs.size)
    for (i in 0..generics.size) { replaceTable[generics[i]] = context.instTypeArgs[i] }
    return (ReplaceRawGenericArgType(fn.GetType().getOrThrow(), replaceTable, builder) as FuncType).getOrThrow()
}

private class DevirtualizationRewriteInfo {
    let invoke: InvokeBase
    let realCallee: Function
    let thisType: Type
    init(invoke: InvokeBase, realCallee: Function, thisType: Type) {
        this.invoke = invoke
        this.realCallee = realCallee
        this.thisType = thisType
    }
}

// Upstream 6e125215 + 3d758bbb + e242ecf4 Devirtualization.cpp.
public class Devirtualization {
    private let analysisWrapper: AnalysisWrapper<TypeAnalysis, TypeDomain>
    private let devirtFuncInfo: DevirtualizationInfo
    private let builder: CHIRBuilder
    private let chirPackage: Package
    private let opts: GlobalOptions
    private let rewriteInfos = ArrayList<DevirtualizationRewriteInfo>()
    private let frozenInstFuns = ArrayList<Function>()
    private let frozenStates = HashMap<Function, Option<Results<TypeDomain>>>()
    private let frozenInstFuncMap = HashMap<String, Function>()

    public init(wrapper: AnalysisWrapper<TypeAnalysis, TypeDomain>, info: DevirtualizationInfo,
        builder: CHIRBuilder, chirPackage: Package, opts: GlobalOptions) {
        analysisWrapper = wrapper
        devirtFuncInfo = info
        this.builder = builder
        this.chirPackage = chirPackage
        this.opts = opts
    }

    private func IsSubtypeSetComplete(def: CustomTypeDef): Bool {
        let relation = GetPackageRelation(def.GetPackageName(), chirPackage.GetName())
        if (def.TestAttr(Attribute.PUBLIC) || def.TestAttr(Attribute.PROTECTED)) {
            return opts.outputMode == OutputMode.EXECUTABLE && relation == PackageRelation.SAME_PACKAGE
        }
        if (def.TestAttr(Attribute.PRIVATE)) { return true }
        if (def.TestAttr(Attribute.INTERNAL)) {
            return (relation != PackageRelation.CHILD && relation != PackageRelation.SAME_PACKAGE) || opts.noSubPkg
        }
        return false
    }

    public func RunOnFuncs(funcs: ArrayList<Function>): Unit {
        rewriteInfos.clear()
        for (fn in funcs) { RunOnFunc(fn) }
        RewriteToApply(rewriteInfos)
    }

    private func RunOnFunc(fn: Function): Unit {
        var result = analysisWrapper.CheckFuncResult(fn)
        if (result.isNone()) { result = frozenStates.get(fn) ?? None }
        let analysisResult = result ?? return
        let tryCollect = { state: TypeDomain, invoke: InvokeBase =>
            let obj = state.CheckAbstractObjectRefBy(invoke.GetObject()) ?? return
            let value = state.CheckAbstractValue(obj) ?? return
            let found = FindFinalCalleeAndThisType(value, invoke)
            if (found[0].isNone() || found[1].isNone()) { return }
            rewriteInfos.add(DevirtualizationRewriteInfo(invoke, found[0].getOrThrow(), found[1].getOrThrow()))
        }
        let before = { state: TypeDomain, expr: Expression, _: Int64 =>
            if (let Some(invoke) <- (expr as Invoke)) { tryCollect(state, InvokeBase(invoke)) }
        }
        let after = { _: TypeDomain, _: Expression, _: Int64 => }
        let terminator = { state: TypeDomain, expr: Expression, _: Option<Block> =>
            if (let Some(invoke) <- (expr as InvokeWithException)) { tryCollect(state, InvokeBase(invoke)) }
        }
        analysisResult.VisitWith(before, after, terminator)
    }

    private func RewriteToBuiltinOp(info: DevirtualizationRewriteInfo): Bool {
        let kinds = [ExprKind.GT, ExprKind.LT, ExprKind.GE, ExprKind.LE, ExprKind.EQUAL, ExprKind.NOTEQUAL]
        let names = [">", "<", ">=", "<=", "==", "!="]
        var kind = ExprKind.INVALID
        for (i in 0..kinds.size) {
            if (IsExpectedFunction(info.realCallee, FuncInfo(names[i], ANY_TYPE, [ANY_TYPE], ANY_TYPE, "std.core"))) {
                kind = kinds[i]
                break
            }
        }
        if (kind == ExprKind.INVALID) { return false }
        let args = info.invoke.GetArgs()
        if (args.size != 2) { return false }
        var lhs = args[0]
        let rhs = args[1]
        var casts = ArrayList<Expression>()
        if (let Some(local) <- lhs.AsLocalVar()) {
            let collected = CollectUpstreamTypeCasts(local)
            lhs = collected[0]
            casts = collected[1]
        }
        if (!lhs.GetType().getOrThrow().IsPrimitive() || !rhs.GetType().getOrThrow().IsPrimitive()) { return false }
        let invoke = info.invoke.GetRawExpr()
        let parent = invoke.GetParentBlock().getOrThrow()
        let next: Option<Block> = if (let Some(term) <- (invoke as InvokeWithException)) { Some(term.GetSuccessBlock()) } else { None }
        let binary = builder.CreateBinaryExpression(kind, invoke.GetResultType().getOrThrow(), lhs, rhs, parent)
        binary.SetDebugLocation(invoke.GetDebugLocation())
        invoke.ReplaceWith(binary)
        for (cast in casts) {
            if (cast.GetResult().getOrThrow().GetUsers().isEmpty()) { cast.RemoveSelfFromBlock() }
        }
        if (let Some(block) <- next) { builder.CreateGoTo(block, parent).MoveAfter(binary) }
        return true
    }

    // 6e125215 Devirtualization.cpp:326 IsValueType, extracted by 3d758bbb AddRefIfNeeded.
    private func AddRefIfNeeded(ty: Type, callee: Function): Type {
        if (ty.IsReferenceType()) {
            return builder.context.GetRefTy(ty)
        }
        if (ty.IsValueType() &&
            (callee.TestAttr(Attribute.MUT) || callee.IsConstructor() || callee.IsInstanceVarInit())) {
            return builder.context.GetRefTy(ty)
        }
        return ty
    }

    private func RewriteToApply(infos: ArrayList<DevirtualizationRewriteInfo>): Unit {
        var i = infos.size - 1
        while (i >= 0) {
            let info = infos[i]
            i--
            if (RewriteToBuiltinOp(info)) { continue }
            var realFunc = info.realCallee
            let thisTy = AddRefIfNeeded(info.thisType, realFunc)
            let invoke = info.invoke.GetRawExpr()
            let context = FuncCallContext(args: info.invoke.GetArgs(),
                instTypeArgs: info.invoke.GetInstantiatedTypeArgs(), thisType: Some(thisTy))
            let expectedRetTy = invoke.GetResultType().getOrThrow()
            var instRetTy = expectedRetTy
            if (let Some(instFunc) <- CreateInstFuncIfPossible(realFunc, context)) {
                realFunc = instFunc
                instRetTy = instFunc.GetFuncType().getOrThrow().GetReturnType()
            }
            var instParentTy = GetInstParentCustomTyOfCallee(realFunc, context.args, context.thisType, builder) ??
                realFunc.GetFuncType().getOrThrow().GetParamType(0)
            instParentTy = AddRefIfNeeded(instParentTy, realFunc)
            let parent = invoke.GetParentBlock().getOrThrow()
            let (converted, expressions) = TypeCastOrBoxIfNeeded(context.args[0], instParentTy, builder, parent)
            if (!refEq(converted, context.args[0])) {
                for (expression in expressions) { expression.MoveBefore(invoke) }
                context.args[0] = converted
            }
            let call: Expression = if (let Some(term) <- (invoke as InvokeWithException)) {
                builder.CreateApplyWithException(instRetTy, realFunc, context,
                    term.GetSuccessBlock(), term.GetErrorBlock(), parent)
            } else {
                builder.CreateApply(instRetTy, realFunc, context, parent)
            }
            call.SetDebugLocation(invoke.GetDebugLocation())
            invoke.ReplaceWith(call)
            AddTypeCastForReturnVal(call, expectedRetTy, builder)
        }
    }

    public func GetFrozenInstFuns(): ArrayList<Function> { return frozenInstFuns }
    public func AppendFrozenFuncState(fn: Function, result: Option<Results<TypeDomain>>): Unit {
        frozenStates[fn] = result
    }

    private func CreateInstFuncIfPossible(fn: Function, context: FuncCallContext): Option<Function> {
        if (!fn.IsFuncWithBody() || !fn.IsInGenericContext() || context.thisType.getOrThrow().IsGenericRelated()) {
            return None
        }
        for (ty in context.instTypeArgs) { if (ty.IsGenericRelated()) { return None } }
        let newId = CreateInstFuncMangleName(fn.GetIdentifierWithoutPrefix(), fn, context, builder)
        var newFunc: Function
        if (let Some(found) <- frozenInstFuncMap.get(newId)) {
            newFunc = found
        } else {
            let instFuncType = GetInstFuncTypeFromContext(fn, context, builder)
            let parameterType = instFuncType.GetParamTypes()
            newFunc = builder.CreateFunction(instFuncType, newId,
                srcCodeIdentifier: fn.GetSrcCodeIdentifier(), rawMangledName: "",
                packageName: fn.GetPackageName())
            newFunc.SetDebugLocation(fn.GetDebugLocation())
            newFunc.AppendAttributeInfo(fn.GetAttributeInfo())
            newFunc.DisableAttr(Attribute.GENERIC)
            if (!context.instTypeArgs.isEmpty()) {
                newFunc.EnableAttr(Attribute.GENERIC_INSTANTIATED)
            }
            newFunc.SetLinkTypeInfo(BasicLinkage.INTERNAL)
            newFunc.SetGenericDecl(fn)
            let oriBlockGroup = fn.GetBody().getOrThrow()
            let copy = BlockGroupCopyHelper(builder)
            copy.GetInstMapFromFuncCall(fn, context.thisType, context.instTypeArgs, context.args)
            let newBody = builder.CreateBlockGroup(newFunc)
            newFunc.InitBody(newBody)
            let cloned = copy.CloneBlockGroup(oriBlockGroup, newBody)
            let newBlocks = cloned[0]
            let newBlockGroupRetValue = cloned[1].getOrThrow()
            newBody.SetEntryBlock(GetEntryBlock(oriBlockGroup, newBlocks))
            newFunc.SetReturnValue(newBlockGroupRetValue)
            CJC_ASSERT(parameterType.size == fn.GetParams().size)
            let paramMap = HashMap<Int64, Value>()
            var paramIndex: Int64 = 0
            while (paramIndex < parameterType.size) {
                let arg = builder.CreateParameter(parameterType[paramIndex],
                    fn.GetParam(paramIndex).GetDebugLocation(), newFunc)
                paramMap[fn.GetParam(paramIndex).nodeId] = arg
                paramIndex++
            }
            BlockGroupCopyHelper.ReplaceExprOperands(newBlocks, paramMap)
            FixCastProblemAfterInst(newBlocks, builder)
            newFunc.SetReturnValue(newBlockGroupRetValue)
            frozenInstFuns.add(newFunc)
            frozenInstFuncMap[newId] = newFunc
        }
        context.instTypeArgs.clear()
        context.thisType = None
        return newFunc
    }

    private func CollectAllSubTypes(specific: ClassType): ArrayList<Type> {
        if (specific.CanBeInherited() && !IsSubtypeSetComplete(specific.GetClassDef())) { return ArrayList<Type>() }
        let all = ArrayList<Type>([specific])
        let visited = HashSet<Type>()
        visited.add(specific)
        let work = ArrayList<ClassType>([specific])
        while (!work.isEmpty()) {
            let cur = work.remove(at: work.size - 1)
            let infos = devirtFuncInfo.subtypeMap.get(cur.GetClassDef()) ?? ArrayList<InheritanceInfo>()
            for (info in infos) {
                let mapping = info.parentType.CalculateGenericTyMapping(cur)
                if (!mapping[0]) { continue }
                let sub = ReplaceRawGenericArgType(info.subType, mapping[1], builder)
                if (!visited.add(sub)) { continue }
                if (sub.CanBeInherited()) {
                    let cls = (sub as ClassType).getOrThrow()
                    if (!IsSubtypeSetComplete(cls.GetClassDef())) { return ArrayList<Type>() }
                    work.add(cls)
                }
                all.add(sub)
            }
        }
        return all
    }

    private func FindFinalCalleeAndThisType(state: TypeValue, invoke: InvokeBase): (Option<Function>, Option<Type>) {
        let specific = state.GetSpecificType()
        if (!specific.CanBeInherited() || state.GetTypeKind() == DevirtualTyKind.EXACTLY) {
            let target = SearchRealCalleeInVtable(specific, invoke, builder).getOrThrow()
            return (Some(target), Some(specific))
        }
        let subTypes = CollectAllSubTypes((specific as ClassType).getOrThrow())
        let targets = HashSet<Function>()
        for (sub in subTypes) {
            if (let Some(target) <- SearchRealCalleeInVtable(sub, invoke, builder)) { targets.add(target) }
        }
        if (targets.size != 1) { return (None, None) }
        let callee = targets.iterator().next().getOrThrow()
        let srcParentTy = invoke.GetInstSrcParentCustomTypeOfMethod(builder)
        let genericSubTy = callee.GetParentCustomTypeOrExtendedType().getOrThrow()
        let thisTy = GetInstSubType(genericSubTy, srcParentTy, builder)
        if (HasUnknownGenericType(srcParentTy, thisTy)) { return (Some(callee), None) }
        return (Some(callee), Some(thisTy))
    }

    public static func CollectContainInvokeExprFuncs(chirPackage: Package): ArrayList<Function> {
        let funcs = ArrayList<Function>()
        for (fn in chirPackage.GetGlobalFuncsWithBody()) {
            if (TypeAnalysis.CheckFuncHasInvoke(fn)) { funcs.add(fn) }
        }
        return funcs
    }
}
