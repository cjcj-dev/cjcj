package cjcj::chir

import std.collection.*
import cjcj::basic.{DiagnosticBuilder, DiagnosticEngine, DiagKindRefactor}
import cjcj::utils.{STATIC_INIT_FUNC, TaskQueue, TaskResult}

private class VarInitConstructorContext {
    public let ctorInitInfo: ConstructorInitInfo
    public let members: ArrayList<MemberVarInfo>

    public init(ctorInitInfo: ConstructorInitInfo, members: ArrayList<MemberVarInfo>) {
        this.ctorInitInfo = ctorInitInfo
        this.members = members
    }
}

public class VarInitCheck {
    private let diag: DiagnosticEngine

    public init(diag: DiagnosticEngine) {
        this.diag = diag
    }

    public func RunOnPackage(pkg: Package, threadNum!: Int64 = 1): CHIRCheckResult {
        let checkResult = CHIRCheckResult()
        let funcs = ArrayList<Function>()
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            if (ShouldCheckFunction(fn)) {
                funcs.add(fn)
            }
        }
        if (funcs.isEmpty()) {
            return checkResult
        }
        if (threadNum == 1) {
            for (fn in funcs) {
                RunOnFunc(fn, checkResult)
            }
            return checkResult
        }
        let taskQueue = TaskQueue(threadNum)
        let taskResults = ArrayList<TaskResult<CHIRCheckResult>>()
        for (fn in funcs) {
            taskResults.add(taskQueue.AddTask<CHIRCheckResult>({ =>
                RunOnFunc(fn)
            }))
        }
        taskQueue.RunAndWaitForAllTasksCompleted()
        for (taskResult in taskResults) {
            let fnResult = taskResult.get()
            var idx: Int64 = 0
            while (idx < fnResult.errors.size) {
                checkResult.AddError(fnResult.errors[idx])
                if (idx < fnResult.notes.size) {
                    for (note in fnResult.notes[idx]) {
                        checkResult.AddNote(note)
                    }
                }
                idx++
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
        return fn.GetFuncKind() != FuncKind.INSTANCEVAR_INIT && fn.GetSkipCheck() != SkipKind.SKIP_VIC
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
        let engine = Engine<MaybeUninitDomain>(fn, analysis)
        let result = engine.IterateToFixpoint() ??
            throw IllegalStateException("VarInitCheck UseBeforeInitCheck expected analysis result")
        let callStack = ArrayList<Function>()
        callStack.add(fn)
        let actionBeforeVisitExpr = { state: MaybeUninitDomain, expr: Expression, idx: Int64 =>
            let _ = idx
            if (expr.GetExprKind() == ExprKind.APPLY) {
                if (let Some(varInitFunc) <- TryGetInstanceVarInitFromApply(expr)) {
                    callStack.add(varInitFunc)
                }
            }
            let initialFunc = callStack[0]
            let curFunc = callStack[callStack.size - 1]
            if (expr.GetExprKind() == ExprKind.LOAD) {
                if (CheckLoadToUninitedAllocation(state, (expr as Load).getOrThrow(), checkResult)) {
                    return
                }
            }
            if (expr.GetExprKind() == ExprKind.GET_ELEMENT_REF) {
                if (CheckGetElementRefToUninitedAllocation(state, (expr as GetElementRef).getOrThrow(), checkResult)) {
                    return
                }
            }
            if (!initialFunc.IsConstructor()) {
                return
            }
            if (expr.GetExprKind() == ExprKind.LOAD) {
                CheckLoadToUninitedCustomDefMember(state, curFunc, (expr as Load).getOrThrow(), members, checkResult)
            } else if (expr.GetExprKind() == ExprKind.STORE_ELEMENT_REF) {
                CheckStoreToUninitedCustomDefMember(
                    state, curFunc, (expr as StoreElementRef).getOrThrow(), members, checkResult)
            } else if (expr.GetExprKind() == ExprKind.APPLY) {
                CheckMemberFuncCall(state, curFunc, expr, checkResult)
            }
        }
        let actionAfterVisitExpr = { state: MaybeUninitDomain, expr: Expression, idx: Int64 =>
            let _ = state
            let _ = idx
            if (expr.GetExprKind() == ExprKind.APPLY) {
                if (TryGetInstanceVarInitFromApply(expr).isSome()) {
                    callStack.remove(at: callStack.size - 1)
                }
            }
        }
        let actionOnTerminator = { state: MaybeUninitDomain, term: Terminator, targetSucc: Option<Block> =>
            let _ = targetSucc
            CheckMaybeUninitTerminator(fn, term, state, members, checkResult)
        }
        result.VisitWith(actionBeforeVisitExpr, actionAfterVisitExpr, actionOnTerminator)
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
        let engine = Engine<MaybeInitDomain>(fn, analysis)
        let result = engine.IterateToFixpoint() ??
            throw IllegalStateException("VarInitCheck ReassignInitedLetVarCheck expected analysis result")
        let actionBeforeVisitExpr = { state: MaybeInitDomain, expr: Expression, idx: Int64 =>
            let _ = idx
            CheckMaybeInitExpression(fn, expr, state, members, checkResult)
        }
        let actionAfterVisitExpr = { state: MaybeInitDomain, expr: Expression, idx: Int64 =>
            let _ = state
            let _ = expr
            let _ = idx
        }
        let actionOnTerminator = { state: MaybeInitDomain, term: Terminator, targetSucc: Option<Block> =>
            let _ = state
            let _ = term
            let _ = targetSucc
        }
        result.VisitWith(actionBeforeVisitExpr, actionAfterVisitExpr, actionOnTerminator)
    }

    private func CheckMaybeUninitTerminator(
        fn: Function,
        term: Terminator,
        state: MaybeUninitDomain,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        if (fn.IsConstructor() && term.GetExprKind() == ExprKind.EXIT) {
            let parentBlock = term.GetParentBlock() ??
                throw IllegalStateException("VarInitCheck terminator expected parent block")
            let isForInGeneratedExit = term.GetSkipCheck() == SkipKind.SKIP_FORIN_EXIT
            let parentGroup = parentBlock.GetParentBlockGroup() ??
                throw IllegalStateException("VarInitCheck terminator parent block expected parent group")
            let body = fn.GetBody() ?? throw IllegalStateException("VarInitCheck expected function body")
            let isExitForLocalFunc = !refEq(parentGroup, body)
            if (isForInGeneratedExit || isExitForLocalFunc || HasFuncCallWithNothingRetVal(parentBlock)) {
                return
            }
            let uninitedMembers = state.GetMaybeUninitedLocalMembers()
            if (!uninitedMembers.isEmpty()) {
                RaiseUninitedDefMemberError(state, fn, members, uninitedMembers)
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
                        diag.DiagnoseRefactor(DiagKindRefactor.chir_cannot_assign_initialized_let_variable,
                            ToPosition(expr.GetDebugLocation())).Emit()
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
        load: Load,
        checkResult: CHIRCheckResult
    ): Bool {
        let targetVal = load.GetLocation()
        if (let Some(isUninited) <- state.IsMaybeUninitedAllocation(targetVal)) {
            if (isUninited) {
                AddUseBeforeInitError(load, targetVal.GetSrcCodeIdentifier(), state.GetMaybeInitedPos(targetVal),
                    checkResult)
                return true
            }
        }
        return false
    }

    private func CheckGetElementRefToUninitedAllocation(
        state: MaybeUninitDomain,
        getElementRef: GetElementRef,
        checkResult: CHIRCheckResult
    ): Bool {
        let targetVal = getElementRef.GetLocation()
        let originalTy = targetVal.GetType().getOrThrow().StripAllRefs()
        if (!originalTy.IsStruct() && !originalTy.IsEnum()) {
            return false
        }
        if (let Some(isUninited) <- state.IsMaybeUninitedAllocation(targetVal)) {
            if (isUninited) {
                AddUseBeforeInitError(getElementRef, targetVal.GetSrcCodeIdentifier(), state.GetMaybeInitedPos(targetVal),
                    checkResult)
                return true
            }
        }
        return false
    }

    private func CheckLoadToUninitedCustomDefMember(
        state: MaybeUninitDomain,
        fn: Function,
        load: Load,
        members: ArrayList<MemberVarInfo>,
        checkResult: CHIRCheckResult
    ): Unit {
        let targetVal = load.GetLocation()
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
        let callee = if (apply.GetExprKind() == ExprKind.APPLY) {
            (apply as Apply).getOrThrow().GetCallee()
        } else {
            (apply as ApplyWithException).getOrThrow().GetCallee()
        }
        if (!callee.IsFuncWithBody()) {
            return
        }
        let calleeFunc = callee.AsFunction().getOrThrow()
        let calleeOuterDef = calleeFunc.GetOuterDeclaredOrExtendedDef()
        let initOuterDef = initFunc.GetOuterDeclaredOrExtendedDef()
        let sameOuterDef = match ((calleeOuterDef, initOuterDef)) {
            case (Some(left), Some(right)) => refEq(left, right)
            case (None, None) => true
            case _ => false
        }
        if (sameOuterDef && !calleeFunc.IsConstructor() && !calleeFunc.TestAttr(Attribute.STATIC) &&
            !state.GetMaybeUninitedLocalMembers().isEmpty() && !calleeFunc.IsInstanceVarInit()) {
            let args = if (apply.GetExprKind() == ExprKind.APPLY) {
                (apply as Apply).getOrThrow().GetArgs()
            } else {
                (apply as ApplyWithException).getOrThrow().GetArgs()
            }
            let thisArg = initFunc.GetParam(0)
            let receiver = args[0]
            if (refEq(receiver, thisArg)) {
                RaiseIllegalMemberFunCallError(apply, calleeFunc, checkResult)
            } else if (let Some(localVal) <- receiver.AsLocalVar()) {
                if (let Some(argExpr) <- localVal.GetExpr()) {
                    if (argExpr.GetExprKind() == ExprKind.LOAD &&
                        refEq((argExpr as Load).getOrThrow().GetLocation(), thisArg)) {
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
        uninitedMemberIdx: ArrayList<Int64>
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
        let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_class_uninitialized_field,
            ToPosition(fn.GetDebugLocation()))
        for (index in uninitedMemberIdx) {
            let identifier = members[index].name
            builder.AddNote("in line ${members[index].loc.GetBeginPos().line}, variable '${identifier}' " +
                "need to be initialized")
            AddMaybeInitedPosNote(builder, identifier, state.GetMaybeInitedPos(index))
        }
        builder.Emit()
    }

    private func CheckUninitedDefMember(
        state: MaybeUninitDomain,
        expr: Expression,
        members: ArrayList<MemberVarInfo>,
        index: Int64,
        onlyCheckSuper: Bool,
        checkResult: CHIRCheckResult
    ): Unit {
        match (state.IsMaybeUninitedMember(index)) {
            case MaybeUninitMemberKind.SUPER_MEMBER =>
                checkResult.AddError("super member '${members[index].name}' is not allowed to be used before calling super()")
            case MaybeUninitMemberKind.LOCAL_MEMBER =>
                if (!onlyCheckSuper) {
                    let identifier = members[index].name
                    let builder = diag.DiagnoseRefactor(DiagKindRefactor.chir_used_before_initialization,
                        ToPosition(expr.GetDebugLocation()), identifier)
                    AddMaybeInitedPosNote(builder, identifier, state.GetMaybeInitedPos(index))
                    builder.Emit()
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
        if (refEq(store.GetLocation(), fn.GetParam(0)) && paths.size == 1) {
            let index = Int64(paths[0])
            if (members[index].TestAttr(Attribute.READONLY)) {
                match (state.IsMaybeInitedMember(index)) {
                    case MaybeInitMemberKind.SUPER_MEMBER =>
                        diag.DiagnoseRefactor(DiagKindRefactor.chir_cannot_assign_initialized_let_variable,
                            ToPosition(store.GetDebugLocation())).Emit()
                    case MaybeInitMemberKind.LOCAL_MEMBER =>
                        diag.DiagnoseRefactor(DiagKindRefactor.chir_cannot_assign_initialized_let_variable,
                            ToPosition(store.GetDebugLocation())).Emit()
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
        let calleeKind = memberFunc.GetFuncKind()
        if (calleeKind == FuncKind.GETTER || calleeKind == FuncKind.SETTER) {
            identifier = identifier[1..identifier.size - 3]
        }
        checkResult.AddError("'${identifier}' is not allowed to be accessed before all member variables are initialized")
    }
}

private func BuildConstructorContext(fn: Function): VarInitConstructorContext {
    let ctorInfo = ConstructorInitInfo()
    let members = ArrayList<MemberVarInfo>()
    if (!fn.IsConstructor()) {
        return VarInitConstructorContext(ctorInfo, members)
    }
    if (let Some(customDef) <- fn.GetOuterDeclaredOrExtendedDef()) {
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
        let resultTy = expr.GetResultType().getOrThrow()
        if (resultTy.StripAllRefs().IsNothing()) {
            return true
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
    if (refEq(location, thisArg)) {
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
    if (refEq(location, thisArg) && (!shouldBeNested || store.GetPath().size > 1)) {
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
    maybeInitedPos: TreeSet<Int64>,
    checkResult: CHIRCheckResult
): Unit {
    checkResult.AddError("variable '${identifier}' is used before initialization")
    AddMaybeInitedPosNote(checkResult, identifier, maybeInitedPos)
}

private func AddMaybeInitedPosNote(
    builder: CHIRCheckResult,
    identifier: String,
    maybeInitedPos: TreeSet<Int64>
): Unit {
    if (maybeInitedPos.isEmpty()) {
        return
    }
    var message = "we detected variable '${identifier}' is assigned in line "
    for (pos in maybeInitedPos) {
        message += "${pos}, "
    }
    message += "but in runtime, these codes might not be executed."
    builder.AddNote(message)
}

private func AddMaybeInitedPosNote(
    builder: DiagnosticBuilder,
    identifier: String,
    maybeInitedPos: TreeSet<Int64>
): Unit {
    if (maybeInitedPos.isEmpty()) {
        return
    }
    var message = "we detected variable '${identifier}' is assigned in line "
    for (pos in maybeInitedPos) {
        message += "${pos}, "
    }
    message += "but in runtime, these codes might not be executed."
    builder.AddNote(message)
}
