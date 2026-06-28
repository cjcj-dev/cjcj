package cangjie_compiler::chir

import std.collection.*

public enum MaybeInitMemberKind {
    | SUPER_MEMBER | LOCAL_MEMBER | NA
}

public class MaybeInitDomain <: GenKillDomain {
    private let ctorInitInfo: ConstructorInitInfo
    private let allocateIdxMap: HashMap<Int64, Int64>

    public init(domainSize: Int64, ctorInitInfo: ConstructorInitInfo, allocateIdxMap: HashMap<Int64, Int64>) {
        super(domainSize)
        this.ctorInitInfo = ctorInitInfo
        this.allocateIdxMap = allocateIdxMap
    }

    public func Clone(): MaybeInitDomain {
        let out = MaybeInitDomain(Size(), ctorInitInfo, allocateIdxMap)
        out.CopyFrom(this)
        return out
    }

    public func CopyFrom(rhs: MaybeInitDomain): Unit {
        CopyBaseFrom(rhs)
    }

    public func Join(rhs: MaybeInitDomain): Bool {
        return JoinStates(rhs, AnalysisKind.MAYBE)
    }

    public func IsMaybeInitedAllocation(location: Value): Option<Bool> {
        if (let Some(idx) <- allocateIdxMap.get(location.nodeId)) {
            return IsTrueAt(idx)
        }
        return None
    }

    public func IsMaybeInitedMember(memberIndex: Int64): MaybeInitMemberKind {
        if (memberIndex < ctorInitInfo.superMemberNums) {
            return if (IsTrueAt(Size() - 1)) { MaybeInitMemberKind.SUPER_MEMBER } else { MaybeInitMemberKind.NA }
        }
        let localEnd = ctorInitInfo.superMemberNums + ctorInitInfo.localMemberNums
        if (memberIndex < localEnd) {
            let localIndex = memberIndex - ctorInitInfo.superMemberNums
            return if (IsTrueAt(localIndex)) { MaybeInitMemberKind.LOCAL_MEMBER } else { MaybeInitMemberKind.NA }
        }
        return MaybeInitMemberKind.NA
    }

    public func SetAllLocalMemberInited(): Unit {
        var idx: Int64 = 0
        while (idx < ctorInitInfo.localMemberNums) {
            Gen(idx)
            idx++
        }
    }
}

public class MaybeInitResult {
    public let functionValue: Function
    private let entryStates: HashMap<Int64, MaybeInitDomain> = HashMap<Int64, MaybeInitDomain>()
    private let exitStates: HashMap<Int64, MaybeInitDomain> = HashMap<Int64, MaybeInitDomain>()

    public init(functionValue: Function) {
        this.functionValue = functionValue
    }

    public func GetEntryState(block: Block): Option<MaybeInitDomain> {
        if (let Some(state) <- entryStates.get(block.nodeId)) {
            return state.Clone()
        }
        return None
    }

    public func GetExitState(block: Block): Option<MaybeInitDomain> {
        if (let Some(state) <- exitStates.get(block.nodeId)) {
            return state.Clone()
        }
        return None
    }

    public func SetEntryState(block: Block, state: MaybeInitDomain): Unit {
        entryStates[block.nodeId] = state.Clone()
    }

    public func SetExitState(block: Block, state: MaybeInitDomain): Unit {
        exitStates[block.nodeId] = state.Clone()
    }
}

public class MaybeInitAnalysis {
    private let functionValue: Function
    private let ctorInitInfo: ConstructorInitInfo
    private let allocateIdxMap: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private var domainSize: Int64 = 0

    public init(functionValue: Function, ctorInitInfo: ConstructorInitInfo) {
        this.functionValue = functionValue
        this.ctorInitInfo = ctorInitInfo
        var allocateIdx = ctorInitInfo.localMemberNums
        if (let Some(body) <- functionValue.GetBody()) {
            allocateIdx = SaveAllocateMap(body, allocateIdx, allocateIdxMap)
        }
        domainSize = allocateIdx
        if (ctorInitInfo.superClassDef.isSome()) {
            domainSize++
        }
    }

    public func Bottom(): MaybeInitDomain {
        return MaybeInitDomain(domainSize, ctorInitInfo, allocateIdxMap)
    }

    public func Run(): MaybeInitResult {
        let result = MaybeInitResult(functionValue)
        if (let Some(body) <- functionValue.GetBody()) {
            RunOnBody(body, result)
        }
        return result
    }

    public func InitializeFuncEntryState(state: MaybeInitDomain): Unit {
        state.SetReachable(true)
    }

    public func PropagateExpressionEffect(state: MaybeInitDomain, expression: Expression): Unit {
        let kind = expression.GetExprKind()
        if (kind == ExprKind.ALLOCATE || kind == ExprKind.ALLOCATE_WITH_EXCEPTION) {
            HandleAllocateExpr(state, expression)
        } else if (kind == ExprKind.STORE) {
            HandleStoreExpr(state, expression)
        } else if (kind == ExprKind.STORE_ELEMENT_REF || kind == ExprKind.STORE_ELEMENT_BY_NAME) {
            HandleStoreElemRefExpr(state, expression)
        } else if (kind == ExprKind.APPLY || kind == ExprKind.APPLY_WITH_EXCEPTION) {
            HandleApplyExpr(state, expression)
        }
    }

    public func PropagateTerminatorEffect(state: MaybeInitDomain, terminator: Terminator): Option<Block> {
        PropagateExpressionEffect(state, terminator)
        return None
    }

    public func GetDomainSize(): Int64 {
        return domainSize
    }

    public func GetAllocateIndex(location: Value): Option<Int64> {
        return allocateIdxMap.get(location.nodeId)
    }

    private func RunOnBody(body: BlockGroup, result: MaybeInitResult): Unit {
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
                    let successorState = if (let Some(oldState) <- result.GetEntryState(successor)) { oldState } else { Bottom() }
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

    private func HandleAllocateExpr(state: MaybeInitDomain, allocate: Expression): Unit {
        if (let Some(result) <- allocate.GetResult()) {
            if (let Some(index) <- allocateIdxMap.get(result.nodeId)) {
                state.Kill(index)
            }
        }
    }

    private func HandleStoreExpr(state: MaybeInitDomain, store: Expression): Unit {
        if (store.GetNumOfOperands() >= 2) {
            let location = store.GetOperand(1)
            if (let Some(index) <- allocateIdxMap.get(location.nodeId)) {
                state.Gen(index)
            }
        }
    }

    private func HandleStoreElemRefExpr(state: MaybeInitDomain, store: Expression): Unit {
        if (let Some(storeRef) <- (store as StoreElementRef)) {
            // modify by cjmp, adapt for var init func create: use the store's top-level func
            let parentFunc = storeRef.GetTopLevelFunc() ??
                throw IllegalStateException("MaybeInitAnalysis StoreElementRef has no top-level function")
            if (let Some(memberIndex) <- IsInitialisingMemberVar(parentFunc, storeRef)) {
                if (memberIndex >= ctorInitInfo.superMemberNums) {
                    state.Gen(memberIndex - ctorInitInfo.superMemberNums)
                }
            }
        }
    }

    private func HandleApplyExpr(state: MaybeInitDomain, apply: Expression): Unit {
        if (!functionValue.IsConstructor()) {
            return
        }
        if (IsSuperConstructorCall(apply)) {
            state.Gen(domainSize - 1)
            return
        }
        if (IsDelegatingConstructorCall(apply)) {
            state.SetAllLocalMemberInited()
            if (ctorInitInfo.superClassDef.isSome()) {
                state.Gen(domainSize - 1)
            }
        }
    }

    private func IsSuperConstructorCall(apply: Expression): Bool {
        if (ctorInitInfo.superClassDef.isNone() || apply.GetNumOfOperands() == 0) {
            return false
        }
        if (let Some(callee) <- apply.GetOperand(0).AsFunction()) {
            if (!callee.IsConstructor()) {
                return false
            }
            if (let Some(parent) <- callee.GetParentCustomTypeDef()) {
                if (let Some(superDef) <- ctorInitInfo.superClassDef) {
                    return parent.nodeId == superDef.nodeId
                }
            }
        }
        return false
    }

    private func IsDelegatingConstructorCall(apply: Expression): Bool {
        if (apply.GetNumOfOperands() == 0) {
            return false
        }
        if (let Some(callee) <- apply.GetOperand(0).AsFunction()) {
            if (!callee.IsConstructor() || !callee.IsFuncWithBody()) {
                return false
            }
            if (let Some(thisDef) <- ctorInitInfo.thisCustomDef) {
                if (let Some(parent) <- callee.GetParentCustomTypeDef()) {
                    if (parent.nodeId != thisDef.nodeId) {
                        return false
                    }
                } else {
                    return false
                }
            }
            if (apply.GetNumOfOperands() > 1 && functionValue.GetNumOfParams() > 0) {
                return apply.GetOperand(1).nodeId == functionValue.GetParam(0).nodeId
            }
        }
        return false
    }
}
