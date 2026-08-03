package cjcj::chir

import cjcj::utils.CJC_ASSERT
import std.collection.*

public class GetOrThrowResultDomain <: AbstractDomain<GetOrThrowResultDomain> {
    private let getOrThrowResults: ArrayList<ExpressionFlatSet> = ArrayList<ExpressionFlatSet>()
    private let argIdxMap: HashMap<Value, Int64>

    public init(argIdxMap: HashMap<Value, Int64>) {
        super()
        this.argIdxMap = argIdxMap
        var idx: Int64 = 0
        while (idx < argIdxMap.size) {
            getOrThrowResults.add(ExpressionFlatSet())
            idx++
        }
    }

    private init(argIdxMap: HashMap<Value, Int64>, values: ArrayList<ExpressionFlatSet>, reachableKind: ReachableKind) {
        super()
        this.argIdxMap = argIdxMap
        kind = reachableKind
        for (value in values) {
            getOrThrowResults.add(value.Clone())
        }
    }

    public override func Clone(): GetOrThrowResultDomain {
        return GetOrThrowResultDomain(argIdxMap, getOrThrowResults, kind)
    }

    public override func CopyFrom(rhs: GetOrThrowResultDomain): Unit {
        kind = rhs.kind
        getOrThrowResults.clear()
        for (value in rhs.getOrThrowResults) {
            getOrThrowResults.add(value.Clone())
        }
    }

    public func SetReachable(value: Bool): Unit {
        kind = if (value) { ReachableKind.REACHABLE } else { ReachableKind.UNREACHABLE }
    }

    public func SetAllTrackedToTop(): Unit {
        for (result in getOrThrowResults) {
            result.SetToBound(isTop: true)
        }
    }

    public override func Join(rhs: GetOrThrowResultDomain): Bool {
        kind = ReachableKind.REACHABLE
        var changed = false
        var idx: Int64 = 0
        while (idx < getOrThrowResults.size) {
            changed = getOrThrowResults[idx].Join(rhs.getOrThrowResults[idx]) || changed
            idx++
        }
        return changed
    }

    public func CheckGetOrThrowResult(location: Value): Option<Expression> {
        if (let Some(idx) <- argIdxMap.get(location)) {
            return getOrThrowResults[idx].GetElem()
        }
        return None
    }

    public func UpdateGetOrThrowResult(location: Value, applyExpr: Expression): Unit {
        if (let Some(idx) <- argIdxMap.get(location)) {
            if (getOrThrowResults[idx].IsBottom() || getOrThrowResults[idx].IsTop()) {
                getOrThrowResults[idx].UpdateElem(applyExpr)
            }
        }
    }

    public override func ToString(): String {
        if (IsBottom()) {
            return "Unreachable"
        }
        let parts = ArrayList<String>()
        for (result in getOrThrowResults) {
            parts.add(result.ToString())
        }
        return "{ " + JoinStrings(parts, ", ") + ", }"
    }
}

public class GetOrThrowResultAnalysis <: Analysis<GetOrThrowResultDomain> {
    private let argIdxMap: HashMap<Value, Int64> = HashMap<Value, Int64>()

    public init(functionValue: Function, isDebug!: Bool = false) {
        super(functionValue, isDebug: isDebug)
        let body = functionValue.GetBody() ??
            throw IllegalArgumentException("GetOrThrowResultAnalysis requires a function body")
        var argIdx: Int64 = 0
        for (block in body.GetBlocks()) {
            for (expr in block.GetExpressions()) {
                if (IsGetOrThrowFunction(expr)) {
                    CJC_ASSERT(expr.GetNumOfOperands() > 1)
                    let arg = expr.GetOperand(1)
                    if (!argIdxMap.contains(arg)) {
                        argIdxMap[arg] = argIdx
                        argIdx++
                    }
                }
            }
        }
    }

    public override func GetAnalysisName(): String {
        return "getOrThrow-result"
    }

    public override func GetBlockLimit(): Option<UInt32> {
        return None
    }

    public override func Bottom(): GetOrThrowResultDomain {
        return GetOrThrowResultDomain(argIdxMap)
    }

    public override func InitializeFuncEntryState(state: GetOrThrowResultDomain): Unit {
        state.SetReachable(true)
        state.SetAllTrackedToTop()
    }

    public override func PropagateExpressionEffect(state: GetOrThrowResultDomain, expression: Expression): Unit {
        if (!IsGetOrThrowFunction(expression)) {
            return
        }
        CJC_ASSERT(expression.GetNumOfOperands() > 1)
        state.UpdateGetOrThrowResult(expression.GetOperand(1), expression)
    }

    public override func PropagateTerminatorEffect(
        state: GetOrThrowResultDomain,
        terminator: Terminator
    ): Option<Block> {
        let _ = state
        let _ = terminator
        return None
    }
}
