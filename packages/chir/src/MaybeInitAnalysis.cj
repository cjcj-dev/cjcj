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
        throw IllegalStateException("MaybeInitDomain member index out of range")
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
        domainSize = ctorInitInfo.localMemberNums + allocateIdx
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
        if (kind == ExprKind.ALLOCATE) {
            HandleAllocateExpr(state, expression)
        } else if (kind == ExprKind.STORE) {
            HandleStoreExpr(state, expression)
        } else if (kind == ExprKind.STORE_ELEMENT_REF) {
            HandleStoreElemRefExpr(state, expression)
        } else if (kind == ExprKind.APPLY) {
            HandleApplyExpr(state, expression)
        }
    }

    public func PropagateTerminatorEffect(state: MaybeInitDomain, terminator: Terminator): Option<Block> {
        let _ = state
        let _ = terminator
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
        let allocateExpr = (allocate as Allocate) ?? throw IllegalStateException("MaybeInitAnalysis expected Allocate")
        let result = allocateExpr.GetResult() ?? throw IllegalStateException("MaybeInitAnalysis Allocate has no result")
        if (let Some(index) <- allocateIdxMap.get(result.nodeId)) {
            state.Kill(index)
        }
    }

    private func HandleStoreExpr(state: MaybeInitDomain, store: Expression): Unit {
        let storeExpr = (store as Store) ?? throw IllegalStateException("MaybeInitAnalysis expected Store")
        let location = storeExpr.GetLocation()
        if (let Some(index) <- allocateIdxMap.get(location.nodeId)) {
            state.Gen(index)
        }
    }

    private func HandleStoreElemRefExpr(state: MaybeInitDomain, store: Expression): Unit {
        let storeRef = (store as StoreElementRef) ??
            throw IllegalStateException("MaybeInitAnalysis expected StoreElementRef")
        // modify by cjmp, adapt for var init func create: use the store's top-level func
        let parentFunc = storeRef.GetTopLevelFunc() ??
            throw IllegalStateException("MaybeInitAnalysis StoreElementRef has no top-level function")
        let memberIdxOpt = IsInitialisingMemberVar(parentFunc, storeRef)
        if (memberIdxOpt.isNone()) {
            return
        }
        let memberIndex = memberIdxOpt.getOrThrow()
        if (memberIndex >= ctorInitInfo.superMemberNums + ctorInitInfo.localMemberNums) {
            throw IllegalStateException("MaybeInitAnalysis member index out of range")
        }
        if (memberIndex < ctorInitInfo.superMemberNums) {
            return
        }
        state.Gen(memberIndex - ctorInitInfo.superMemberNums)
    }

    private func HandleApplyExpr(state: MaybeInitDomain, apply: Expression): Unit {
        if (!functionValue.IsConstructor()) {
            return
        }
        let applyExpr = (apply as Apply) ?? throw IllegalStateException("MaybeInitAnalysis expected Apply")
        if (applyExpr.IsSuperCall()) {
            state.Gen(domainSize - 1)
            return
        }
        let callee = applyExpr.GetCallee()
        if (callee.IsFuncWithBody()) {
            if (let Some(calleeFunc) <- callee.AsFunction()) {
                let outerDefOpt = calleeFunc.GetOuterDeclaredOrExtendedDef()
                let sameOuterDef = match ((outerDefOpt, ctorInitInfo.thisCustomDef)) {
                    case (Some(left), Some(right)) => left.nodeId == right.nodeId
                    case (None, None) => true
                    case _ => false
                }
                if (calleeFunc.IsConstructor() && sameOuterDef &&
                    applyExpr.GetArgs()[0].nodeId == functionValue.GetParam(0).nodeId) {
                    state.SetAllLocalMemberInited()
                    if (ctorInitInfo.superClassDef.isSome()) {
                        state.Gen(domainSize - 1)
                    }
                }
            }
        }
    }
}
