package cjcj::chir

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
        globalFunc = fn
        InlineImpl(fn.GetBody().getOrThrow())
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
            let cast = TypeCastOrBoxIfNeeded(newLoad.GetResult().getOrThrow(), resOld.GetType().getOrThrow(), builder,
                newLoad.GetParentBlock().getOrThrow(), INVALID_LOCATION)
            if (!refEq(cast, newLoad.GetResult().getOrThrow())) {
                CJC_ASSERT(cast.IsLocalVar())
                cast.AsLocalVar().getOrThrow().GetExpr().getOrThrow().MoveBefore(user)
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
            let _ = builder.CreateGoTo(block2, exitBlock)
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
        if (user.GetExprKind() == ExprKind.APPLY || user.GetExprKind() == ExprKind.APPLY_WITH_EXCEPTION) {
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
