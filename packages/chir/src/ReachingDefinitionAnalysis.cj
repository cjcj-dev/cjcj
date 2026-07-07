package cangjie_compiler::chir

import std.collection.*

public class ReachingDefinitionDomain <: AbstractDomain<ReachingDefinitionDomain> {
    private let reachingDefs: ArrayList<ExpressionFlatSet> = ArrayList<ExpressionFlatSet>()
    private let reachingLoadDefs: ArrayList<ExpressionFlatSet> = ArrayList<ExpressionFlatSet>()
    private let allocateIdxMap: HashMap<Int64, Int64>

    public init(allocateIdxMap: HashMap<Int64, Int64>) {
        super()
        this.allocateIdxMap = allocateIdxMap
        var idx: Int64 = 0
        while (idx < allocateIdxMap.size) {
            reachingDefs.add(ExpressionFlatSet())
            reachingLoadDefs.add(ExpressionFlatSet())
            idx++
        }
    }

    public init(allocateIdxMap: HashMap<Int64, Int64>, reachingDefs: ArrayList<ExpressionFlatSet>,
        reachingLoadDefs: ArrayList<ExpressionFlatSet>, kind: ReachableKind) {
        super()
        this.allocateIdxMap = allocateIdxMap
        for (slot in reachingDefs) {
            this.reachingDefs.add(slot.Clone())
        }
        for (slot in reachingLoadDefs) {
            this.reachingLoadDefs.add(slot.Clone())
        }
        this.kind = kind
    }

    public override func Clone(): ReachingDefinitionDomain {
        return ReachingDefinitionDomain(allocateIdxMap, reachingDefs, reachingLoadDefs, kind)
    }

    public func IsReachable(): Bool {
        return !IsBottom()
    }

    public func SetReachable(value: Bool): Unit {
        kind = if (value) { ReachableKind.REACHABLE } else { ReachableKind.UNREACHABLE }
    }

    public func SetAllTrackedToTop(): Unit {
        var idx: Int64 = 0
        while (idx < reachingDefs.size) {
            reachingDefs[idx].SetToBound(isTop: true)
            reachingLoadDefs[idx].SetToBound(isTop: true)
            idx++
        }
    }

    public override func Join(rhs: ReachingDefinitionDomain): Bool {
        kind = ReachableKind.REACHABLE
        var changed = false
        var idx: Int64 = 0
        while (idx < reachingDefs.size && idx < rhs.reachingDefs.size) {
            let defChanged = reachingDefs[idx].Join(rhs.reachingDefs[idx])
            let loadChanged = reachingLoadDefs[idx].Join(rhs.reachingLoadDefs[idx])
            changed = changed || defChanged || loadChanged
            idx++
        }
        return changed
    }

    public func CheckReachingDef(location: Value): Option<Expression> {
        if (let Some(idx) <- allocateIdxMap.get(location.nodeId)) {
            if (idx >= 0 && idx < reachingDefs.size) {
                let maybeExpr = reachingDefs[idx].GetElem()
                if (let Some(expr) <- maybeExpr) {
                    if (expr.GetExprKind() == ExprKind.STORE) {
                        return expr
                    }
                }
            }
        }
        return None
    }

    public func CheckReachingLoadDef(location: Value): Option<Expression> {
        if (let Some(idx) <- allocateIdxMap.get(location.nodeId)) {
            if (idx >= 0 && idx < reachingLoadDefs.size) {
                let maybeExpr = reachingLoadDefs[idx].GetElem()
                if (let Some(expr) <- maybeExpr) {
                    if (expr.GetExprKind() == ExprKind.LOAD) {
                        return expr
                    }
                }
            }
        }
        return None
    }

    public func UpdateStore(location: Value, storeExpr: Expression): Bool {
        if (let Some(idx) <- allocateIdxMap.get(location.nodeId)) {
            if (idx >= 0 && idx < reachingDefs.size) {
                reachingDefs[idx].UpdateElem(storeExpr)
                reachingLoadDefs[idx].SetToBound(isTop: true)
                return true
            }
        }
        return false
    }

    public func UpdateLoad(location: Value, loadExpr: Expression): Bool {
        if (let Some(idx) <- allocateIdxMap.get(location.nodeId)) {
            if (idx >= 0 && idx < reachingLoadDefs.size && reachingLoadDefs[idx].IsTop()) {
                reachingLoadDefs[idx].UpdateElem(loadExpr)
                return true
            }
        }
        return false
    }

    public func Invalidate(location: Value): Bool {
        if (let Some(idx) <- allocateIdxMap.get(location.nodeId)) {
            if (idx >= 0 && idx < reachingDefs.size) {
                reachingDefs[idx].SetToBound(isTop: true)
                reachingLoadDefs[idx].SetToBound(isTop: true)
                return true
            }
        }
        return false
    }

    public override func ToString(): String {
        if (IsBottom()) {
            return "Unreachable"
        }
        let defParts = ArrayList<String>()
        let loadParts = ArrayList<String>()
        for (slot in reachingDefs) {
            defParts.add(slot.ToString())
        }
        for (slot in reachingLoadDefs) {
            loadParts.add(slot.ToString())
        }
        return "{ " + JoinStrings(defParts, ", ") + " } { " + JoinStrings(loadParts, ", ") + " }"
    }
}

public class ReachingDefinitionResult {
    public let functionValue: Function
    private let trackedAllocations: ArrayList<Value> = ArrayList<Value>()
    private let allocateIdxMap: HashMap<Int64, Int64>
    private let entryStates: HashMap<Int64, ReachingDefinitionDomain> = HashMap<Int64, ReachingDefinitionDomain>()
    private let exitStates: HashMap<Int64, ReachingDefinitionDomain> = HashMap<Int64, ReachingDefinitionDomain>()

    public init(functionValue: Function, allocateIdxMap: HashMap<Int64, Int64>, trackedAllocations: ArrayList<Value>) {
        this.functionValue = functionValue
        this.allocateIdxMap = allocateIdxMap
        for (allocation in trackedAllocations) {
            this.trackedAllocations.add(allocation)
        }
    }

    public func GetTrackedAllocations(): ArrayList<Value> {
        let out = ArrayList<Value>()
        for (allocation in trackedAllocations) {
            out.add(allocation)
        }
        return out
    }

    public func GetTrackedAllocationIndex(value: Value): Option<Int64> {
        return allocateIdxMap.get(value.nodeId)
    }

    public func GetEntryState(block: Block): Option<ReachingDefinitionDomain> {
        if (let Some(state) <- entryStates.get(block.nodeId)) {
            return state.Clone()
        }
        return None
    }

    public func GetExitState(block: Block): Option<ReachingDefinitionDomain> {
        if (let Some(state) <- exitStates.get(block.nodeId)) {
            return state.Clone()
        }
        return None
    }

    public func SetEntryState(block: Block, state: ReachingDefinitionDomain): Unit {
        entryStates[block.nodeId] = state.Clone()
    }

    public func SetExitState(block: Block, state: ReachingDefinitionDomain): Unit {
        exitStates[block.nodeId] = state.Clone()
    }
}

public class ReachingDefinitionAnalysis <: Analysis<ReachingDefinitionDomain> {
    private let functionValue: Function
    private let allocateIdxMap: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let trackedAllocations: ArrayList<Value> = ArrayList<Value>()

    public init(functionValue: Function) {
        super(functionValue)
        this.functionValue = functionValue
        CollectTrackedAllocations()
    }

    public override func Bottom(): ReachingDefinitionDomain {
        return ReachingDefinitionDomain(allocateIdxMap)
    }

    public func Run(): ReachingDefinitionResult {
        let result = ReachingDefinitionResult(functionValue, allocateIdxMap, trackedAllocations)
        if (let Some(body) <- functionValue.GetBody()) {
            RunOnBody(body, result)
        }
        return result
    }

    public override func InitializeFuncEntryState(state: ReachingDefinitionDomain): Unit {
        state.SetReachable(true)
        state.SetAllTrackedToTop()
    }

    public override func PropagateExpressionEffect(state: ReachingDefinitionDomain, expression: Expression): Unit {
        let kind = expression.GetExprKind()
        if (kind == ExprKind.STORE) {
            HandleStoreExpr(state, expression)
        } else if (kind == ExprKind.LOAD) {
            HandleLoadExpr(state, expression)
        } else if (kind == ExprKind.GET_ELEMENT_REF) {
            HandleGetElemRefExpr(state, expression)
        } else if (kind == ExprKind.STORE_ELEMENT_REF) {
            HandleStoreElemRefExpr(state, expression)
        } else if (kind == ExprKind.APPLY) {
            HandleApplyExpr(state, expression)
        } else if (kind == ExprKind.INTRINSIC) {
            HandleIntrinsicExpr(state, expression)
        }
    }

    public override func PropagateTerminatorEffect(state: ReachingDefinitionDomain, terminator: Terminator): Option<Block> {
        let kind = terminator.GetExprKind()
        if (kind == ExprKind.APPLY_WITH_EXCEPTION) {
            HandleApplyExpr(state, terminator)
        } else if (kind == ExprKind.INTRINSIC_WITH_EXCEPTION) {
            HandleIntrinsicExpr(state, terminator)
        }
        return None
    }

    public override func HandleVarStateCapturedByLambda(state: ReachingDefinitionDomain, lambda: Lambda): Unit {
        for (captured in GetLambdaCapturedVarsRecursively(lambda)) {
            state.Invalidate(captured)
        }
    }

    private func CollectTrackedAllocations(): Unit {
        if (let Some(body) <- functionValue.GetBody()) {
            let blocks = CollectBlocksRecursively(body)
            for (block in blocks) {
                for (expr in block.GetExpressionsRef()) {
                    if (expr.GetExprKind() == ExprKind.ALLOCATE || expr.GetExprKind() == ExprKind.ALLOCATE_WITH_EXCEPTION) {
                        if (let Some(result) <- expr.GetResult()) {
                            if (CanTrackAllocation(result)) {
                                allocateIdxMap[result.nodeId] = trackedAllocations.size
                                trackedAllocations.add(result)
                            }
                        }
                    }
                }
            }
        }
    }

    private func RunOnBody(body: BlockGroup, result: ReachingDefinitionResult): Unit {
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

    private func HandleStoreExpr(state: ReachingDefinitionDomain, store: Expression): Unit {
        if (store.GetNumOfOperands() >= 2) {
            state.UpdateStore(store.GetOperand(1), store)
        }
    }

    private func HandleLoadExpr(state: ReachingDefinitionDomain, load: Expression): Unit {
        if (load.GetNumOfOperands() >= 1) {
            state.UpdateLoad(load.GetOperand(0), load)
        }
    }

    private func HandleGetElemRefExpr(state: ReachingDefinitionDomain, getElemRef: Expression): Unit {
        if (getElemRef.GetNumOfOperands() >= 1) {
            let location = getElemRef.GetOperand(0)
            if (IsTrackedStructRef(location)) {
                if (let Some(result) <- getElemRef.GetResult()) {
                    if (!result.TestAttr(Attribute.READONLY)) {
                        state.Invalidate(location)
                    }
                } else {
                    state.Invalidate(location)
                }
            }
        }
    }

    private func HandleStoreElemRefExpr(state: ReachingDefinitionDomain, storeElemRef: Expression): Unit {
        if (storeElemRef.GetNumOfOperands() >= 2) {
            let location = storeElemRef.GetOperand(1)
            if (IsTrackedStructRef(location)) {
                state.Invalidate(location)
            }
        }
    }

    private func HandleApplyExpr(state: ReachingDefinitionDomain, apply: Expression): Unit {
        if (apply.GetNumOfOperands() > 1) {
            if (let Some(callee) <- apply.GetOperand(0).AsFunction()) {
                if (callee.TestAttr(Attribute.MUT)) {
                    let receiver = apply.GetOperand(1)
                    if (IsTrackedStructRef(receiver)) {
                        state.Invalidate(receiver)
                    }
                }
            }
        }
    }

    private func HandleIntrinsicExpr(state: ReachingDefinitionDomain, intrinsic: Expression): Unit {
        if (GetIntrinsicKind(intrinsic) != IntrinsicKind.INOUT_PARAM) {
            return
        }
        if (intrinsic.GetNumOfOperands() == 1) {
            state.Invalidate(intrinsic.GetOperand(0))
        }
    }

    private func CanTrackAllocation(value: Value): Bool {
        if (let Some(valueTy) <- value.GetType()) {
            let allocatedTy = valueTy.StripAllRefs()
            if (allocatedTy.IsClass() || allocatedTy.IsVArray() || allocatedTy.IsGeneric()) {
                return false
            }
            if (let Some(structTy) <- (allocatedTy as StructType)) {
                if (structTy.GetStructDef().IsCStruct()) {
                    return false
                }
            }
        }
        return !allocateIdxMap.contains(value.nodeId)
    }

    private func IsTrackedStructRef(value: Value): Bool {
        if (!allocateIdxMap.contains(value.nodeId)) {
            return false
        }
        if (let Some(valueTy) <- value.GetType()) {
            return valueTy.StripAllRefs().IsStruct()
        }
        return false
    }
}

private func GetIntrinsicKind(expr: Expression): IntrinsicKind {
    if (let Some(intrinsic) <- (expr as Intrinsic)) {
        return intrinsic.GetIntrinsicKind()
    }
    if (let Some(intrinsicWithException) <- (expr as IntrinsicWithException)) {
        return intrinsicWithException.GetIntrinsicKind()
    }
    return IntrinsicKind.NOT_INTRINSIC
}

private func CollectBlocksRecursively(body: BlockGroup): ArrayList<Block> {
    let out = ArrayList<Block>()
    CollectBlocksRecursively(body, out)
    return out
}

private func CollectBlocksRecursively(body: BlockGroup, out: ArrayList<Block>): Unit {
    for (block in body.GetBlocksRef()) {
        var hasBlock = false
        for (item in out) {
            if (refEq(item, block)) {
                hasBlock = true
                break
            }
        }
        if (!hasBlock) {
            out.add(block)
        }
        for (expr in block.GetExpressionsRef()) {
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                    CollectBlocksRecursively(lambdaBody, out)
                }
            }
        }
    }
}
