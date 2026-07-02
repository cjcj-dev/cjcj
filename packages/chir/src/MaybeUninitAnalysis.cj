package cangjie_compiler::chir

import std.collection.*

public class ConstructorInitInfo {
    public var thisCustomDef: Option<CustomTypeDef> = None
    public var superClassDef: Option<ClassDef> = None
    public var superMemberNums: Int64 = 0
    public var localMemberNums: Int64 = 0

    public init() {}

    public init(thisCustomDef: Option<CustomTypeDef>, superClassDef: Option<ClassDef>,
        superMemberNums!: Int64 = 0, localMemberNums!: Int64 = 0) {
        this.thisCustomDef = thisCustomDef
        this.superClassDef = superClassDef
        this.superMemberNums = superMemberNums
        this.localMemberNums = localMemberNums
    }
}

public enum MaybeUninitMemberKind {
    | SUPER_MEMBER | LOCAL_MEMBER | NA
}

public class MaybeUninitDomain <: GenKillDomain<MaybeUninitDomain> {
    private let ctorInitInfo: ConstructorInitInfo
    private let allocateIdxMap: HashMap<Int64, Int64>
    let maybeInitedPos: ArrayList<TreeSet<Int64>> = ArrayList<TreeSet<Int64>>()

    public init(domainSize: Int64, ctorInitInfo: ConstructorInitInfo, allocateIdxMap: HashMap<Int64, Int64>) {
        super(domainSize)
        this.ctorInitInfo = ctorInitInfo
        this.allocateIdxMap = allocateIdxMap
        var idx: Int64 = 0
        while (idx < domainSize) {
            maybeInitedPos.add(TreeSet<Int64>())
            idx++
        }
    }

    public override func Clone(): MaybeUninitDomain {
        let out = MaybeUninitDomain(Size(), ctorInitInfo, allocateIdxMap)
        out.CopyFrom(this)
        return out
    }

    public func CopyFrom(rhs: MaybeUninitDomain): Unit {
        CopyBaseFrom(rhs)
        maybeInitedPos.clear()
        for (positions in rhs.maybeInitedPos) {
            let copied = TreeSet<Int64>()
            for (line in positions) {
                copied.add(line)
            }
            maybeInitedPos.add(copied)
        }
    }

    public override func Join(rhs: MaybeUninitDomain): Bool {
        var idx: Int64 = 0
        while (idx < maybeInitedPos.size) {
            for (line in rhs.maybeInitedPos[idx]) {
                maybeInitedPos[idx].add(line)
            }
            idx++
        }
        return JoinStates(rhs, AnalysisKind.MAYBE)
    }

    public func IsMaybeUninitedAllocation(location: Value): Option<Bool> {
        if (let Some(idx) <- allocateIdxMap.get(location.nodeId)) {
            return IsTrueAt(idx)
        }
        return None
    }

    public func GetMaybeInitedPos(location: Value): TreeSet<Int64> {
        let idx = allocateIdxMap.get(location.nodeId) ??
            throw IllegalStateException("MaybeUninitDomain expected allocation index")
        return maybeInitedPos[idx]
    }

    public func IsMaybeUninitedMember(memberIndex: Int64): MaybeUninitMemberKind {
        if (memberIndex < ctorInitInfo.superMemberNums) {
            return if (IsTrueAt(Size() - 1)) { MaybeUninitMemberKind.SUPER_MEMBER } else { MaybeUninitMemberKind.NA }
        }
        let localEnd = ctorInitInfo.superMemberNums + ctorInitInfo.localMemberNums
        if (memberIndex < localEnd) {
            let localIndex = memberIndex - ctorInitInfo.superMemberNums
            return if (IsTrueAt(localIndex)) { MaybeUninitMemberKind.LOCAL_MEMBER } else { MaybeUninitMemberKind.NA }
        }
        throw IllegalStateException("MaybeUninitDomain member index out of range")
    }

    public func GetMaybeInitedPos(memberIndex: Int64): TreeSet<Int64> {
        if (memberIndex < ctorInitInfo.superMemberNums) {
            throw IllegalStateException("MaybeUninitDomain expected local member index")
        }
        return maybeInitedPos[memberIndex - ctorInitInfo.superMemberNums]
    }

    public func GetMaybeUninitedLocalMembers(): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        var idx: Int64 = 0
        while (idx < ctorInitInfo.localMemberNums) {
            if (IsTrueAt(idx)) {
                out.add(idx + ctorInitInfo.superMemberNums)
            }
            idx++
        }
        return out
    }

    public func SetAllLocalMemberInited(): Unit {
        var idx: Int64 = 0
        while (idx < ctorInitInfo.localMemberNums) {
            Kill(idx)
            idx++
        }
    }

}

public class MaybeUninitAnalysis <: Analysis<MaybeUninitDomain> {
    private let functionValue: Function
    private let ctorInitInfo: ConstructorInitInfo
    private let allocateIdxMap: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private var domainSize: Int64 = 0

    public init(functionValue: Function, ctorInitInfo: ConstructorInitInfo) {
        super(functionValue)
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

    public override func Bottom(): MaybeUninitDomain {
        return MaybeUninitDomain(domainSize, ctorInitInfo, allocateIdxMap)
    }

    public override func InitializeFuncEntryState(state: MaybeUninitDomain): Unit {
        state.SetReachable(true)
        state.GenAll()
    }

    public override func PropagateExpressionEffect(state: MaybeUninitDomain, expression: Expression): Unit {
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

    public override func PropagateTerminatorEffect(state: MaybeUninitDomain, terminator: Terminator): Option<Block> {
        let _ = state
        let _ = terminator
        return None
    }

    private func HandleAllocateExpr(state: MaybeUninitDomain, allocate: Expression): Unit {
        let allocateExpr = (allocate as Allocate) ?? throw IllegalStateException("MaybeUninitAnalysis expected Allocate")
        let result = allocateExpr.GetResult() ?? throw IllegalStateException("MaybeUninitAnalysis Allocate has no result")
        if (let Some(index) <- allocateIdxMap.get(result.nodeId)) {
            state.Gen(index)
        }
    }

    private func HandleStoreExpr(state: MaybeUninitDomain, store: Expression): Unit {
        let storeExpr = (store as Store) ?? throw IllegalStateException("MaybeUninitAnalysis expected Store")
        let location = storeExpr.GetLocation()
        if (let Some(index) <- allocateIdxMap.get(location.nodeId)) {
            state.Kill(index)
            let debugLoc = store.GetDebugLocation()
            state.maybeInitedPos[index].add(Int64(debugLoc.GetBeginPos().line))
        }
    }

    private func HandleStoreElemRefExpr(state: MaybeUninitDomain, store: Expression): Unit {
        let storeRef = (store as StoreElementRef) ??
            throw IllegalStateException("MaybeUninitAnalysis expected StoreElementRef")
        let parentFunc = storeRef.GetTopLevelFunc() ??
            throw IllegalStateException("MaybeUninitAnalysis StoreElementRef has no top-level function")
        let memberIdxOpt = IsInitialisingMemberVar(parentFunc, storeRef)
        if (memberIdxOpt.isNone()) {
            return
        }
        let memberIndex = memberIdxOpt.getOrThrow()
        if (memberIndex >= ctorInitInfo.superMemberNums + ctorInitInfo.localMemberNums) {
            throw IllegalStateException("MaybeUninitAnalysis member index out of range")
        }
        if (memberIndex < ctorInitInfo.superMemberNums) {
            return
        }
        let stateIndex = memberIndex - ctorInitInfo.superMemberNums
        state.Kill(stateIndex)
        let debugLoc = store.GetDebugLocation()
        state.maybeInitedPos[stateIndex].add(Int64(debugLoc.GetBeginPos().line))
    }

    private func HandleApplyExpr(state: MaybeUninitDomain, apply: Expression): Unit {
        if (!functionValue.IsConstructor()) {
            return
        }
        let applyExpr = (apply as Apply) ?? throw IllegalStateException("MaybeUninitAnalysis expected Apply")
        if (applyExpr.IsSuperCall()) {
            state.Kill(domainSize - 1)
            return
        }
        let callee = applyExpr.GetCallee()
        if (callee.IsFuncWithBody()) {
            if (let Some(calleeFunc) <- callee.AsFunction()) {
                let outerDefOpt = calleeFunc.GetOuterDeclaredOrExtendedDef()
                let sameOuterDef = match ((outerDefOpt, ctorInitInfo.thisCustomDef)) {
                    case (Some(left), Some(right)) => refEq(left, right)
                    case (None, None) => true
                    case _ => false
                }
                if (calleeFunc.IsConstructor() && sameOuterDef &&
                    applyExpr.GetArgs()[0].nodeId == functionValue.GetParam(0).nodeId) {
                    state.SetAllLocalMemberInited()
                    if (ctorInitInfo.superClassDef.isSome()) {
                        state.Kill(domainSize - 1)
                    }
                }
            }
        }
    }
}

public func SaveAllocateMap(body: BlockGroup, allocateIdx: Int64, allocateIdxMap: HashMap<Int64, Int64>): Int64 {
    var nextIdx = allocateIdx
    for (block in body.GetBlocksRef()) {
        for (expr in block.GetExpressionsRef()) {
            let kind = expr.GetExprKind()
            if (kind == ExprKind.ALLOCATE || kind == ExprKind.ALLOCATE_WITH_EXCEPTION) {
                if (let Some(result) <- expr.GetResult()) {
                    if (result.GetDebugExpr().isSome()) {
                        allocateIdxMap[result.nodeId] = nextIdx
                        nextIdx++
                    }
                }
            }
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                    nextIdx = SaveAllocateMap(lambdaBody, nextIdx, allocateIdxMap)
                }
            }
        }
    }
    return nextIdx
}
