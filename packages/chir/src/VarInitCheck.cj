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
        if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return
        }
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
        if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return
        }
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
        if (kind == ExprKind.GET_ELEMENT_REF) {
            if (CheckGetElementRefToUninitedAllocation(state, expr, checkResult)) {
                return
            }
        }
        if (!fn.IsConstructor()) {
            return
        }
        if (kind == ExprKind.LOAD) {
            CheckLoadToUninitedCustomDefMember(state, fn, expr, members, checkResult)
        } else if (kind == ExprKind.STORE_ELEMENT_REF) {
            let storeRef = (expr as StoreElementRef).getOrThrow()
            CheckStoreToUninitedCustomDefMember(state, fn, storeRef, members, checkResult)
        } else if (kind == ExprKind.APPLY) {
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
            if (let Some(parentGroup) <- block.GetParentBlockGroup()) {
                if (parentGroup.nodeId != body.nodeId) {
                    return
                }
            } else {
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
            let store = (expr as Store).getOrThrow()
            let targetVal = store.GetLocation()
            if (targetVal.IsLocalVar() && targetVal.TestAttr(Attribute.READONLY)) {
                if (let Some(isInited) <- state.IsMaybeInitedAllocation(targetVal)) {
                    if (isInited) {
                        AddCannotAssignInitializedLetError(expr, fn, checkResult)
                    }
                }
            }
        } else if (kind == ExprKind.STORE_ELEMENT_REF) {
            let storeRef = (expr as StoreElementRef).getOrThrow()
            CheckStoreToInitedCustomDefMember(state, fn, storeRef, members, checkResult)
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
                if (let Some(index) <- IsGetElemRefViaDefMember(targetExpr, thisArg)) {
                    CheckUninitedDefMember(state, load, members, index, false, checkResult)
                }
            }
        }
    }

    private func CheckStoreToUninitedCustomDefMember(
        state: MaybeUninitDomain,
        fn: Function,
        store: StoreElementRef,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        if (fn.GetNumOfParams() == 0) {
            return
        }
        let thisArg = fn.GetParam(0)
        if (let Some(index) <- IsStoreViaDefMember(store, thisArg, shouldBeNested: true)) {
            CheckUninitedDefMember(state, store, members, index, false, checkResult)
            return
        }
        if (!fn.IsClassMethod()) {
            return
        }
        if (let Some(index) <- IsStoreViaDefMember(store, thisArg)) {
            CheckUninitedDefMember(state, store, members, index, true, checkResult)
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
            let calleeOuterDef = calleeFunc.GetOuterDeclaredOrExtendedDef()
            let initOuterDef = initFunc.GetOuterDeclaredOrExtendedDef()
            let sameOuterDef = match ((calleeOuterDef, initOuterDef)) {
                case (Some(left), Some(right)) => left.nodeId == right.nodeId
                case (None, None) => true
                case _ => false
            }
            if (!sameOuterDef) {
                return
            }
            if (apply.GetNumOfOperands() <= 1) {
                return
            }
            let thisArg = initFunc.GetParam(0)
            let receiver = apply.GetOperand(1)
            if (receiver.nodeId == thisArg.nodeId) {
                RaiseIllegalMemberFunCallError(apply, calleeFunc, checkResult)
            } else if (let Some(localVal) <- receiver.AsLocalVar()) {
                if (let Some(argExpr) <- localVal.GetExpr()) {
                    if (argExpr.GetExprKind() == ExprKind.LOAD && argExpr.GetNumOfOperands() > 0 &&
                        argExpr.GetOperand(0).nodeId == thisArg.nodeId) {
                        RaiseIllegalMemberFunCallError(apply, calleeFunc, checkResult)
                    }
                }
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
        var allCommonNotDeserialized = true
        for (index in uninitedMemberIdx) {
            let member = members[index]
            if (!(member.TestAttr(Attribute.COMMON) && !member.TestAttr(Attribute.DESERIALIZED))) {
                allCommonNotDeserialized = false
                break
            }
        }
        if (allCommonNotDeserialized) {
            return
        }
        for (index in uninitedMemberIdx) {
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
        store: StoreElementRef,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        if (!fn.IsConstructor()) {
            return
        }
        let paths = store.GetPath()
        if (store.GetLocation().nodeId == fn.GetParam(0).nodeId && paths.size == 1) {
            let index = Int64(paths[0])
            if (members[index].TestAttr(Attribute.READONLY)) {
                match (state.IsMaybeInitedMember(index)) {
                    case MaybeInitMemberKind.SUPER_MEMBER => AddCannotAssignInitializedLetError(store, fn, checkResult)
                    case MaybeInitMemberKind.LOCAL_MEMBER => AddCannotAssignInitializedLetError(store, fn, checkResult)
                    case MaybeInitMemberKind.NA => return
                }
            }
            return
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
            }
            let allMembers = classDef.GetAllInstanceVars()
            for (member in allMembers) {
                members.add(member)
            }
            ctorInfo.localMemberNums = classDef.GetDirectInstanceVarNum()
            ctorInfo.superMemberNums = allMembers.size - ctorInfo.localMemberNums
        } else {
            let localMembers = customDef.GetAllInstanceVars()
            for (member in localMembers) {
                members.add(member)
            }
            ctorInfo.localMemberNums = localMembers.size
        }
    }
    return VarInitConstructorContext(ctorInfo, members)
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

private func IsGetElemRefViaDefMember(
    expr: Expression,
    thisArg: Parameter
): Option<Int64> {
    if (expr.GetExprKind() != ExprKind.GET_ELEMENT_REF) {
        return None
    }
    let getElemRef = (expr as GetElementRef).getOrThrow()
    let location = getElemRef.GetLocation()
    if (location.nodeId == thisArg.nodeId) {
        return Int64(getElemRef.GetPath()[0])
    }
    if (let Some(localVal) <- location.AsLocalVar()) {
        if (let Some(locationExpr) <- localVal.GetExpr()) {
            return IsGetElemRefViaDefMember(locationExpr, thisArg)
        }
    }
    return None
}

private func IsStoreViaDefMember(
    store: StoreElementRef,
    thisArg: Parameter,
    shouldBeNested!: Bool = false
): Option<Int64> {
    let location = store.GetLocation()
    if (location.nodeId == thisArg.nodeId && (!shouldBeNested || store.GetPath().size > 1)) {
        return Int64(store.GetPath()[0])
    } else if (let Some(localVal) <- location.AsLocalVar()) {
        if (let Some(expr) <- localVal.GetExpr()) {
            return IsGetElemRefViaDefMember(expr, thisArg)
        }
    }
    return None
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
