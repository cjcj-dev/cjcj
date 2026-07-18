package cjcj::sema.Desugar.AfterTypeCheck

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*

private let INDEX_COMPILER: String = "$index-compiler"
private let STOP_COMPILER: String = "$stop-compiler"
private let ITER_COMPILER: String = "iter-compiler"
private let STRING_SIZE_NAME: String = "size"
private let SUBSCRIPT_OPERATOR_NAME: String = "[]"
private let ITERATOR_METHOD_NAME: String = "iterator"
private let NEXT_METHOD_NAME: String = "next"
private let OPTION_VALUE_CTOR: String = "Some"
private let OPTION_NONE_CTOR: String = "None"
private let V_COMPILER: String = "v-compiler"

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

private func FuncRetTyOf(decl: Decl): Option<Ty> {
    if (let Some(t) <- decl.GetTy()) {
        if (let Some(funcTy) <- (t as FuncTy)) {
            return funcTy.retTy
        }
    }
    return None
}

private func UnitTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
}

private func BoolTy(): Ty {
    return TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN)
}

private func NothingTy(): Ty {
    return TypeManager.GetNothingTy()
}

private func CreateVarRef(decl: VarDecl, pos: Node): RefExpr {
    let refExpr = CreateRefExpr(decl, pos)
    if (let Some(ty) <- decl.GetTy()) {
        refExpr.SetTy(ty)
    }
    refExpr.curFile = decl.curFile
    return refExpr
}

private func CreateSynthesizedNoArgMemberCall(source: Node, baseExpr: Expr, name: String,
    context: Option<ASTContext>, synthesizer: Option<(ASTContext, SynPos, Node) -> Ty>): Option<CallExpr> {
    let memberAccess = CreateMemberAccess(baseExpr, name)
    memberAccess.target = None
    memberAccess.targets.clear()
    CopyBasicInfo(source, memberAccess)
    memberAccess.SetTy(Ty.GetInitialTy())
    AddCurFile(memberAccess, file: source.curFile)

    let callExpr = CreateCallExpr(memberAccess, ArrayList<FuncArg>())
    CopyBasicInfo(source, callExpr)
    callExpr.SetTy(Ty.GetInitialTy())
    AddCurFile(callExpr, file: source.curFile)
    if (let Some(ctx) <- context) {
        if (let Some(synthesize) <- synthesizer) {
            let synTy = synthesize(ctx, SynPos.EXPR_ARG, callExpr)
            if (Ty.IsTyCorrect(Some(synTy))) {
                callExpr.SetTy(synTy)
            }
            if (let Some(funcDecl) <- callExpr.resolvedFunction) {
                memberAccess.target = funcDecl
            }
            return Some(callExpr)
        }
    }
    return None
}

private func CreateIndexVar(forInExpr: ForInExpr, rangeExpr: RangeExpr): Option<VarDecl> {
    if (let Some(startExpr) <- rangeExpr.startExpr) {
        if (let Some(initializer) <- CloneExpr(startExpr)) {
            var indexName = INDEX_COMPILER
            if (let Some(pattern) <- forInExpr.pattern) {
                if (let Some(varDecl) <- GetRangePatternVarDecl(pattern)) {
                    indexName = "$iter-" + varDecl.identifier.Val()
                }
            }
            let index = CreateVarDecl(indexName, initializer, None)
            index.EnableAttr(Attribute.IMPLICIT_ADD)
            index.isVar = true
            index.assignPos = index.begin
            index.fullPackageName = forInExpr.GetFullPackageName()
            index.begin = if (let Some(patternNode) <- forInExpr.pattern) { patternNode.begin } else { forInExpr.begin }
            index.end = if (let Some(patternEndNode) <- forInExpr.pattern) { patternEndNode.end } else { forInExpr.end }
            index.curFile = forInExpr.curFile
            return index
        }
    }
    return None
}

private func CreateStopVar(rangeExpr: RangeExpr): Option<VarDecl> {
    if (let Some(stopExpr) <- rangeExpr.stopExpr) {
        if (let Some(initializer) <- CloneExpr(stopExpr)) {
            let stop = CreateVarDecl(STOP_COMPILER, initializer, None)
            stop.begin = stopExpr.begin
            stop.end = stopExpr.end
            stop.curFile = stopExpr.curFile
            return stop
        }
    }
    return None
}

private func CreateStringIndexVar(forInExpr: ForInExpr): VarDecl {
    let litZero = CreateLitConstExpr(LitConstKind.INTEGER, "0", TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
    let index = CreateVarDecl(ITER_COMPILER, litZero, None)
    index.EnableAttr(Attribute.IMPLICIT_ADD)
    index.isVar = true
    index.assignPos = index.begin
    index.curFile = forInExpr.curFile
    CopyBasicInfo(forInExpr, index)
    index.SetTy(litZero.GetTy() ?? TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
    if (let Some(pattern) <- forInExpr.pattern) {
        index.begin = pattern.begin
        index.end = pattern.end
    }
    return index
}

private func CreateStringTmpVar(forInExpr: ForInExpr): Option<VarDecl> {
    if (let Some(inExpr) <- forInExpr.inExpression) {
        let tmp = CreateTmpVarDecl()
        tmp.initializer = inExpr
        tmp.isVar = false
        tmp.curFile = forInExpr.curFile
        CopyBasicInfo(inExpr, tmp)
        if (let Some(ty) <- inExpr.GetTy()) {
            tmp.SetTy(ty)
        }
        return tmp
    }
    return None
}

private func FirstGetterDecl(decl: Decl): Option<FuncDecl> {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        return funcDecl
    }
    let used = GetUsedMemberDecl(decl, true)
    if (let Some(funcDecl) <- (used as FuncDecl)) {
        return funcDecl
    }
    return None
}

private func AsFuncDecl(decl: Option<Decl>): Option<FuncDecl> {
    if (let Some(value) <- decl) {
        return value as FuncDecl
    }
    return None
}

private func CreateSizeCall(typeManager: TypeManager, forInExpr: ForInExpr, tmp: VarDecl): Option<CallExpr> {
    let tmpTy = tmp.GetTy()
    let sizeDecls = FieldLookup(typeManager, Ty.GetDeclPtrOfTy(tmpTy), STRING_SIZE_NAME,
        info: LookupInfo(baseTy: tmpTy, file: forInExpr.curFile, lookupExtend: false))
    if (sizeDecls.isEmpty()) {
        return None
    }
    if (let Some(getter) <- FirstGetterDecl(sizeDecls[0])) {
        let base = CreateMemberAccess(CreateVarRef(tmp, forInExpr), getter)
        base.curFile = forInExpr.curFile
        let args = ArrayList<FuncArg>()
        let callTy = sizeDecls[0].GetTy()
        let call = CreateCallExpr(base, args, Some(getter), callTy, CallKind.CALL_DECLARED_FUNCTION)
        CopyBasicInfo(forInExpr, call)
        AddCurFile(call, file: forInExpr.curFile)
        if (let Some(retTy) <- FuncRetTyOf(getter)) {
            call.SetTy(retTy)
        } else if (let Some(ty) <- callTy) {
            call.SetTy(ty)
        } else {
            call.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
        }
        return call
    }
    return None
}

private func CreateStringEndVar(typeManager: TypeManager, forInExpr: ForInExpr, tmp: VarDecl): Option<VarDecl> {
    if (let Some(sizeCall) <- CreateSizeCall(typeManager, forInExpr, tmp)) {
        let end = CreateTmpVarDecl()
        end.initializer = sizeCall
        end.isVar = false
        end.curFile = forInExpr.curFile
        CopyBasicInfo(forInExpr, end)
        end.begin = tmp.begin
        end.end = tmp.end
        if (let Some(ty) <- sizeCall.GetTy()) {
            end.SetTy(ty)
        }
        return end
    }
    return None
}

private func CreateStringElementCall(typeManager: TypeManager, forInExpr: ForInExpr, tmp: VarDecl,
    index: VarDecl, expectedElementTy: Option<Ty>): Option<CallExpr> {
    let base = CreateMemberAccess(CreateVarRef(tmp, forInExpr), SUBSCRIPT_OPERATOR_NAME)
    base.SetTy(Ty.GetInitialTy())
    base.curFile = forInExpr.curFile
    CopyBasicInfo(forInExpr, base)
    let tmpTy = tmp.GetTy()
    let subscriptTargets = FieldLookup(typeManager, Ty.GetDeclPtrOfTy(tmpTy), SUBSCRIPT_OPERATOR_NAME,
        info: LookupInfo(baseTy: tmpTy, file: forInExpr.curFile))
    for (target in subscriptTargets) {
        base.targets.add(Some((target as FuncDecl).getOrThrow()))
    }
    let selectedTarget = SelectStringSubscriptTarget(typeManager, subscriptTargets, index, expectedElementTy)
    if (let Some(firstTarget) <- selectedTarget) {
        base.target = firstTarget
        if (let Some(targetTy) <- firstTarget.GetTy()) {
            base.SetTy(targetTy)
        }
    }
    let args = ArrayList<FuncArg>()
    let indexRef = CreateVarRef(index, forInExpr)
    CopyBasicInfo(forInExpr, indexRef)
    args.add(CreateFuncArg(indexRef))
    let call = CreateCallExpr(base, args, selectedTarget,
        if (let Some(target) <- selectedTarget) { FuncRetTyOf(target) } else { None },
        CallKind.CALL_DECLARED_FUNCTION)
    CopyBasicInfo(forInExpr, call)
    AddCurFile(call, file: forInExpr.curFile)
    if (let Some(target) <- selectedTarget) {
        if (let Some(retTy) <- FuncRetTyOf(target)) {
            call.SetTy(retTy)
            return call
        }
    }
    return None
}

private func SelectStringSubscriptTarget(typeManager: TypeManager, targets: ArrayList<Decl>,
    index: VarDecl, expectedElementTy: Option<Ty>): Option<FuncDecl> {
    let indexTy = index.GetTy() ?? return AsFuncDecl(if (!targets.isEmpty()) { Some(targets[0]) } else { None })
    for (target in targets) {
        if (let Some(funcDecl) <- AsFuncDecl(Some(target))) {
            let paramTys = GetParamTys(funcDecl)
            if (!paramTys.isEmpty() &&
                typeManager.CheckTypeCompatibility(paramTys[paramTys.size - 1], indexTy) !=
                    TypeCompatibility.INCOMPATIBLE) {
                if (let Some(expectedTy) <- expectedElementTy) {
                    if (let Some(retTy) <- FuncRetTyOf(funcDecl)) {
                        if (typeManager.CheckTypeCompatibility(expectedTy, retTy) != TypeCompatibility.INCOMPATIBLE) {
                            return funcDecl
                        }
                    }
                } else {
                    return funcDecl
                }
            }
        }
    }
    return AsFuncDecl(if (!targets.isEmpty()) { Some(targets[0]) } else { None })
}

private func CreateStringLetIter(typeManager: TypeManager, forInExpr: ForInExpr, tmp: VarDecl,
    index: VarDecl): Option<VarDecl> {
    if (let Some(pattern) <- forInExpr.pattern) {
        if (let Some(varDecl) <- GetRangePatternVarDecl(pattern)) {
            if (let Some(elemCall) <- CreateStringElementCall(typeManager, forInExpr, tmp, index, varDecl.GetTy())) {
                varDecl.parentPattern = None
                varDecl.initializer = elemCall
                varDecl.curFile = forInExpr.curFile
                if (let Some(ty) <- elemCall.GetTy()) {
                    varDecl.SetTy(ty)
                }
                forInExpr.patternInDesugarExpr = pattern
                forInExpr.pattern = None
                return varDecl
            }
        }
    }
    return None
}

private func CreateStringUpdate(forInExpr: ForInExpr, index: VarDecl): AssignExpr {
    let update = AssignExpr()
    update.curFile = forInExpr.curFile
    update.leftValue = CreateVarRef(index, forInExpr)
    update.rightExpr = CreateLitConstExpr(LitConstKind.INTEGER, "1", TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
    update.op = TokenKind.ADD_ASSIGN
    update.isCompound = true
    update.begin = forInExpr.begin
    update.end = forInExpr.end
    update.SetTy(UnitTy())
    update.EnableAttr(Attribute.COMPILER_ADD)
    return update
}

private func CreateStringCond(forInExpr: ForInExpr, index: VarDecl, end: VarDecl): BinaryExpr {
    let cond = CreateBinaryExpr(CreateVarRef(index, forInExpr), CreateVarRef(end, forInExpr), TokenKind.LT)
    cond.curFile = forInExpr.curFile
    cond.SetTy(BoolTy())
    if (let Some(inExpr) <- forInExpr.inExpression) {
        cond.begin = inExpr.begin
        cond.end = inExpr.end
    }
    return cond
}

private func RangeIsIncreasing(rangeExpr: RangeExpr): Bool {
    if (let Some(stepExpr) <- rangeExpr.stepExpr) {
        return !stepExpr.constNumValue.asInt.IsNegativeNum()
    }
    return true
}

private func IsStepOne(rangeExpr: RangeExpr): Bool {
    if (let Some(startExpr) <- rangeExpr.startExpr) {
        if (let Some(startTy) <- startExpr.GetTy()) {
            if (startTy.IsInvalid() || !startTy.IsInteger()) {
                return false
            }
        } else {
            return false
        }
    } else {
        return false
    }
    if (let Some(stopExpr) <- rangeExpr.stopExpr) {
        if (let Some(stopTy) <- stopExpr.GetTy()) {
            if (stopTy.IsInvalid() || !stopTy.IsInteger()) {
                return false
            }
        } else {
            return false
        }
    } else {
        return false
    }
    if (let Some(stepExpr) <- rangeExpr.stepExpr) {
        if (!stepExpr.isConst) {
            return false
        }
        let stepValue = stepExpr.constNumValue.asInt.`Int64`()
        return stepValue == 1 || stepValue == -1
    }
    return true
}

private func IsCallRangeConstructor(callExpr: CallExpr): Bool {
    let rangeConstructorParamSize: Int64 = 6
    let rangeConstructorIntLength: Int64 = 3
    if (callExpr.callKind != CallKind.CALL_OBJECT_CREATION) {
        return false
    }
    let callee = (callExpr.baseFunc ?? return false) as RefExpr
    let calledFunc = ((callee ?? return false).ref.target ?? return false) as FuncDecl
    let funcBody = (calledFunc ?? return false).funcBody ?? return false
    if (funcBody.paramLists.isEmpty() || funcBody.paramLists[0].params.size != rangeConstructorParamSize) {
        return false
    }
    if (callExpr.args.size != rangeConstructorParamSize) {
        return false
    }
    var index: Int64 = 0
    while (index < rangeConstructorIntLength) {
        let argTy = callExpr.args[index].GetTy() ?? return false
        if (!argTy.IsInteger()) {
            return false
        }
        index++
    }
    let stepExpr = callExpr.args[rangeConstructorIntLength - 1].expr ?? return false
    let stepLit = (stepExpr as LitConstExpr) ?? return false
    let stepValue = stepLit.constNumValue.asInt.`Int64`()
    if (stepValue != 1 && stepValue != -1) {
        return false
    }
    index = rangeConstructorIntLength
    while (index < rangeConstructorParamSize) {
        let argTy = callExpr.args[index].GetTy() ?? return false
        if (!argTy.IsBoolean()) {
            return false
        }
        index++
    }
    let isClosedExpr = callExpr.args[rangeConstructorParamSize - 1].expr ?? return false
    let isClosedLit = (isClosedExpr as LitConstExpr) ?? return false
    return isClosedLit.constNumValue.asBoolean
}

private func IsClosedRangeOne(forInExpr: ForInExpr): Bool {
    let inExpr = forInExpr.inExpression ?? return false
    if (let Some(rangeExpr) <- (inExpr as RangeExpr)) {
        if (let Some(desugar) <- rangeExpr.desugarExpr) {
            if (let Some(callExpr) <- (desugar as CallExpr)) {
                return IsCallRangeConstructor(callExpr)
            }
            return false
        }
        if (rangeExpr.isClosed && IsStepOne(rangeExpr)) {
            return true
        }
        return false
    }
    if (let Some(callExpr) <- (inExpr as CallExpr)) {
        return IsCallRangeConstructor(callExpr)
    }
    return false
}

private func CreateRangeCond(forInExpr: ForInExpr, index: VarDecl, stop: VarDecl, op: TokenKind): BinaryExpr {
    let left = CreateVarRef(index, stop)
    let right = CreateVarRef(stop, stop)
    let cond = CreateBinaryExpr(left, right, op)
    cond.curFile = forInExpr.curFile
    cond.SetTy(BoolTy())
    if (let Some(inExpr) <- forInExpr.inExpression) {
        cond.begin = inExpr.begin
        cond.end = inExpr.end
    }
    return cond
}

private func CreateUpdate(forInExpr: ForInExpr, rangeExpr: RangeExpr, index: VarDecl): Option<AssignExpr> {
    let update = AssignExpr()
    update.curFile = forInExpr.curFile
    update.leftValue = CreateVarRef(index, rangeExpr)
    if (let Some(stepExpr) <- rangeExpr.stepExpr) {
        update.rightExpr = stepExpr
        rangeExpr.stepExpr = None
    } else {
        let stepTy = if (let Some(indexTy) <- index.GetTy()) { indexTy } else { TypeManager.GetInvalidTy() }
        update.rightExpr = CreateLitConstExpr(LitConstKind.INTEGER, "1", stepTy)
    }
    update.op = TokenKind.ADD_ASSIGN
    update.isCompound = true
    update.begin = rangeExpr.begin
    update.end = rangeExpr.end
    update.SetTy(UnitTy())
    update.EnableAttr(Attribute.COMPILER_ADD)
    return update
}

private func CreateGuard(forInExpr: ForInExpr, rangeCond: BinaryExpr, includeRangeCond: Bool): IfExpr {
    let guardIf = IfExpr()
    guardIf.sugarKind = SugarKind.FOR_IN_EXPR
    guardIf.curFile = forInExpr.curFile
    guardIf.begin = rangeCond.begin
    guardIf.end = rangeCond.end
    if (let Some(patternGuard) <- forInExpr.patternGuard) {
        if (includeRangeCond) {
            if (let Some(clonedRangeCond) <- (ASTCloner.Clone(rangeCond) as Expr)) {
                let andCond = CreateBinaryExpr(clonedRangeCond, patternGuard, TokenKind.AND)
                andCond.SetTy(BoolTy())
                andCond.curFile = forInExpr.curFile
                guardIf.condExpr = andCond
            } else {
                guardIf.condExpr = patternGuard
            }
        } else {
            guardIf.condExpr = patternGuard
        }
    } else if (includeRangeCond) {
        if (let Some(clonedCond) <- (ASTCloner.Clone(rangeCond) as Expr)) {
            guardIf.condExpr = clonedCond
        } else {
            guardIf.condExpr = rangeCond
        }
    } else {
        let always = CreateLitConstExpr(LitConstKind.BOOL, "true", BoolTy())
        always.begin = rangeCond.begin
        always.end = rangeCond.end
        always.EnableAttr(Attribute.COMPILER_ADD)
        guardIf.condExpr = always
    }
    if (let Some(body) <- forInExpr.body) {
        guardIf.thenBody = body
    } else {
        let emptyBody = Block()
        emptyBody.SetTy(UnitTy())
        guardIf.thenBody = emptyBody
    }
    guardIf.SetTy(UnitTy())
    guardIf.EnableAttr(Attribute.IMPLICIT_ADD)
    return guardIf
}

private func FinishRangeRearrange(forInExpr: ForInExpr, index: VarDecl, stop: VarDecl, update: AssignExpr,
    rangeCond: BinaryExpr): Unit {
    let nodes = ArrayList<Node>()
    nodes.add(index)
    nodes.add(stop)
    nodes.add(update)
    nodes.add(rangeCond)
    let block = CreateBlock(nodes, UnitTy())
    if (let Some(inExpr) <- forInExpr.inExpression) {
        CopyBasicInfo(inExpr, block)
    } else {
        CopyBasicInfo(forInExpr, block)
    }
    AddCurFile(block, file: forInExpr.curFile)
    forInExpr.inExpression = Some(block)
    forInExpr.forInKind = ForInKind.FORIN_RANGE
    if (let Some(body) <- forInExpr.body) {
        RearrangeRefLoop(forInExpr, forInExpr, body)
    }
}

private func GetRangePatternVarDecl(pattern: Pattern): Option<VarDecl> {
    if (let Some(varPattern) <- (pattern as VarPattern)) {
        return varPattern.varDecl
    }
    if (let Some(varOrEnum) <- (pattern as VarOrEnumPattern)) {
        if (let Some(realPattern) <- varOrEnum.pattern) {
            return GetRangePatternVarDecl(realPattern)
        }
    }
    return None
}

private func BindRangePatternVar(forInExpr: ForInExpr, index: VarDecl): Unit {
    if (let Some(pattern) <- forInExpr.pattern) {
        if (let Some(varDecl) <- GetRangePatternVarDecl(pattern)) {
            varDecl.parentPattern = None
            let initRef = CreateVarRef(index, index)
            initRef.begin = index.begin
            initRef.end = index.end
            varDecl.initializer = initRef
            varDecl.curFile = forInExpr.curFile
            if (let Some(indexTy) <- index.GetTy()) {
                varDecl.SetTy(indexTy)
            }
        }
    }
}

private func SynthesizeNode(context: Option<ASTContext>, synthesizer: Option<(ASTContext, SynPos, Node) -> Ty>,
    pos: SynPos, node: Node): Option<Ty> {
    if (let Some(ctx) <- context) {
        if (let Some(synthesize) <- synthesizer) {
            return Some(synthesize(ctx, pos, node))
        }
    }
    return None
}

private func ReArrangeForInRangeExpr(forInExpr: ForInExpr, rangeExpr: RangeExpr,
    context: Option<ASTContext>, synthesizer: Option<(ASTContext, SynPos, Node) -> Ty>): Unit {
    if (let Some(index) <- CreateIndexVar(forInExpr, rangeExpr)) {
        if (let Some(stop) <- CreateStopVar(rangeExpr)) {
            if (let Some(update) <- CreateUpdate(forInExpr, rangeExpr, index)) {
                let increasing = RangeIsIncreasing(rangeExpr)
                let op = if (rangeExpr.isClosed) {
                    if (increasing) { TokenKind.LE } else { TokenKind.GE }
                } else {
                    if (increasing) { TokenKind.LT } else { TokenKind.GT }
                }
                let rangeCond = CreateRangeCond(forInExpr, index, stop, op)
                if (let Some(inExpr) <- forInExpr.inExpression) {
                    CopyBasicInfo(inExpr, update)
                }
                AddCurFile(update, file: forInExpr.curFile)
                if (let Some(updateTy) <- SynthesizeNode(context, synthesizer, SynPos.EXPR_ARG, update)) {
                    if (!Ty.IsTyCorrect(Some(updateTy))) {
                        return
                    }
                    update.SetTy(updateTy)
                }
                BindRangePatternVar(forInExpr, index)
                FinishRangeRearrange(forInExpr, index, stop, update, rangeCond)
            }
        }
    }
}

private func FinishStringDesugar(forInExpr: ForInExpr, index: VarDecl, tmp: VarDecl, end: VarDecl,
    whileExpr: WhileExpr): Unit {
    let nodes = ArrayList<Node>()
    nodes.add(index)
    nodes.add(tmp)
    nodes.add(end)
    nodes.add(whileExpr)
    let block = CreateBlock(nodes, UnitTy())
    CopyBasicInfo(forInExpr, block)
    AddCurFile(block, file: forInExpr.curFile)
    if (let Some(whileBody) <- whileExpr.body) {
        RearrangeRefLoop(forInExpr, whileExpr, whileBody)
    }
    forInExpr.desugarExpr = block
    forInExpr.inExpression = None
    forInExpr.patternGuard = None
    forInExpr.body = None
    forInExpr.forInKind = ForInKind.FORIN_STRING
}

private func CreateStringElementCallForRearrange(forInExpr: ForInExpr, tmp: VarDecl,
    index: VarDecl, end: VarDecl, context: Option<ASTContext>,
    synthesizer: Option<(ASTContext, SynPos, Node) -> Ty>): Option<CallExpr> {
    let tmpRef = CreateVarRef(tmp, end)
    CopyBasicInfo(end, tmpRef)
    let base = CreateMemberAccess(tmpRef, SUBSCRIPT_OPERATOR_NAME)
    base.SetTy(Ty.GetInitialTy())
    if (let Some(baseExpr) <- base.baseExpr) {
        CopyBasicInfo(end, baseExpr)
    }
    let indexRef = CreateVarRef(index, end)
    CopyBasicInfo(end, indexRef)
    let args = ArrayList<FuncArg>()
    args.add(CreateFuncArg(indexRef))
    if (let Some(argExpr) <- args[0].expr) {
        CopyBasicInfo(end, argExpr)
    }
    let call = CreateCallExpr(base, args)
    CopyBasicInfo(end, call)
    AddCurFile(call, file: forInExpr.curFile)
    if (let Some(callTy) <- SynthesizeNode(context, synthesizer, SynPos.EXPR_ARG, call)) {
        if (!Ty.IsTyCorrect(Some(callTy))) {
            return None
        }
        call.SetTy(callTy)
        return call
    }
    return Some(call)
}

private func BindStringPatternVarForRearrange(forInExpr: ForInExpr, tmp: VarDecl,
    index: VarDecl, end: VarDecl, context: Option<ASTContext>,
    synthesizer: Option<(ASTContext, SynPos, Node) -> Ty>): Unit {
    if (let Some(pattern) <- forInExpr.pattern) {
        if (let Some(varDecl) <- GetRangePatternVarDecl(pattern)) {
            if (let Some(elemCall) <- CreateStringElementCallForRearrange(
                forInExpr, tmp, index, end, context, synthesizer)) {
                varDecl.initializer = elemCall
            }
        }
    }
}

private func FinishStringRearrange(forInExpr: ForInExpr, index: VarDecl, tmp: VarDecl, end: VarDecl): Unit {
    let nodes = ArrayList<Node>()
    nodes.add(index)
    nodes.add(tmp)
    nodes.add(end)
    let block = CreateBlock(nodes, UnitTy())
    if (let Some(initializer) <- tmp.initializer) {
        CopyBasicInfo(initializer, block)
    } else {
        CopyBasicInfo(forInExpr, block)
    }
    AddCurFile(block, file: forInExpr.curFile)
    forInExpr.inExpression = Some(block)
    forInExpr.forInKind = ForInKind.FORIN_STRING
    if (let Some(body) <- forInExpr.body) {
        RearrangeRefLoop(forInExpr, forInExpr, body)
    }
}

private func ReArrangeForInStringExpr(typeManager: TypeManager, forInExpr: ForInExpr,
    context: Option<ASTContext>, synthesizer: Option<(ASTContext, SynPos, Node) -> Ty>): Unit {
    let index = CreateStringIndexVar(forInExpr)
    if (let Some(ctx) <- context) {
        ctx.AddDeclName(Names(ITER_COMPILER, forInExpr.scopeName), index)
    }
    if (let Some(tmp) <- CreateStringTmpVar(forInExpr)) {
        if (let Some(end) <- CreateStringEndVar(typeManager, forInExpr, tmp)) {
            if (let Some(initializer) <- end.initializer) {
                initializer.begin = tmp.begin
                initializer.end = tmp.end
                AddCurFile(initializer, file: forInExpr.curFile)
                if (let Some(endTy) <- SynthesizeNode(context, synthesizer, SynPos.EXPR_ARG, initializer)) {
                    if (!Ty.IsTyCorrect(Some(endTy))) {
                        return
                    }
                    end.SetTy(endTy)
                }
            }
            BindStringPatternVarForRearrange(forInExpr, tmp, index, end, context, synthesizer)
            FinishStringRearrange(forInExpr, index, tmp, end)
        }
    }
}

private func CreateIteratorVar(forInExpr: ForInExpr, context: Option<ASTContext>,
    synthesizer: Option<(ASTContext, SynPos, Node) -> Ty>): Option<VarDecl> {
    if (let Some(inExpr) <- forInExpr.inExpression) {
        let inExprBegin = inExpr.begin
        let inExprEnd = inExpr.end
        if (let Some(iteratorCall) <- CreateSynthesizedNoArgMemberCall(inExpr, inExpr, ITERATOR_METHOD_NAME,
            context, synthesizer)) {
            let iterator = CreateVarDecl(ITER_COMPILER, iteratorCall, None)
            iterator.begin = if (let Some(pattern) <- forInExpr.pattern) { pattern.begin } else { inExprBegin }
            iterator.end = if (let Some(patternEnd) <- forInExpr.pattern) { patternEnd.end } else { inExprEnd }
            iterator.curFile = forInExpr.curFile
            if (let Some(iteratorTy) <- iteratorCall.GetTy()) {
                iterator.SetTy(iteratorTy)
            }
            return iterator
        }
    }
    return None
}

private func CreateIteratorNextCall(forInExpr: ForInExpr, iterator: VarDecl, context: Option<ASTContext>,
    synthesizer: Option<(ASTContext, SynPos, Node) -> Ty>): Option<CallExpr> {
    let iteratorRef = CreateVarRef(iterator, forInExpr)
    CopyBasicInfo(forInExpr, iteratorRef)
    if (let Some(iteratorTy) <- iterator.GetTy()) {
        iteratorRef.SetTy(iteratorTy)
    }
    return CreateSynthesizedNoArgMemberCall(forInExpr, iteratorRef, NEXT_METHOD_NAME, context, synthesizer)
}

private func CreateOptionCtorRef(enumTy: EnumTy, ctorName: String, ctorTy: Ty): Option<RefExpr> {
    if (let Some(enumDecl) <- enumTy.declPtr) {
        if (let Some(ctorDecl) <- LookupEnumMember(enumDecl, ctorName)) {
            let refExpr = CreateRefExpr(ctorDecl)
            refExpr.ref.targets.add(Some(ctorDecl))
            refExpr.SetTy(ctorTy)
            for (typeArg in enumTy.typeArgs) {
                refExpr.instTys.add(typeArg)
            }
            return refExpr
        }
    }
    return None
}

private func CreateLoopJump(refLoop: Expr, isBreak: Bool): JumpExpr {
    let jumpExpr = JumpExpr()
    jumpExpr.isBreak = isBreak
    jumpExpr.refLoop = refLoop
    jumpExpr.SetTy(NothingTy())
    return jumpExpr
}

private func CreateNoneCaseForIter(enumTy: EnumTy, refLoop: Expr): Option<MatchCase> {
    if (let Some(noneRef) <- CreateOptionCtorRef(enumTy, OPTION_NONE_CTOR, enumTy)) {
        let nonePattern = EnumPattern()
        nonePattern.constructor = noneRef
        nonePattern.SetTy(enumTy)
        let breakExpr = CreateLoopJump(refLoop, true)
        let breakNodes = ArrayList<Node>()
        breakNodes.add(breakExpr)
        let breakBlock = CreateBlock(breakNodes, NothingTy())
        let caseNone = MatchCase()
        caseNone.patterns.add(nonePattern)
        caseNone.exprOrDecls = breakBlock
        caseNone.SetTy(NothingTy())
        return caseNone
    }
    return None
}

private func CreateWildcardContinueCase(patternTy: Ty, refLoop: Expr): MatchCase {
    let wildcard = WildcardPattern()
    wildcard.SetTy(patternTy)
    let continueExpr = CreateLoopJump(refLoop, false)
    let continueNodes = ArrayList<Node>()
    continueNodes.add(continueExpr)
    let continueBlock = CreateBlock(continueNodes, NothingTy())
    let wildCase = MatchCase()
    wildCase.patterns.add(wildcard)
    wildCase.exprOrDecls = continueBlock
    wildCase.SetTy(NothingTy())
    return wildCase
}

private func CreatePatternBodyCase(forInExpr: ForInExpr, refLoop: Expr): Option<MatchCase> {
    if (let Some(pattern) <- forInExpr.pattern) {
        if (let Some(body) <- forInExpr.body) {
            let casePat = MatchCase()
            casePat.patterns.add(pattern)
            forInExpr.patternInDesugarExpr = pattern
            casePat.patternGuard = forInExpr.patternGuard
            casePat.exprOrDecls = body
            body.begin.Mark(PositionStatus.IGNORE)
            body.end.Mark(PositionStatus.IGNORE)
            RearrangeRefLoop(forInExpr, refLoop, body)
            if (let Some(bodyTy) <- body.GetTy()) {
                casePat.SetTy(bodyTy)
            }
            return casePat
        }
    }
    return None
}

private func CreateSomeCaseForIter(typeManager: TypeManager, enumTy: EnumTy, forInExpr: ForInExpr,
    refLoop: Expr): Option<MatchCase> {
    if (enumTy.typeArgs.size != 1) {
        return None
    }
    if (let None <- forInExpr.pattern) {
        return None
    }
    let pattern = forInExpr.pattern.getOrThrow()
    if (let None <- pattern.GetTy()) {
        return None
    }
    let patternTy = pattern.GetTy().getOrThrow()
    let someTy = typeManager.GetFunctionTy(enumTy.typeArgs.toArray(), enumTy)
    if (let Some(someRef) <- CreateOptionCtorRef(enumTy, OPTION_VALUE_CTOR, someTy)) {
        let somePattern = EnumPattern()
        somePattern.constructor = someRef
        somePattern.SetTy(enumTy)
        let valuePattern = CreateVarPattern(V_COMPILER, patternTy)
        CopyBasicInfo(pattern, valuePattern)
        somePattern.patterns.add(valuePattern)
        if (let Some(valueDecl) <- valuePattern.varDecl) {
            let selector = CreateRefExpr(valueDecl, forInExpr)
            selector.SetTy(patternTy)
            let innerCases = ArrayList<MatchCase>()
            if (let Some(casePat) <- CreatePatternBodyCase(forInExpr, refLoop)) {
                casePat.SetCtxExprForPatterns(selector)
                innerCases.add(casePat)
                let wildcardCase = CreateWildcardContinueCase(patternTy, refLoop)
                wildcardCase.SetCtxExprForPatterns(selector)
                innerCases.add(wildcardCase)
                let innerTy = if (let Some(body) <- forInExpr.body) {
                    body.GetTy() ?? UnitTy()
                } else {
                    UnitTy()
                }
                let insideMatch = CreateMatchExpr(selector, innerCases, innerTy)
                CopyBasicInfo(forInExpr, insideMatch)
                AddCurFile(insideMatch, file: forInExpr.curFile)
                let someNodes = ArrayList<Node>()
                someNodes.add(insideMatch)
                let someBlock = CreateBlock(someNodes, NothingTy())
                let caseSome = MatchCase()
                caseSome.patterns.add(somePattern)
                caseSome.exprOrDecls = someBlock
                caseSome.SetTy(NothingTy())
                return caseSome
            }
        }
    }
    return None
}

private func FinishIterDesugar(forInExpr: ForInExpr, iterator: VarDecl, whileExpr: WhileExpr): Unit {
    let nodes = ArrayList<Node>()
    nodes.add(iterator)
    nodes.add(whileExpr)
    let block = CreateBlock(nodes, UnitTy())
    CopyBasicInfo(forInExpr, block)
    AddCurFile(block, file: forInExpr.curFile)
    forInExpr.desugarExpr = block
    forInExpr.inExpression = None
    forInExpr.pattern = None
    forInExpr.patternGuard = None
    forInExpr.body = None
    forInExpr.forInKind = ForInKind.FORIN_ITER
}

private func DesugarForInIterExpr(typeManager: TypeManager, forInExpr: ForInExpr, context: Option<ASTContext>,
    synthesizer: Option<(ASTContext, SynPos, Node) -> Ty>): Unit {
    if (let Some(iterator) <- CreateIteratorVar(forInExpr, context, synthesizer)) {
        if (let Some(nextCall) <- CreateIteratorNextCall(forInExpr, iterator, context, synthesizer)) {
            if (let Some(selectorTy) <- nextCall.GetTy()) {
                if (let Some(enumTy) <- (selectorTy as EnumTy)) {
                    let whileExpr = WhileExpr()
                    whileExpr.sugarKind = SugarKind.FOR_IN_EXPR
                    whileExpr.EnableAttr(Attribute.IMPLICIT_ADD)
                    CopyBasicInfo(forInExpr, whileExpr)
                    if (let Some(body) <- forInExpr.body) {
                        whileExpr.begin = body.begin
                        whileExpr.end = body.end
                    }
                    let cond = CreateLitConstExpr(LitConstKind.BOOL, "true", BoolTy())
                    if (let Some(inExpr) <- forInExpr.inExpression) {
                        cond.begin = inExpr.begin
                        cond.end = inExpr.end
                    }
                    whileExpr.condExpr = cond

                    let matchCases = ArrayList<MatchCase>()
                    if (let Some(noneCase) <- CreateNoneCaseForIter(enumTy, whileExpr)) {
                        if (let Some(someCase) <- CreateSomeCaseForIter(typeManager, enumTy, forInExpr,
                            whileExpr)) {
                            noneCase.SetCtxExprForPatterns(nextCall)
                            someCase.SetCtxExprForPatterns(nextCall)
                            matchCases.add(noneCase)
                            matchCases.add(someCase)
                            let matchTy = if (let Some(body) <- forInExpr.body) {
                                body.GetTy() ?? UnitTy()
                            } else {
                                UnitTy()
                            }
                            let matchExpr = CreateMatchExpr(nextCall, matchCases, matchTy)
                            CopyBasicInfo(forInExpr, matchExpr)
                            AddCurFile(matchExpr, file: forInExpr.curFile)
                            let whileNodes = ArrayList<Node>()
                            whileNodes.add(matchExpr)
                            let whileBody = CreateBlock(whileNodes, UnitTy())
                            CopyBasicInfo(forInExpr, whileBody)
                            whileExpr.body = whileBody
                            whileExpr.SetTy(UnitTy())
                            FinishIterDesugar(forInExpr, iterator, whileExpr)
                        }
                    }
                }
            }
        }
    }
}

private func DesugarForInStringExpr(typeManager: TypeManager, forInExpr: ForInExpr): Unit {
    let index = CreateStringIndexVar(forInExpr)
    if (let Some(tmp) <- CreateStringTmpVar(forInExpr)) {
        if (let Some(end) <- CreateStringEndVar(typeManager, forInExpr, tmp)) {
            let condition = CreateStringCond(forInExpr, index, end)
            let guardExpr = CreateGuard(forInExpr, condition, false)
            let whileExpr = WhileExpr()
            whileExpr.sugarKind = SugarKind.FOR_IN_EXPR
            CopyBasicInfo(forInExpr, whileExpr)
            whileExpr.condExpr = condition
            let bodyNodes = ArrayList<Node>()
            if (let Some(letValue) <- CreateStringLetIter(typeManager, forInExpr, tmp, index)) {
                bodyNodes.add(letValue)
            }
            // CreateStringUpdate already assigns the Unit type to this compound assignment.
            let update = CreateStringUpdate(forInExpr, index)
            bodyNodes.add(update)
            bodyNodes.add(guardExpr)
            let whileBody = CreateBlock(bodyNodes, UnitTy())
            CopyBasicInfo(forInExpr, whileBody)
            whileExpr.body = whileBody
            whileExpr.SetTy(UnitTy())
            FinishStringDesugar(forInExpr, index, tmp, end, whileExpr)
        }
    }
}

public func DesugarForInRangeExpr(forInExpr: ForInExpr): Unit {
    if (let Some(_) <- forInExpr.desugarExpr) {
        return
    }
    if (let Some(inExpr) <- forInExpr.inExpression) {
        if (let Some(rangeExpr) <- (inExpr as RangeExpr)) {
            if (!IsStepOne(rangeExpr)) {
                return
            }
            ReArrangeForInRangeExpr(forInExpr, rangeExpr, None, None)
        }
    }
}

public func ReArrangeForInExpr(typeManager: TypeManager, forInExpr: ForInExpr,
    context!: Option<ASTContext> = None,
    synthesizer!: Option<(ASTContext, SynPos, Node) -> Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Unit {
    if (!Ty.IsTyCorrect(forInExpr.GetTy()) ||
        (if (let Some(diagEngine) <- diag) { diagEngine.GetErrorCount() != 0u64 } else { false })) {
        return
    }
    if (let Some(_) <- forInExpr.desugarExpr) {
        return
    }
    if (IsClosedRangeOne(forInExpr)) {
        return
    }
    if (let Some(inExpr) <- forInExpr.inExpression) {
        if (let Some(inTy) <- inExpr.GetTy()) {
            if (inTy.IsRange() && !inTy.typeArgs.isEmpty() && inTy.typeArgs[0].IsInteger()) {
                if (let Some(rangeExpr) <- (inExpr as RangeExpr)) {
                    if (IsStepOne(rangeExpr)) {
                        ReArrangeForInRangeExpr(forInExpr, rangeExpr, context, synthesizer)
                        return
                    }
                }
            }
            if (inTy.IsString()) {
                ReArrangeForInStringExpr(typeManager, forInExpr, context, synthesizer)
            } else {
                DesugarForInExpr(typeManager, forInExpr, context: context, synthesizer: synthesizer, diag: diag)
            }
        }
    }
}

public func DesugarForInExpr(typeManager: TypeManager, forInExpr: ForInExpr,
    context!: Option<ASTContext> = None,
    synthesizer!: Option<(ASTContext, SynPos, Node) -> Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Unit {
    if (!Ty.IsTyCorrect(forInExpr.GetTy()) ||
        (if (let Some(diagEngine) <- diag) { diagEngine.GetErrorCount() != 0u64 } else { false })) {
        return
    }
    if (let Some(_) <- forInExpr.desugarExpr) {
        return
    }
    if (let Some(inExpr) <- forInExpr.inExpression) {
        if (let Some(inTy) <- inExpr.GetTy()) {
            if (inTy.IsRange() && !inTy.typeArgs.isEmpty() && inTy.typeArgs[0].IsInteger()) {
                if (let Some(_) <- (inExpr as RangeExpr)) {
                    DesugarForInRangeExpr(forInExpr)
                    match (forInExpr.forInKind) {
                        case ForInKind.FORIN_RANGE => return
                        case _ => ()
                    }
                    if (let Some(_) <- forInExpr.desugarExpr) {
                        return
                    }
                }
            }
            if (inTy.IsString()) {
                DesugarForInStringExpr(typeManager, forInExpr)
            } else {
                DesugarForInIterExpr(typeManager, forInExpr, context, synthesizer)
            }
        }
    }
}
