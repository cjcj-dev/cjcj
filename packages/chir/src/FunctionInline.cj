package cjcj::chir

import cjcj::basic.Linkage as BasicLinkage
import std.collection.*
import std.core.Box as CoreBox
import cjcj::option.{OptimizationLevel, enumIndex}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT}

private let INIT_INLINE_THRESHOLD: Int64 = 20
private let INLINED_COUNT_THRESHOLD: Int64 = 20
private let SEARCH_THRESHOLD: Int64 = INIT_INLINE_THRESHOLD * 3
private let INCREASE_THRESHOLD: Int64 = 5
private let INCREASE_WHEN_CALLEE_WITH_LAMBDA_ARG: Int64 = 2
private let INLINED_BLOCKSIZE_THRESHOLD: Int64 = 10000

private let functionInlineWhiteList: Array<FuncInfo> = [
    FuncInfo("get", "Array", [NOT_CARE], ANY_TYPE, "std.core"),
    FuncInfo("set", "Array", [NOT_CARE], ANY_TYPE, "std.core"),
    FuncInfo("[]", "Array", [NOT_CARE], ANY_TYPE, "std.core"),
    FuncInfo("copyTo", "Array", [NOT_CARE], ANY_TYPE, "std.core"),
    FuncInfo("utf8Size", "Rune", [NOT_CARE], ANY_TYPE, "std.core"),
    FuncInfo("[]", "String", [NOT_CARE], ANY_TYPE, "std.core"),
    FuncInfo("init", "ArrayList", [NOT_CARE], ANY_TYPE, "std.collection"),
    FuncInfo("get", "ArrayList", [NOT_CARE], ANY_TYPE, "std.collection"),
    FuncInfo("set", "ArrayList", [NOT_CARE], ANY_TYPE, "std.collection"),
    FuncInfo("append", "ArrayList", [NOT_CARE], ANY_TYPE, "std.collection"),
    FuncInfo("[]", "ArrayList", [NOT_CARE], ANY_TYPE, "std.collection"),
    FuncInfo("checkRange", "ArrayList", [NOT_CARE], ANY_TYPE, "std.collection"),
    FuncInfo("remove", "ArrayList", [NOT_CARE], ANY_TYPE, "std.collection"),
    FuncInfo("==", "HashSet", [NOT_CARE], ANY_TYPE, "std.collection"),
    FuncInfo("!=", "HashSet", [NOT_CARE], ANY_TYPE, "std.collection")
]

private let functionInlineBlackList: Array<FuncInfo> = [
    FuncInfo("init", "Future", [NOT_CARE], ANY_TYPE, "std.core"),
    FuncInfo("arrayInitByFunction", "", [NOT_CARE], NOT_CARE, "std.core"),
    FuncInfo("callNativeFunc", NOT_CARE, [NOT_CARE], NOT_CARE, "std.fs"),
    FuncInfo("wrappingShl", NOT_CARE, [NOT_CARE], ANY_TYPE, "std.overflow"),
    FuncInfo("wrappingShr", NOT_CARE, [NOT_CARE], ANY_TYPE, "std.overflow")
]

public class FunctionInline {
    private let builder: CHIRBuilder
    private let optLevel: OptimizationLevel
    private let debug: Bool
    private var globalFunc: Option<Function> = None
    private let inlinedCountMap: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let funcSizeMap: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let optName: String = "Function Inline"
    private let effectMap: OptEffectCHIRMap = OptEffectCHIRMap()

    public init(builder: CHIRBuilder, optLevel: OptimizationLevel, debug: Bool) {
        this.builder = builder
        this.optLevel = optLevel
        this.debug = debug
    }

    private func InlineImpl(blockGroup: BlockGroup): Unit {
        let preVisit: VisitExprActionFunc = { expr =>
            if (expr.GetExprKind() != ExprKind.APPLY) {
                return VisitResult.CONTINUE
            }
            let apply = (expr as Apply).getOrThrow()
            if (CheckCanRewrite(apply)) {
                DoFunctionInline(apply, optName)
            }
            return VisitResult.CONTINUE
        }
        Visitor.Visit(blockGroup, preVisit)
    }

    public func Run(fn: Function): Unit {
        let _ = PreserveThrowBoundary(fn)
        globalFunc = fn
        InlineImpl(fn.GetBody().getOrThrow())
        OutlineThrowConstructions(fn)
    }

    // Outline before LLVM creates aggregate entry slots. Only the complete
    // construction suffix moves; field loads, guards and their roots stay put.
    // This is not a lifetime inference for existing GC storage.
    private func OutlineThrowConstructions(fn: Function): Unit {
        if (fn.TestAttr(Attribute.IMPORTED) || fn.GetGenericDecl().isSome() ||
            !fn.GetGenericTypeParams().isEmpty() || fn.GetType().getOrThrow().IsGenericRelated() ||
            fn.GetReturnType().getOrThrow().IsNothing() || fn.GetFuncType().getOrThrow().IsCFunc()) {
            return
        }
        // Do not hide annotation violations or change a special stack contract.
        for (attr in [Attribute.NO_HEAP_ALLOC, Attribute.NO_WRITE_BARRIER, Attribute.NO_WRITE_BARRIER_REC,
            Attribute.NO_STACK_GROW, Attribute.SYSTEM_STACK, Attribute.FOREIGN]) {
            if (fn.TestAttr(attr)) { return }
        }
        for (block in fn.GetBody().getOrThrow().GetBlocks()) {
            let exprs = block.GetExpressions()
            if (block.IsLandingPadBlock() || exprs.size < 4) { continue }
            let start = exprs.size - 4
            let suffix = ArrayList<Expression>()
            for (idx in start..exprs.size) { suffix.add(exprs[idx]) }
            if (!IsCompleteThrowConstruction(suffix)) { continue }
            let captures = ArrayList<Value>()
            if (!CollectThrowCaptures(suffix, captures)) { continue }
            OutlineThrowConstruction(fn, block, suffix, captures)
        }
    }

    private func IsCompleteThrowConstruction(exprs: ArrayList<Expression>): Bool {
        if (exprs[0].GetExprKind() != ExprKind.APPLY || exprs[1].GetExprKind() != ExprKind.ALLOCATE ||
            exprs[2].GetExprKind() != ExprKind.APPLY || exprs[3].GetExprKind() != ExprKind.RAISE_EXCEPTION ||
            !exprs[3].GetSuccessors().isEmpty()) {
            return false
        }
        let message = (exprs[0] as Apply).getOrThrow()
        let allocation = (exprs[1] as Allocate).getOrThrow()
        let constructor = (exprs[2] as Apply).getOrThrow()
        let aggregateTy = message.GetResult().getOrThrow().GetType().getOrThrow()
        if ((!aggregateTy.IsStruct() && !aggregateTy.IsTuple()) || !allocation.GetType().IsClass()) {
            return false
        }
        let ctor = constructor.GetCallee().AsFunction() ?? return false
        let args = constructor.GetArgs()
        if (!ctor.IsConstructor() || args.isEmpty() ||
            !refEq(args[0], allocation.GetResult().getOrThrow()) ||
            !args.contains(message.GetResult().getOrThrow()) ||
            !refEq(exprs[3].GetOperand(0), constructor.GetResult().getOrThrow())) {
            return false
        }
        // Dynamic/This/generic call context would need an additional capture
        // contract. Direct, concretely typed calls use the ordinary ABI here.
        for (call in [message, constructor]) {
            if (!call.GetCallee().IsFunc()) { return false }
            if (let Some(ty) <- call.GetThisType()) {
                if (ty.IsGenericRelated() || ty.IsThis()) { return false }
            }
            for (ty in call.GetInstantiatedTypeArgs()) {
                if (ty.IsGenericRelated() || ty.IsThis()) { return false }
            }
        }
        return !allocation.GetType().IsGenericRelated()
    }

    private func CollectThrowCaptures(exprs: ArrayList<Expression>, captures: ArrayList<Value>): Bool {
        let produced = HashSet<Value>()
        for (expr in exprs) {
            if (let Some(result) <- expr.GetResult()) {
                if (result.GetType().getOrThrow().IsGenericRelated()) { return false }
                produced.add(result)
                for (user in result.GetUsers()) {
                    if (!exprs.contains(user)) { return false }
                }
            }
        }
        let available = HashSet<Value>()
        for (expr in exprs) {
            for (operand in expr.GetOperands()) {
                if (available.contains(operand)) { continue }
                if (produced.contains(operand)) { return false }
                if (operand.IsFunc()) { continue }
                let ty = operand.GetType() ?? return false
                // No managed/native/aggregate address is captured. Cold prefix
                // reads finish in the caller; only their scalar results cross.
                if (!ty.IsNumeric() && !ty.IsBoolean() && !ty.IsRune()) { return false }
                if (!captures.contains(operand)) { captures.add(operand) }
            }
            if (let Some(result) <- expr.GetResult()) { available.add(result) }
        }
        return true
    }

    private func OutlineThrowConstruction(fn: Function, block: Block,
        exprs: ArrayList<Expression>, captures: ArrayList<Value>): Unit {
        let paramTys = ArrayList<Type>()
        for (capture in captures) { paramTys.add(capture.GetType().getOrThrow()) }
        let nothing = builder.context.GetNothingType()
        let packageName = builder.context.GetCurPackage().getOrThrow().GetName()
        // Frozen specializations have the same original name in different
        // packages. Cross-split internal helpers need package-unique symbols.
        let helper = builder.CreateFunction(builder.context.GetFuncTy(paramTys, nothing),
            fn.GetIdentifierWithoutPrefix() + ".throw." + packageName + "." + block.GetIdentifier(),
            packageName: packageName)
        helper.SetLinkTypeInfo(BasicLinkage.INTERNAL)
        helper.EnableAttr(Attribute.COMPILER_ADD)
        helper.EnableAttr(Attribute.NO_INLINE)
        helper.EnableAttr(Attribute.NO_REFLECT_INFO)
        helper.EnableAttr(Attribute.NO_DEBUG_INFO)
        let body = builder.CreateBlockGroup(helper)
        helper.InitBody(body)
        let entry = builder.CreateBlock(body)
        body.SetEntryBlock(entry)
        let replacements = HashMap<Value, Value>()
        for (capture in captures) {
            replacements[capture] = builder.CreateParameter(capture.GetType().getOrThrow(), DebugLocation(), helper)
        }
        for (expr in exprs) {
            let cloned = expr.Clone(builder, entry)
            cloned.CopyBaseInfoFrom(expr)
            cloned.AppendAttributeInfo(expr.GetAttributeInfo())
            // Generated frame: retain the original source position on the call,
            // not a caller's lexical scope on instructions in a different fn.
            cloned.SetDebugLocation(DebugLocation())
            for (operand in expr.GetOperands()) {
                if (let Some(replacement) <- replacements.get(operand)) {
                    cloned.ReplaceOperand(operand, replacement)
                }
            }
            entry.AppendExpression(cloned)
            if (let Some(result) <- expr.GetResult()) {
                let clonedResult = cloned.GetResult().getOrThrow()
                clonedResult.CopyBaseInfoFrom(result)
                clonedResult.AppendAttributeInfo(result.GetAttributeInfo())
                clonedResult.SetDebugLocation(DebugLocation())
                replacements[result] = clonedResult
            }
        }
        let call = builder.CreateApply(nothing, helper, FuncCallContext(args: captures), block)
        call.SetDebugLocation(exprs[0].GetDebugLocation())
        // All results are suffix-local. Remove uses in reverse construction
        // order after the new helper owns its own cloned values.
        var idx = exprs.size
        while (idx > 0) { idx--; exprs[idx].RemoveSelfFromBlock() }
        block.AppendExpression(call)
        block.AppendExpression(builder.CreateExit(None, block))
        RecordEffectMap(call)
    }

    public func GetEffectMap(): OptEffectCHIRMap {
        return effectMap
    }

    private func CheckCanRewrite(apply: Apply): Bool {
        let callee = apply.GetCallee()
        if (!callee.IsFuncWithBody()) {
            return false
        }
        let fn = callee.AsFunction().getOrThrow()
        if (PreserveThrowBoundary(fn)) {
            return false
        }
        let parentBlock = apply.GetParentBlock().getOrThrow()
        if (parentBlock.GetTerminator().getOrThrow().GetExprKind() == ExprKind.RAISE_EXCEPTION) {
            return false
        }
        if (parentBlock.GetExpressions().size >= INLINED_BLOCKSIZE_THRESHOLD) {
            return false
        }
        if (let Some(currentGlobalFunc) <- globalFunc) {
            if (refEq(callee, currentGlobalFunc)) {
                return false
            }
        }
        if (InBlackList(fn)) {
            return false
        }
        if (InWhiteList(fn)) {
            return true
        }
        if (fn.GetFuncKind() == FuncKind.INSTANCEVAR_INIT) {
            return true
        }
        // @ObjCMirror functions are generated and always have the same body
        // that calls relevant native code.
        // According to benchmarks, they can always be inlined.
        if (fn.TestAttr(Attribute.OBJ_C_FOREIGN)) {
            return true
        }
        let currentGlobalFunc = globalFunc.getOrThrow()
        let inlinedCount = inlinedCountMap.get(currentGlobalFunc.nodeId) ?? 0
        if (inlinedCount >= INLINED_COUNT_THRESHOLD) {
            return false
        }
        let realThreshold = CalculateThreshold(callee, optLevel)
        if (!funcSizeMap.contains(fn.nodeId)) {
            funcSizeMap[fn.nodeId] = CountFuncSize(fn)
        }
        if (funcSizeMap.get(fn.nodeId).getOrThrow() <= realThreshold) {
            inlinedCountMap[currentGlobalFunc.nodeId] = inlinedCount + 1
            return true
        }
        return false
    }

    private func ReplaceFuncResult(resNew: LocalVar, resOld: LocalVar): Unit {
        var valueType = resNew.GetType().getOrThrow()
        CJC_ASSERT(valueType.IsRef())
        let users = resOld.GetUsers()
        if (users.isEmpty()) {
            return
        }
        valueType = (valueType as RefType).getOrThrow().GetBaseType()
        for (user in users) {
            let newLoad = builder.CreateLoad(valueType, resNew, user.GetParentBlock().getOrThrow())
            newLoad.MoveBefore(user)
            user.ReplaceOperand(resOld, newLoad.GetResult().getOrThrow())
            let (cast, expressions) = TypeCastOrBoxIfNeeded(newLoad.GetResult().getOrThrow(), resOld.GetType().getOrThrow(), builder,
                newLoad.GetParentBlock().getOrThrow(), INVALID_LOCATION)
            if (!refEq(cast, newLoad.GetResult().getOrThrow())) {
                CJC_ASSERT(cast.IsLocalVar())
                for (expression in expressions) {
                    expression.MoveBefore(user)
                }
                user.ReplaceOperand(newLoad.GetResult().getOrThrow(), cast)
            }
        }
    }

    private func SetGroupDebugLocation(blocks: ArrayList<Block>, loc: DebugLocation): Unit {
        let changeLoc: VisitExprActionFunc = { expr =>
            expr.SetDebugLocation(loc)
            return VisitResult.CONTINUE
        }
        for (block in blocks) {
            Visitor.Visit(block, changeLoc)
        }
    }

    public func DoFunctionInline(apply: Apply, name: String): Unit {
        RecordEffectMap(apply)
        PrintOptInfo(apply, debug, name)
        var oldFuncGroup: Option<BlockGroup> = None
        let funcArgs = ArrayList<Parameter>()
        if (apply.GetCallee().IsFuncWithBody()) {
            let fn = apply.GetCallee().AsFunction().getOrThrow()
            oldFuncGroup = fn.GetBody()
            funcArgs.add(all: fn.GetParams())
        } else {
            CJC_ASSERT(apply.GetCallee().IsLocalVar())
            let lambda = (apply.GetCallee().AsLocalVar().getOrThrow().GetExpr().getOrThrow() as Lambda).getOrThrow()
            oldFuncGroup = lambda.GetBody()
            funcArgs.add(all: lambda.GetParams())
        }
        let sourceGroup = oldFuncGroup.getOrThrow()
        CJC_ASSERT(sourceGroup.GetTopLevelFunc().isSome())
        let cloned = CloneBlockGroupForInline(sourceGroup, apply)
        let newBlocks = cloned[0]
        let returnValue = cloned[1]
        SetGroupDebugLocation(newBlocks, apply.GetDebugLocation())
        let funcEntry = GetEntryBlock(sourceGroup, newBlocks)
        let exitBlocks = GetExitBlocks(newBlocks)
        let applyArgs = apply.GetArgs()
        ReplaceFuncArgs(funcArgs, applyArgs, newBlocks)
        FixCastProblemAfterInst(newBlocks, builder)
        if (let Some(newReturnValue) <- returnValue) {
            ReplaceFuncResult(newReturnValue, apply.GetResult().getOrThrow().AsLocalVar().getOrThrow())
        }
        let splitBlocks = builder.SplitBlock(apply)
        let block1 = splitBlocks[0]
        let block2 = splitBlocks[1]
        block1.GetTerminator().getOrThrow().ReplaceSuccessor(block2, funcEntry)
        for (exitBlock in exitBlocks) {
            exitBlock.GetTerminator().getOrThrow().RemoveSelfFromBlock()
            let createdExpression192 = builder.CreateGoTo(block2, exitBlock)
            exitBlock.AppendExpression(createdExpression192)
        }
    }

    private func RecordEffectMap(apply: Apply): Unit {
        if (!apply.GetCallee().IsFuncWithBody()) {
            return
        }
        let callee = apply.GetCallee().AsFunction().getOrThrow()
        let parentFunc = apply.GetTopLevelFunc().getOrThrow()
        if (!callee.IsLambda() && !parentFunc.IsLambda()) {
            if (let Some(affectedFunctions) <- effectMap.get(callee)) {
                affectedFunctions.add(parentFunc)
            } else {
                let affectedFunctions = HashSet<Value>()
                affectedFunctions.add(parentFunc)
                effectMap[callee] = affectedFunctions
            }
        }
    }

    private func CloneBlockGroupForInline(oldBlockGroup: BlockGroup,
        apply: Apply): (ArrayList<Block>, Option<LocalVar>) {
        let blockGroupCopy = BlockGroupCopyHelper(builder)
        blockGroupCopy.GetInstMapFromApply(apply)
        return blockGroupCopy.CloneBlockGroup(oldBlockGroup, apply.GetParentBlockGroup().getOrThrow())
    }
}

// A complete throw function owns its exception construction and managed message
// storage. Translation keeps a parameter-entry GoTo before the source body in
// debug builds. Follow only an acyclic, unconditional path to an external raise;
// do not depend on MergeBlocks removing that source/debug boundary. Keep calls,
// handlers, roots and CFG intact, and carry the existing NO_INLINE to codegen.
private func PreserveThrowBoundary(fn: Function): Bool {
    if (!fn.GetReturnType().getOrThrow().IsNothing()) {
        return false
    }
    var current = fn.GetEntryBlock()
    let visited = HashSet<Value>()
    while (let Some(block) <- current) {
        if (visited.contains(block)) { return false }
        visited.add(block)
        if (block.GetTerminator().isNone()) { return false }
        let terminator = block.GetTerminator().getOrThrow()
        if (terminator.GetExprKind() == ExprKind.RAISE_EXCEPTION) {
            // A local handler can continue or loop: this is not an external throw.
            if (!terminator.GetSuccessors().isEmpty()) { return false }
            fn.EnableAttr(Attribute.NO_INLINE)
            return true
        }
        if (terminator.GetExprKind() != ExprKind.GOTO) { return false }
        let successors = terminator.GetSuccessors()
        if (successors.size != 1) { return false }
        current = Some(successors[0])
    }
    return false
}

private func InBlackList(fn: Function): Bool {
    if (fn.GetFuncKind() == FuncKind.MACRO_FUNC || fn.GetFuncKind() == FuncKind.GLOBALVAR_INIT ||
        fn.GetFuncKind() == FuncKind.MAIN_ENTRY) {
        return true
    }
    if (fn.GetFuncType().getOrThrow().IsCFunc()) {
        return true
    }
    if (fn.TestAttr(Attribute.NO_INLINE)) {
        return true
    }
    for (element in functionInlineBlackList) {
        if (IsExpectedFunction(fn, element)) {
            return true
        }
    }
    return false
}

private func InWhiteList(fn: Function): Bool {
    for (element in functionInlineWhiteList) {
        if (IsExpectedFunction(fn, element)) {
            return true
        }
    }
    return false
}

private func OnlyCalledOnce(fn: Function): Bool {
    var alreadyHasUser = false
    for (user in fn.GetUsers()) {
        if (user.GetExprKind() == ExprKind.APPLY || user.GetExprKind() == ExprKind.TRY_APPLY) {
            if (alreadyHasUser) {
                return false
            }
            alreadyHasUser = true
        }
    }
    return true
}

private func IsHotSpotCall(callee: Function): Bool {
    if (callee.TestAttr(Attribute.OPERATOR)) {
        return true
    }
    return false
}

private func FunctionWithLambdaArg(fn: Function): Bool {
    for (arg in fn.GetParams()) {
        if (arg.GetType().getOrThrow().IsFunc()) {
            return true
        }
    }
    return false
}

private func CalculateThreshold(callee: Value, optLevel: OptimizationLevel): Int64 {
    var realThreshold = INIT_INLINE_THRESHOLD
    let fn = callee.AsFunction().getOrThrow()
    if (OnlyCalledOnce(fn)) {
        realThreshold += realThreshold / INCREASE_THRESHOLD
    }
    if (enumIndex(optLevel) < enumIndex(OptimizationLevel.Os)) {
        if (IsHotSpotCall(fn)) {
            realThreshold = INIT_INLINE_THRESHOLD + INIT_INLINE_THRESHOLD / INCREASE_THRESHOLD
        }
        if (FunctionWithLambdaArg(fn)) {
            realThreshold = INIT_INLINE_THRESHOLD * INCREASE_WHEN_CALLEE_WITH_LAMBDA_ARG
        }
    }
    return realThreshold
}

private func GetExprSize(expr: Expression): Int64 {
    let exprSize = CoreBox<Int64>(0)
    if (expr.GetExprKind() != ExprKind.LAMBDA) {
        exprSize.value++
        return exprSize.value
    }
    let countExpr: VisitExprActionFunc = { _: Expression =>
        exprSize.value++
        return VisitResult.CONTINUE
    }
    Visitor.Visit((expr as Lambda).getOrThrow().GetBody().getOrThrow(), countExpr)
    return exprSize.value
}

private func CountFuncSize(fn: Function): Int64 {
    var funcSize: Int64 = 0
    for (block in fn.GetBody().getOrThrow().GetBlocks()) {
        for (expr in block.GetExpressions()) {
            funcSize += GetExprSize(expr)
            if (funcSize >= SEARCH_THRESHOLD) {
                break
            }
        }
    }
    return funcSize
}

private func GetEntryBlock(oldBlockGroup: BlockGroup, blocks: ArrayList<Block>): Block {
    let oldBlocks = oldBlockGroup.GetBlocks()
    CJC_ASSERT(oldBlocks.size == blocks.size)
    CJC_ASSERT(!blocks.isEmpty())
    var index: Int64 = 0
    while (index < oldBlocks.size) {
        if (refEq(oldBlocks[index], oldBlockGroup.GetEntryBlock().getOrThrow())) {
            return blocks[index]
        }
        index++
    }
    CJC_ABORT()
    return blocks[0]
}

private func GetExitBlocks(blocks: ArrayList<Block>): ArrayList<Block> {
    let exitBlocks = ArrayList<Block>()
    for (block in blocks) {
        let terminator = block.GetTerminator().getOrThrow()
        if (terminator.GetExprKind() == ExprKind.EXIT) {
            exitBlocks.add(block)
        }
    }
    return exitBlocks
}

private func ReplaceFuncArgs(src: ArrayList<Parameter>, dst: ArrayList<Value>, newBlocks: ArrayList<Block>): Unit {
    CJC_ASSERT(src.size == dst.size)
    let allNewBlocks = HashSet<Value>()
    let collectBlock: VisitBlockActionFunc = { block =>
        allNewBlocks.add(block)
        return VisitResult.CONTINUE
    }
    for (block in newBlocks) {
        Visitor.Visit(block, collectBlock)
    }
    var index: Int64 = 0
    while (index < src.size) {
        for (user in src[index].GetUsers()) {
            if (!allNewBlocks.contains(user.GetParentBlock().getOrThrow())) {
                continue
            }
            user.ReplaceOperand(src[index], dst[index])
        }
        index++
    }
}
