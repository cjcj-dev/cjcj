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

public class MaybeUninitDomain <: GenKillDomain {
    private let ctorInitInfo: ConstructorInitInfo
    private let allocateIdxMap: HashMap<Int64, Int64>
    private let maybeInitedPos: ArrayList<ArrayList<Int64>> = ArrayList<ArrayList<Int64>>()

    public init(domainSize: Int64, ctorInitInfo: ConstructorInitInfo, allocateIdxMap: HashMap<Int64, Int64>) {
        super(domainSize)
        this.ctorInitInfo = ctorInitInfo
        this.allocateIdxMap = allocateIdxMap
        var idx: Int64 = 0
        while (idx < domainSize) {
            maybeInitedPos.add(ArrayList<Int64>())
            idx++
        }
    }

    public func Clone(): MaybeUninitDomain {
        let out = MaybeUninitDomain(Size(), ctorInitInfo, allocateIdxMap)
        out.CopyFrom(this)
        return out
    }

    public func CopyFrom(rhs: MaybeUninitDomain): Unit {
        CopyBaseFrom(rhs)
        maybeInitedPos.clear()
        for (positions in rhs.maybeInitedPos) {
            let copied = ArrayList<Int64>()
            for (line in positions) {
                copied.add(line)
            }
            maybeInitedPos.add(copied)
        }
    }

    public func Join(rhs: MaybeUninitDomain): Bool {
        var idx: Int64 = 0
        while (idx < maybeInitedPos.size && idx < rhs.maybeInitedPos.size) {
            for (line in rhs.maybeInitedPos[idx]) {
                AddLineIfMissing(maybeInitedPos[idx], line)
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

    public func GetMaybeInitedPos(location: Value): ArrayList<Int64> {
        if (let Some(idx) <- allocateIdxMap.get(location.nodeId)) {
            return CopyIntListAt(idx)
        }
        return ArrayList<Int64>()
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
        return MaybeUninitMemberKind.NA
    }

    public func GetMaybeInitedPos(memberIndex: Int64): ArrayList<Int64> {
        if (memberIndex < ctorInitInfo.superMemberNums) {
            return ArrayList<Int64>()
        }
        return CopyIntListAt(memberIndex - ctorInitInfo.superMemberNums)
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

    public func RecordMaybeInitedPos(index: Int64, line: Int64): Unit {
        if (index >= 0 && index < maybeInitedPos.size && line > 0) {
            AddLineIfMissing(maybeInitedPos[index], line)
        }
    }

    private func CopyIntListAt(index: Int64): ArrayList<Int64> {
        let out = ArrayList<Int64>()
        if (index >= 0 && index < maybeInitedPos.size) {
            for (line in maybeInitedPos[index]) {
                out.add(line)
            }
        }
        return out
    }
}

public class MaybeUninitResult {
    public let functionValue: Function
    private let entryStates: HashMap<Int64, MaybeUninitDomain> = HashMap<Int64, MaybeUninitDomain>()
    private let exitStates: HashMap<Int64, MaybeUninitDomain> = HashMap<Int64, MaybeUninitDomain>()

    public init(functionValue: Function) {
        this.functionValue = functionValue
    }

    public func GetEntryState(block: Block): Option<MaybeUninitDomain> {
        if (let Some(state) <- entryStates.get(block.nodeId)) {
            return state.Clone()
        }
        return None
    }

    public func GetExitState(block: Block): Option<MaybeUninitDomain> {
        if (let Some(state) <- exitStates.get(block.nodeId)) {
            return state.Clone()
        }
        return None
    }

    public func SetEntryState(block: Block, state: MaybeUninitDomain): Unit {
        entryStates[block.nodeId] = state.Clone()
    }

    public func SetExitState(block: Block, state: MaybeUninitDomain): Unit {
        exitStates[block.nodeId] = state.Clone()
    }
}

public class MaybeUninitAnalysis {
    private let functionValue: Function
    private let ctorInitInfo: ConstructorInitInfo
    private let allocateIdxMap: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private var domainSize: Int64 = 0

    public init(functionValue: Function, ctorInitInfo: ConstructorInitInfo) {
        this.functionValue = functionValue
        this.ctorInitInfo = ctorInitInfo
        var allocateIdx = ctorInitInfo.localMemberNums
        if (let Some(body) <- functionValue.GetBody()) {
            SaveAllocateMap(body, allocateIdx, allocateIdxMap)
        }
        domainSize = allocateIdx
        if (ctorInitInfo.superClassDef.isSome()) {
            domainSize++
        }
    }

    public func Bottom(): MaybeUninitDomain {
        return MaybeUninitDomain(domainSize, ctorInitInfo, allocateIdxMap)
    }

    public func Run(): MaybeUninitResult {
        let result = MaybeUninitResult(functionValue)
        if (let Some(body) <- functionValue.GetBody()) {
            RunOnBody(body, result)
        }
        return result
    }

    public func InitializeFuncEntryState(state: MaybeUninitDomain): Unit {
        state.SetReachable(true)
        state.GenAll()
    }

    public func PropagateExpressionEffect(state: MaybeUninitDomain, expression: Expression): Unit {
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

    public func PropagateTerminatorEffect(state: MaybeUninitDomain, terminator: Terminator): Option<Block> {
        PropagateExpressionEffect(state, terminator)
        return None
    }

    public func GetDomainSize(): Int64 {
        return domainSize
    }

    public func GetAllocateIndex(location: Value): Option<Int64> {
        return allocateIdxMap.get(location.nodeId)
    }

    private func RunOnBody(body: BlockGroup, result: MaybeUninitResult): Unit {
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

    private func HandleAllocateExpr(state: MaybeUninitDomain, allocate: Expression): Unit {
        if (let Some(result) <- allocate.GetResult()) {
            if (let Some(index) <- allocateIdxMap.get(result.nodeId)) {
                state.Gen(index)
            }
        }
    }

    private func HandleStoreExpr(state: MaybeUninitDomain, store: Expression): Unit {
        if (store.GetNumOfOperands() >= 2) {
            let location = store.GetOperand(1)
            if (let Some(index) <- allocateIdxMap.get(location.nodeId)) {
                state.Kill(index)
                state.RecordMaybeInitedPos(index, Int64(store.GetDebugLocation().line))
            }
        }
    }

    private func HandleStoreElemRefExpr(state: MaybeUninitDomain, store: Expression): Unit {
        if (let Some(memberIndex) <- IsInitialisingMemberVar(functionValue, store, ctorInitInfo)) {
            if (memberIndex >= ctorInitInfo.superMemberNums) {
                let stateIndex = memberIndex - ctorInitInfo.superMemberNums
                state.Kill(stateIndex)
                state.RecordMaybeInitedPos(stateIndex, Int64(store.GetDebugLocation().line))
            }
        }
    }

    private func HandleApplyExpr(state: MaybeUninitDomain, apply: Expression): Unit {
        if (!functionValue.IsConstructor()) {
            return
        }
        if (IsSuperConstructorCall(apply)) {
            state.Kill(domainSize - 1)
            return
        }
        if (IsDelegatingConstructorCall(apply)) {
            state.SetAllLocalMemberInited()
            if (ctorInitInfo.superClassDef.isSome()) {
                state.Kill(domainSize - 1)
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

public func SaveAllocateMap(body: BlockGroup, allocateIdx: Int64, allocateIdxMap: HashMap<Int64, Int64>): Int64 {
    var nextIdx = allocateIdx
    for (block in body.GetBlocksRef()) {
        for (expr in block.GetExpressionsRef()) {
            let kind = expr.GetExprKind()
            if (kind == ExprKind.ALLOCATE || kind == ExprKind.ALLOCATE_WITH_EXCEPTION) {
                if (let Some(result) <- expr.GetResult()) {
                    if (!allocateIdxMap.contains(result.nodeId)) {
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

public func IsInitialisingMemberVar(functionValue: Function, store: Expression,
    ctorInitInfo: ConstructorInitInfo): Option<Int64> {
    if (!functionValue.IsConstructor() || store.GetNumOfOperands() == 0) {
        return None
    }
    if (store.GetNumOfOperands() > 1) {
        let maybeIndex = ResolveMemberIndexFromValue(store.GetOperand(1), ctorInitInfo)
        if (maybeIndex.isSome()) {
            return maybeIndex
        }
    }
    return ResolveMemberIndexFromValue(store.GetOperand(0), ctorInitInfo)
}

private func ResolveMemberIndexFromValue(value: Value, ctorInitInfo: ConstructorInitInfo): Option<Int64> {
    let srcName = value.GetSrcCodeIdentifier()
    let idName = value.GetIdentifierWithoutPrefix()
    var offset = ctorInitInfo.superMemberNums
    if (let Some(def) <- ctorInitInfo.thisCustomDef) {
        var idx: Int64 = 0
        for (member in def.GetInstanceVars()) {
            if ((!srcName.isEmpty() && member.name == srcName) || (!idName.isEmpty() && member.name == idName)) {
                return offset + idx
            }
            idx++
        }
    }
    if (let Some(superDef) <- ctorInitInfo.superClassDef) {
        var idx: Int64 = 0
        for (member in superDef.GetInstanceVars()) {
            if ((!srcName.isEmpty() && member.name == srcName) || (!idName.isEmpty() && member.name == idName)) {
                return idx
            }
            idx++
        }
    }
    return None
}

private func AddLineIfMissing(lines: ArrayList<Int64>, line: Int64): Unit {
    for (existing in lines) {
        if (existing == line) {
            return
        }
    }
    lines.add(line)
}
