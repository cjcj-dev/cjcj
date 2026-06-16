package cangjie_compiler::chir

import std.collection.*

public class GetOrThrowResultDomain {
    private var reachable: Bool = false
    private let getOrThrowResults: ArrayList<ExpressionFlatSet> = ArrayList<ExpressionFlatSet>()
    private let argIdxMap: HashMap<Int64, Int64>

    public init(argIdxMap: HashMap<Int64, Int64>) {
        this.argIdxMap = argIdxMap
        var idx: Int64 = 0
        while (idx < argIdxMap.size) {
            getOrThrowResults.add(ExpressionFlatSet())
            idx++
        }
    }

    public init(argIdxMap: HashMap<Int64, Int64>, values: ArrayList<ExpressionFlatSet>, reachable: Bool) {
        this.argIdxMap = argIdxMap
        for (value in values) {
            getOrThrowResults.add(value.Clone())
        }
        this.reachable = reachable
    }

    public func Clone(): GetOrThrowResultDomain {
        return GetOrThrowResultDomain(argIdxMap, getOrThrowResults, reachable)
    }

    public func IsReachable(): Bool {
        return reachable
    }

    public func SetReachable(value: Bool): Unit {
        reachable = value
    }

    public func SetAllTrackedToTop(): Unit {
        var idx: Int64 = 0
        while (idx < getOrThrowResults.size) {
            getOrThrowResults[idx].SetToBound(isTop: true)
            idx++
        }
    }

    public func Join(rhs: GetOrThrowResultDomain): Bool {
        if (!rhs.reachable) {
            return false
        }
        if (!reachable) {
            CopyFrom(rhs)
            return true
        }
        var changed = false
        var idx: Int64 = 0
        while (idx < getOrThrowResults.size && idx < rhs.getOrThrowResults.size) {
            changed = getOrThrowResults[idx].Join(rhs.getOrThrowResults[idx]) || changed
            idx++
        }
        return changed
    }

    public func CheckGetOrThrowResult(location: Value): Option<Expression> {
        if (let Some(idx) <- argIdxMap.get(location.nodeId)) {
            if (idx >= 0 && idx < getOrThrowResults.size) {
                let maybeExpr = getOrThrowResults[idx].GetElem()
                if (let Some(expr) <- maybeExpr) {
                    if (IsGetOrThrowFunction(expr)) {
                        return expr
                    }
                }
            }
        }
        return None
    }

    public func UpdateGetOrThrowResult(location: Value, applyExpr: Expression): Bool {
        if (let Some(idx) <- argIdxMap.get(location.nodeId)) {
            if (idx >= 0 && idx < getOrThrowResults.size) {
                if (getOrThrowResults[idx].IsBottom() || getOrThrowResults[idx].IsTop()) {
                    getOrThrowResults[idx].UpdateElem(applyExpr)
                    return true
                }
            }
        }
        return false
    }

    public func ToString(): String {
        if (!reachable) {
            return "Unreachable"
        }
        let parts = ArrayList<String>()
        for (result in getOrThrowResults) {
            parts.add(result.ToString())
        }
        return "{ " + JoinStrings(parts, ", ") + " }"
    }

    private func CopyFrom(rhs: GetOrThrowResultDomain): Unit {
        reachable = rhs.reachable
        getOrThrowResults.clear()
        for (value in rhs.getOrThrowResults) {
            getOrThrowResults.add(value.Clone())
        }
    }
}

public class GetOrThrowResultAnalysisResult {
    public let functionValue: Function
    private let argIdxMap: HashMap<Int64, Int64>
    private let trackedArgs: ArrayList<Value> = ArrayList<Value>()
    private let entryStates: HashMap<Int64, GetOrThrowResultDomain> = HashMap<Int64, GetOrThrowResultDomain>()
    private let exitStates: HashMap<Int64, GetOrThrowResultDomain> = HashMap<Int64, GetOrThrowResultDomain>()

    public init(functionValue: Function, argIdxMap: HashMap<Int64, Int64>, trackedArgs: ArrayList<Value>) {
        this.functionValue = functionValue
        this.argIdxMap = argIdxMap
        for (arg in trackedArgs) {
            this.trackedArgs.add(arg)
        }
    }

    public func GetTrackedArgs(): ArrayList<Value> {
        let out = ArrayList<Value>()
        for (arg in trackedArgs) {
            out.add(arg)
        }
        return out
    }

    public func GetTrackedArgIndex(value: Value): Option<Int64> {
        return argIdxMap.get(value.nodeId)
    }

    public func GetEntryState(block: Block): Option<GetOrThrowResultDomain> {
        if (let Some(state) <- entryStates.get(block.nodeId)) {
            return state.Clone()
        }
        return None
    }

    public func GetExitState(block: Block): Option<GetOrThrowResultDomain> {
        if (let Some(state) <- exitStates.get(block.nodeId)) {
            return state.Clone()
        }
        return None
    }

    public func SetEntryState(block: Block, state: GetOrThrowResultDomain): Unit {
        entryStates[block.nodeId] = state.Clone()
    }

    public func SetExitState(block: Block, state: GetOrThrowResultDomain): Unit {
        exitStates[block.nodeId] = state.Clone()
    }
}

public class GetOrThrowResultAnalysis {
    private let functionValue: Function
    private let debug: Bool
    private let argIdxMap: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let trackedArgs: ArrayList<Value> = ArrayList<Value>()

    public init(functionValue: Function, isDebug!: Bool = false) {
        this.functionValue = functionValue
        this.debug = isDebug
        CollectTrackedArgs()
    }

    public func IsDebug(): Bool {
        return debug
    }

    public func Bottom(): GetOrThrowResultDomain {
        return GetOrThrowResultDomain(argIdxMap)
    }

    public func Run(): GetOrThrowResultAnalysisResult {
        let result = GetOrThrowResultAnalysisResult(functionValue, argIdxMap, trackedArgs)
        if (let Some(body) <- functionValue.GetBody()) {
            RunOnBody(body, result)
        }
        return result
    }

    public func InitializeFuncEntryState(state: GetOrThrowResultDomain): Unit {
        state.SetReachable(true)
        state.SetAllTrackedToTop()
    }

    public func PropagateExpressionEffect(state: GetOrThrowResultDomain, expression: Expression): Unit {
        if (!IsGetOrThrowFunction(expression) || expression.GetNumOfOperands() < 2) {
            return
        }
        state.UpdateGetOrThrowResult(expression.GetOperand(1), expression)
    }

    public func PropagateTerminatorEffect(state: GetOrThrowResultDomain, terminator: Terminator): Option<Block> {
        PropagateExpressionEffect(state, terminator)
        return None
    }

    private func CollectTrackedArgs(): Unit {
        if (let Some(body) <- functionValue.GetBody()) {
            let blocks = CollectBlocksRecursivelyForGetOrThrow(body)
            for (block in blocks) {
                for (expr in block.GetExpressionsRef()) {
                    if (IsGetOrThrowFunction(expr) && expr.GetNumOfOperands() >= 2) {
                        let arg = expr.GetOperand(1)
                        if (argIdxMap.get(arg.nodeId).isNone()) {
                            argIdxMap[arg.nodeId] = trackedArgs.size
                            trackedArgs.add(arg)
                        }
                    }
                }
            }
        }
    }

    private func RunOnBody(body: BlockGroup, result: GetOrThrowResultAnalysisResult): Unit {
        if (let Some(entryBlock) <- body.GetEntryBlock()) {
            let entryState = Bottom()
            InitializeFuncEntryState(entryState)
            result.SetEntryState(entryBlock, entryState)
            let worklist = ArrayList<Block>()
            worklist.add(entryBlock)
            var worklistIdx: Int64 = 0
            while (worklistIdx < worklist.size) {
                let block = worklist[worklistIdx]
                worklistIdx++
                let state = if (let Some(existing) <- result.GetEntryState(block)) { existing } else { Bottom() }
                for (expr in block.GetExpressionsRef()) {
                    if (let Some(term) <- expr.AsTerminator()) {
                        PropagateTerminatorEffect(state, term)
                    } else {
                        PropagateExpressionEffect(state, expr)
                    }
                }
                result.SetExitState(block, state)
                for (successor in block.GetSuccessors()) {
                    let successorState = if (let Some(oldState) <- result.GetEntryState(successor)) {
                        oldState
                    } else {
                        Bottom()
                    }
                    if (successorState.Join(state)) {
                        result.SetEntryState(successor, successorState)
                        worklist.add(successor)
                    }
                }
            }
        }
        for (block in body.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        RunOnBody(lambdaBody, result)
                    }
                }
            }
        }
    }
}

private func CollectBlocksRecursivelyForGetOrThrow(body: BlockGroup): ArrayList<Block> {
    let blocks = ArrayList<Block>()
    AppendBlocksRecursivelyForGetOrThrow(body, blocks)
    return blocks
}

private func AppendBlocksRecursivelyForGetOrThrow(body: BlockGroup, blocks: ArrayList<Block>): Unit {
    for (block in body.GetBlocksRef()) {
        blocks.add(block)
        for (expr in block.GetExpressionsRef()) {
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                    AppendBlocksRecursivelyForGetOrThrow(lambdaBody, blocks)
                }
            }
        }
    }
}
