package cangjie_compiler::chir

import std.collection.*
import cangjie_compiler::utils.STATIC_INIT_FUNC

private class VarInitConstructorContext {
    public let ctorInitInfo: ConstructorInitInfo
    public let members: ArrayList<MemberVarInfo>

    public init(ctorInitInfo: ConstructorInitInfo, members: ArrayList<MemberVarInfo>) {
        this.ctorInitInfo = ctorInitInfo
        this.members = members
    }
}

public class VarInitCheck {
    public init() {}

    public func RunOnPackage(pkg: Package): CHIRCheckResult {
        let checkResult = CHIRCheckResult()
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            if (ShouldCheckFunction(fn)) {
                RunOnFunc(fn, checkResult)
            }
        }
        return checkResult
    }

    public func RunOnFunc(fn: Function): CHIRCheckResult {
        let checkResult = CHIRCheckResult()
        RunOnFunc(fn, checkResult)
        return checkResult
    }

    public func RunOnFunc(fn: Function, checkResult: CHIRCheckResult): Unit {
        let ctorContext = BuildConstructorContext(fn)
        UseBeforeInitCheck(fn, ctorContext.ctorInitInfo, ctorContext.members, checkResult)
        ReassignInitedLetVarCheck(fn, ctorContext.ctorInitInfo, ctorContext.members, checkResult)
    }

    private func ShouldCheckFunction(fn: Function): Bool {
        let srcName = fn.GetSrcCodeIdentifier()
        if (srcName.contains("__ad_") || srcName == STATIC_INIT_FUNC) {
            return false
        }
        if (fn.GetIdentifier().contains("$Mocked")) {
            return false
        }
        return fn.GetFuncKind() != FuncKind.INSTANCEVAR_INIT
    }

    private func UseBeforeInitCheck(
        fn: Function,
        ctorInitInfo: ConstructorInitInfo,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        if (fn.GetBody().isNone()) {
            return
        }
        let analysis = MaybeUninitAnalysis(fn, ctorInitInfo)
        let analysisResult = analysis.Run()
        if (let Some(body) <- fn.GetBody()) {
            VisitMaybeUninitBody(fn, body, analysis, analysisResult, members, checkResult)
        }
    }

    private func ReassignInitedLetVarCheck(
        fn: Function,
        ctorInitInfo: ConstructorInitInfo,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        if (fn.GetBody().isNone()) {
            return
        }
        let analysis = MaybeInitAnalysis(fn, ctorInitInfo)
        let analysisResult = analysis.Run()
        if (let Some(body) <- fn.GetBody()) {
            VisitMaybeInitBody(fn, body, analysis, analysisResult, members, checkResult)
        }
    }

    private func VisitMaybeUninitBody(
        fn: Function,
        body: BlockGroup,
        analysis: MaybeUninitAnalysis,
        analysisResult: MaybeUninitResult,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        for (block in body.GetBlocksRef()) {
            if (let Some(entryState) <- analysisResult.GetEntryState(block)) {
                let state = entryState
                for (expr in block.GetExpressionsRef()) {
                    if (let Some(term) <- expr.AsTerminator()) {
                        CheckMaybeUninitTerminator(fn, body, block, term, state, members, checkResult)
                        analysis.PropagateTerminatorEffect(state, term)
                    } else {
                        CheckMaybeUninitExpression(fn, expr, state, members, checkResult)
                        analysis.PropagateExpressionEffect(state, expr)
                    }
                }
            }
        }
        VisitNestedMaybeUninitBodies(fn, body, analysis, analysisResult, members, checkResult)
    }

    private func VisitNestedMaybeUninitBodies(
        fn: Function,
        body: BlockGroup,
        analysis: MaybeUninitAnalysis,
        analysisResult: MaybeUninitResult,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        for (block in body.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        VisitMaybeUninitBody(fn, lambdaBody, analysis, analysisResult, members, checkResult)
                    }
                }
            }
        }
    }

    private func VisitMaybeInitBody(
        fn: Function,
        body: BlockGroup,
        analysis: MaybeInitAnalysis,
        analysisResult: MaybeInitResult,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        for (block in body.GetBlocksRef()) {
            if (let Some(entryState) <- analysisResult.GetEntryState(block)) {
                let state = entryState
                for (expr in block.GetExpressionsRef()) {
                    if (let Some(term) <- expr.AsTerminator()) {
                        CheckMaybeInitExpression(fn, term, state, members, checkResult)
                        analysis.PropagateTerminatorEffect(state, term)
                    } else {
                        CheckMaybeInitExpression(fn, expr, state, members, checkResult)
                        analysis.PropagateExpressionEffect(state, expr)
                    }
                }
            }
        }
        VisitNestedMaybeInitBodies(fn, body, analysis, analysisResult, members, checkResult)
    }

    private func VisitNestedMaybeInitBodies(
        fn: Function,
        body: BlockGroup,
        analysis: MaybeInitAnalysis,
        analysisResult: MaybeInitResult,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        for (block in body.GetBlocksRef()) {
            for (expr in block.GetExpressionsRef()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        VisitMaybeInitBody(fn, lambdaBody, analysis, analysisResult, members, checkResult)
                    }
                }
            }
        }
    }

    private func CheckMaybeUninitExpression(
        fn: Function,
        expr: Expression,
        state: MaybeUninitDomain,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        let kind = expr.GetExprKind()
        if (kind == ExprKind.LOAD) {
            if (CheckLoadToUninitedAllocation(state, expr, checkResult)) {
                return
            }
        }
        if (kind == ExprKind.GET_ELEMENT_REF || kind == ExprKind.GET_ELEMENT_BY_NAME) {
            if (CheckGetElementRefToUninitedAllocation(state, expr, checkResult)) {
                return
            }
        }
        if (!fn.IsConstructor()) {
            return
        }
        if (kind == ExprKind.LOAD) {
            CheckLoadToUninitedCustomDefMember(state, fn, expr, members, checkResult)
        } else if (kind == ExprKind.STORE_ELEMENT_REF || kind == ExprKind.STORE_ELEMENT_BY_NAME) {
            CheckStoreToUninitedCustomDefMember(state, fn, expr, members, checkResult)
        } else if (kind == ExprKind.APPLY || kind == ExprKind.APPLY_WITH_EXCEPTION) {
            CheckMemberFuncCall(state, fn, expr, checkResult)
        }
    }

    private func CheckMaybeUninitTerminator(
        fn: Function,
        body: BlockGroup,
        block: Block,
        term: Terminator,
        state: MaybeUninitDomain,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        if (fn.IsConstructor() && term.GetExprKind() == ExprKind.EXIT) {
            if (!IsBlockInBody(block, body)) {
                return
            }
            if (HasFuncCallWithNothingRetVal(block)) {
                return
            }
            let uninitedMembers = state.GetMaybeUninitedLocalMembers()
            if (!uninitedMembers.isEmpty()) {
                RaiseUninitedDefMemberError(state, fn, members, uninitedMembers, checkResult)
            }
            return
        }
        if (fn.IsConstructor() && term.GetExprKind() == ExprKind.APPLY_WITH_EXCEPTION) {
            CheckMemberFuncCall(state, fn, term, checkResult)
        }
    }

    private func CheckMaybeInitExpression(
        fn: Function,
        expr: Expression,
        state: MaybeInitDomain,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        let kind = expr.GetExprKind()
        if (kind == ExprKind.STORE) {
            if (let Some(targetVal) <- ResolveStoreLocation(expr)) {
                if (targetVal.IsLocalVar() && targetVal.TestAttr(Attribute.READONLY)) {
                    if (let Some(isInited) <- state.IsMaybeInitedAllocation(targetVal)) {
                        if (isInited) {
                            AddCannotAssignInitializedLetError(expr, fn, checkResult)
                        }
                    }
                }
            }
        } else if (kind == ExprKind.STORE_ELEMENT_REF || kind == ExprKind.STORE_ELEMENT_BY_NAME) {
            CheckStoreToInitedCustomDefMember(state, fn, expr, members, checkResult)
        }
    }

    private func CheckLoadToUninitedAllocation(
        state: MaybeUninitDomain,
        load: Expression,
        checkResult: CHIRCheckResult
    ): Bool {
        if (load.GetNumOfOperands() == 0) {
            return false
        }
        let targetVal = load.GetOperand(0)
        if (let Some(isUninited) <- state.IsMaybeUninitedAllocation(targetVal)) {
            if (isUninited) {
                AddUseBeforeInitError(load, ValueDisplayName(targetVal), state.GetMaybeInitedPos(targetVal),
                    checkResult)
                return true
            }
        }
        return false
    }

    private func CheckGetElementRefToUninitedAllocation(
        state: MaybeUninitDomain,
        getElementRef: Expression,
        checkResult: CHIRCheckResult
    ): Bool {
        if (getElementRef.GetNumOfOperands() == 0) {
            return false
        }
        let targetVal = getElementRef.GetOperand(0)
        if (let Some(targetTy) <- targetVal.GetType()) {
            let originalTy = targetTy.StripAllRefs()
            if (!originalTy.IsStruct() && !originalTy.IsEnum()) {
                return false
            }
        }
        if (let Some(isUninited) <- state.IsMaybeUninitedAllocation(targetVal)) {
            if (isUninited) {
                AddUseBeforeInitError(getElementRef, ValueDisplayName(targetVal), state.GetMaybeInitedPos(targetVal),
                    checkResult)
                return true
            }
        }
        return false
    }

    private func CheckLoadToUninitedCustomDefMember(
        state: MaybeUninitDomain,
        fn: Function,
        load: Expression,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        if (fn.GetNumOfParams() == 0 || load.GetNumOfOperands() == 0) {
            return
        }
        let targetVal = load.GetOperand(0)
        if (let Some(localVal) <- targetVal.AsLocalVar()) {
            if (let Some(targetExpr) <- localVal.GetExpr()) {
                let thisArg = fn.GetParam(0)
                if (let Some(index) <- ResolveGetElementRefViaDefMember(targetExpr, thisArg, members)) {
                    CheckUninitedDefMember(state, load, members, index, false, checkResult)
                }
            }
        }
    }

    private func CheckStoreToUninitedCustomDefMember(
        state: MaybeUninitDomain,
        fn: Function,
        store: Expression,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        if (fn.GetNumOfParams() == 0) {
            return
        }
        let thisArg = fn.GetParam(0)
        let ctorInfo = BuildConstructorContext(fn).ctorInitInfo
        if (IsNestedStoreViaDefMember(store, thisArg)) {
            if (let Some(index) <- ResolveStoreMemberIndex(fn, store, ctorInfo, members)) {
                CheckUninitedDefMember(state, store, members, index, false, checkResult)
            }
        }
        if (!IsClassMethod(fn)) {
            return
        }
        if (StoreTouchesThis(store, thisArg)) {
            if (let Some(index) <- ResolveStoreMemberIndex(fn, store, ctorInfo, members)) {
                CheckUninitedDefMember(state, store, members, index, true, checkResult)
            }
        }
    }

    private func CheckMemberFuncCall(
        state: MaybeUninitDomain,
        initFunc: Function,
        apply: Expression,
        checkResult: CHIRCheckResult
    ): Unit {
        if (apply.GetNumOfOperands() == 0 || initFunc.GetNumOfParams() == 0) {
            return
        }
        if (state.GetMaybeUninitedLocalMembers().isEmpty()) {
            return
        }
        if (let Some(calleeFunc) <- apply.GetOperand(0).AsFunction()) {
            if (!calleeFunc.IsFuncWithBody() || calleeFunc.IsConstructor() ||
                calleeFunc.TestAttr(Attribute.STATIC) || calleeFunc.IsInstanceVarInit()) {
                return
            }
            if (!SameParentDef(calleeFunc, initFunc)) {
                return
            }
            if (apply.GetNumOfOperands() <= 1) {
                return
            }
            let thisArg = initFunc.GetParam(0)
            let receiver = apply.GetOperand(1)
            if (receiver.nodeId == thisArg.nodeId || IsLoadedFromThis(receiver, thisArg)) {
                RaiseIllegalMemberFunCallError(apply, calleeFunc, checkResult)
            }
        }
    }

    private func RaiseUninitedDefMemberError(
        state: MaybeUninitDomain,
        fn: Function,
        members: ArrayList<MemberVarInfo>,
        uninitedMemberIdx: ArrayList<Int64>,
        checkResult: CHIRCheckResult
    ): Unit {
        for (index in uninitedMemberIdx) {
            if (index >= 0 && index < members.size) {
                let memberName = members[index].name
                var message = "in function ${fn.GetIdentifier()}, constructor exits before member `${memberName}` " +
                    "is initialized"
                let lines = state.GetMaybeInitedPos(index)
                if (!lines.isEmpty()) {
                    message += "; " + MaybeInitedPosNote(memberName, lines)
                }
                checkResult.AddError(message)
            }
        }
    }

    private func CheckUninitedDefMember(
        state: MaybeUninitDomain,
        expr: Expression,
        members: ArrayList<MemberVarInfo>,
        index: Int64,
        onlyCheckSuper: Bool,
        checkResult: CHIRCheckResult
    ): Unit {
        if (index < 0 || index >= members.size) {
            return
        }
        match (state.IsMaybeUninitedMember(index)) {
            case MaybeUninitMemberKind.SUPER_MEMBER =>
                checkResult.AddError("illegal usage of super member `${members[index].name}` at " +
                    VarInitExprLocation(expr))
            case MaybeUninitMemberKind.LOCAL_MEMBER =>
                if (!onlyCheckSuper) {
                    AddUseBeforeInitError(expr, members[index].name, state.GetMaybeInitedPos(index), checkResult)
                }
            case MaybeUninitMemberKind.NA => return
        }
    }

    private func CheckStoreToInitedCustomDefMember(
        state: MaybeInitDomain,
        fn: Function,
        store: Expression,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        if (!fn.IsConstructor() || fn.GetNumOfParams() == 0) {
            return
        }
        let ctorInfo = BuildConstructorContext(fn).ctorInitInfo
        if (let Some(index) <- ResolveStoreMemberIndex(fn, store, ctorInfo, members)) {
            if (index >= 0 && index < members.size && members[index].isReadOnly) {
                match (state.IsMaybeInitedMember(index)) {
                    case MaybeInitMemberKind.SUPER_MEMBER => AddCannotAssignInitializedLetError(store, fn, checkResult)
                    case MaybeInitMemberKind.LOCAL_MEMBER => AddCannotAssignInitializedLetError(store, fn, checkResult)
                    case MaybeInitMemberKind.NA => return
                }
            }
        }
    }

    private func RaiseIllegalMemberFunCallError(
        apply: Expression,
        memberFunc: Function,
        checkResult: CHIRCheckResult
    ): Unit {
        var identifier = memberFunc.GetSrcCodeIdentifier()
        if (identifier.isEmpty()) {
            identifier = memberFunc.GetIdentifierWithoutPrefix()
        }
        let calleeKind = memberFunc.GetFuncKind()
        if ((calleeKind == FuncKind.GETTER || calleeKind == FuncKind.SETTER) && identifier.size > 4) {
            identifier = identifier[1..identifier.size - 4]
        }
        checkResult.AddError("illegal member call `${identifier}` before all members are initialized at " +
            VarInitExprLocation(apply))
    }
}

private func BuildConstructorContext(fn: Function): VarInitConstructorContext {
    let ctorInfo = ConstructorInitInfo()
    let members = ArrayList<MemberVarInfo>()
    if (!fn.IsConstructor()) {
        return VarInitConstructorContext(ctorInfo, members)
    }
    if (let Some(customDef) <- fn.GetParentCustomTypeDef()) {
        ctorInfo.thisCustomDef = customDef
        if (let Some(classDef) <- (customDef as ClassDef)) {
            if (let Some(superDef) <- classDef.GetSuperClassDef()) {
                ctorInfo.superClassDef = superDef
                CollectSuperMembers(superDef, members)
                ctorInfo.superMemberNums = members.size
            }
            let localMembers = classDef.GetInstanceVars()
            for (member in localMembers) {
                members.add(member)
            }
            ctorInfo.localMemberNums = localMembers.size
        } else {
            let localMembers = customDef.GetInstanceVars()
            for (member in localMembers) {
                members.add(member)
            }
            ctorInfo.localMemberNums = localMembers.size
        }
    }
    return VarInitConstructorContext(ctorInfo, members)
}

private func CollectSuperMembers(classDef: ClassDef, members: ArrayList<MemberVarInfo>): Unit {
    if (let Some(superDef) <- classDef.GetSuperClassDef()) {
        CollectSuperMembers(superDef, members)
    }
    for (member in classDef.GetInstanceVars()) {
        members.add(member)
    }
}

private func HasFuncCallWithNothingRetVal(block: Block): Bool {
    for (expr in block.GetNonTerminatorExpressions()) {
        if (!expr.IsFuncCall()) {
            continue
        }
        if (let Some(resultTy) <- expr.GetResultType()) {
            if (resultTy.StripAllRefs().IsNothing()) {
                return true
            }
        }
    }
    return false
}

private func ResolveStoreLocation(store: Expression): Option<Value> {
    if (store.GetNumOfOperands() >= 2) {
        return store.GetOperand(1)
    }
    return None
}

private func ResolveStoreMemberIndex(
    fn: Function,
    store: Expression,
    ctorInfo: ConstructorInitInfo,
    members: ArrayList<MemberVarInfo>
): Option<Int64> {
    if (let Some(index) <- IsInitialisingMemberVar(fn, store, ctorInfo)) {
        return index
    }
    return ResolveMemberIndexFromOperands(store, members, 2)
}

private func ResolveGetElementRefViaDefMember(
    expr: Expression,
    thisArg: Parameter,
    members: ArrayList<MemberVarInfo>
): Option<Int64> {
    let kind = expr.GetExprKind()
    if (kind != ExprKind.GET_ELEMENT_REF && kind != ExprKind.GET_ELEMENT_BY_NAME) {
        return None
    }
    if (expr.GetNumOfOperands() == 0) {
        return None
    }
    let location = expr.GetOperand(0)
    if (location.nodeId == thisArg.nodeId) {
        return ResolveMemberIndexFromOperands(expr, members, 1)
    }
    if (let Some(localVal) <- location.AsLocalVar()) {
        if (let Some(locationExpr) <- localVal.GetExpr()) {
            return ResolveGetElementRefViaDefMember(locationExpr, thisArg, members)
        }
    }
    return None
}

private func ResolveMemberIndexFromOperands(
    expr: Expression,
    members: ArrayList<MemberVarInfo>,
    startIndex: Int64
): Option<Int64> {
    var idx = startIndex
    while (idx < expr.GetNumOfOperands()) {
        if (let Some(memberIndex) <- ResolveMemberIndexFromValue(expr.GetOperand(idx), members)) {
            return memberIndex
        }
        idx++
    }
    return None
}

private func ResolveMemberIndexFromValue(value: Value, members: ArrayList<MemberVarInfo>): Option<Int64> {
    let srcName = value.GetSrcCodeIdentifier()
    let identifier = value.GetIdentifierWithoutPrefix()
    var idx: Int64 = 0
    for (member in members) {
        if ((!srcName.isEmpty() && srcName == member.name) || (!identifier.isEmpty() && identifier == member.name)) {
            return idx
        }
        idx++
    }
    if (let Some(intLiteral) <- ExtractIntLiteral(value)) {
        if (intLiteral >= 0 && intLiteral < members.size) {
            return intLiteral
        }
    }
    return None
}

private func ExtractIntLiteral(value: Value): Option<Int64> {
    if (let Some(localVal) <- value.AsLocalVar()) {
        if (let Some(expr) <- localVal.GetExpr()) {
            if (let Some(constant) <- (expr as Constant)) {
                if (let Some(intLiteral) <- (constant.literal as IntLiteral)) {
                    return intLiteral.value
                }
            }
        }
    }
    return None
}

private func IsNestedStoreViaDefMember(store: Expression, thisArg: Parameter): Bool {
    if (!StoreTouchesThis(store, thisArg)) {
        return false
    }
    if (store.GetNumOfOperands() > 3) {
        return true
    }
    var idx: Int64 = 0
    while (idx < store.GetNumOfOperands()) {
        if (IsGetElementRefDerivedFromThis(store.GetOperand(idx), thisArg)) {
            return true
        }
        idx++
    }
    return false
}

private func StoreTouchesThis(store: Expression, thisArg: Parameter): Bool {
    var idx: Int64 = 0
    while (idx < store.GetNumOfOperands()) {
        let operand = store.GetOperand(idx)
        if (operand.nodeId == thisArg.nodeId || IsGetElementRefDerivedFromThis(operand, thisArg)) {
            return true
        }
        idx++
    }
    return false
}

private func IsGetElementRefDerivedFromThis(value: Value, thisArg: Parameter): Bool {
    if (let Some(localVal) <- value.AsLocalVar()) {
        if (let Some(expr) <- localVal.GetExpr()) {
            return IsGetElementRefExpressionDerivedFromThis(expr, thisArg)
        }
    }
    return false
}

private func IsGetElementRefExpressionDerivedFromThis(expr: Expression, thisArg: Parameter): Bool {
    let kind = expr.GetExprKind()
    if (kind != ExprKind.GET_ELEMENT_REF && kind != ExprKind.GET_ELEMENT_BY_NAME) {
        return false
    }
    if (expr.GetNumOfOperands() == 0) {
        return false
    }
    let location = expr.GetOperand(0)
    if (location.nodeId == thisArg.nodeId) {
        return true
    }
    return IsGetElementRefDerivedFromThis(location, thisArg)
}

private func IsLoadedFromThis(value: Value, thisArg: Parameter): Bool {
    if (let Some(localVal) <- value.AsLocalVar()) {
        if (let Some(expr) <- localVal.GetExpr()) {
            if (expr.GetExprKind() == ExprKind.LOAD && expr.GetNumOfOperands() > 0) {
                return expr.GetOperand(0).nodeId == thisArg.nodeId
            }
        }
    }
    return false
}

private func SameParentDef(left: Function, right: Function): Bool {
    if (let Some(leftParent) <- left.GetParentCustomTypeDef()) {
        if (let Some(rightParent) <- right.GetParentCustomTypeDef()) {
            return leftParent.nodeId == rightParent.nodeId
        }
    }
    return false
}

private func IsClassMethod(fn: Function): Bool {
    if (let Some(def) <- fn.GetParentCustomTypeDef()) {
        return (def as ClassDef).isSome()
    }
    return false
}

private func IsBlockInBody(block: Block, body: BlockGroup): Bool {
    if (let Some(parent) <- block.GetParentBlockGroup()) {
        return parent.nodeId == body.nodeId
    }
    return false
}

private func AddUseBeforeInitError(
    expr: Expression,
    identifier: String,
    maybeInitedPos: ArrayList<Int64>,
    checkResult: CHIRCheckResult
): Unit {
    var message = "value `${identifier}` used before initialization at " + VarInitExprLocation(expr)
    if (!maybeInitedPos.isEmpty()) {
        message += "; " + MaybeInitedPosNote(identifier, maybeInitedPos)
    }
    checkResult.AddError(message)
}

private func AddCannotAssignInitializedLetError(
    expr: Expression,
    fn: Function,
    checkResult: CHIRCheckResult
): Unit {
    checkResult.AddError("in function ${fn.GetIdentifier()}, cannot assign initialized let variable at " +
        VarInitExprLocation(expr))
}

private func MaybeInitedPosNote(identifier: String, maybeInitedPos: ArrayList<Int64>): String {
    let lines = ArrayList<String>()
    for (line in maybeInitedPos) {
        lines.add("${line}")
    }
    return "variable `${identifier}` is assigned in line " + JoinStrings(lines, ", ") +
        ", but these assignments might not execute at runtime"
}

private func ValueDisplayName(value: Value): String {
    let srcName = value.GetSrcCodeIdentifier()
    if (!srcName.isEmpty()) {
        return srcName
    }
    return value.GetIdentifierWithoutPrefix()
}

private func VarInitExprLocation(expr: Expression): String {
    let loc = expr.GetDebugLocation().ToString()
    if (loc.isEmpty()) {
        return "<unknown>"
    }
    return loc
}
