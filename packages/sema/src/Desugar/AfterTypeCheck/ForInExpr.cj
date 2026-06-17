package cangjie_compiler::sema.Desugar.AfterTypeCheck

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let INDEX_COMPILER: String = "$index-compiler"
private let IS_FIRST_COMPILER: String = "$isFirst-compiler"
private let STOP_COMPILER: String = "$stop-compiler"
private let ITER_COMPILER: String = "iter-compiler"
private let STRING_SIZE_NAME: String = "size"
private let SUBSCRIPT_OPERATOR_NAME: String = "[]"

private func CloneExpr(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

// After type-checking, desugar-created calls have a fully resolved callee, so the
// result type is simply the callee's function return type. Reading it directly
// avoids re-running expression synthesis (which would couple this after-typecheck
// package to TypeCheckExpr and form a sema subpackage dependency cycle).
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

private func CreateVarRef(decl: VarDecl, pos: Node): RefExpr {
    let refExpr = CreateRefExpr(decl, pos)
    if (let Some(ty) <- decl.GetTy()) {
        refExpr.SetTy(ty)
    }
    refExpr.curFile = decl.curFile
    return refExpr
}

private func CreateIndexVar(forInExpr: ForInExpr, rangeExpr: RangeExpr): Option<VarDecl> {
    if (let Some(startExpr) <- rangeExpr.startExpr) {
        if (let Some(initializer) <- CloneExpr(startExpr)) {
            var indexName = INDEX_COMPILER
            if (let Some(pattern) <- forInExpr.pattern) {
                if (let Some(varPattern) <- (pattern as VarPattern)) {
                    if (let Some(varDecl) <- varPattern.varDecl) {
                        indexName = "$iter-" + varDecl.identifier.Val()
                    }
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
    index.SetTy(litZero.GetTy() ?? TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64))
    CopyBasicInfo(forInExpr, index)
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
    index: VarDecl): Option<CallExpr> {
    let base = CreateMemberAccess(CreateVarRef(tmp, forInExpr), SUBSCRIPT_OPERATOR_NAME)
    base.SetTy(Ty.GetInitialTy())
    base.curFile = forInExpr.curFile
    CopyBasicInfo(forInExpr, base)
    let tmpTy = tmp.GetTy()
    let subscriptTargets = FieldLookup(typeManager, Ty.GetDeclPtrOfTy(tmpTy), SUBSCRIPT_OPERATOR_NAME,
        info: LookupInfo(baseTy: tmpTy, file: forInExpr.curFile))
    for (target in subscriptTargets) {
        base.targets.add(target)
    }
    if (!subscriptTargets.isEmpty()) {
        let firstTarget = subscriptTargets[0]
        base.target = firstTarget
        if (let Some(targetTy) <- firstTarget.GetTy()) {
            base.SetTy(targetTy)
        }
    }
    let args = ArrayList<FuncArg>()
    let indexRef = CreateVarRef(index, forInExpr)
    CopyBasicInfo(forInExpr, indexRef)
    args.add(CreateFuncArg(indexRef))
    let call = CreateCallExpr(base, args)
    CopyBasicInfo(forInExpr, call)
    AddCurFile(call, file: forInExpr.curFile)
    if (!subscriptTargets.isEmpty()) {
        if (let Some(retTy) <- FuncRetTyOf(subscriptTargets[0])) {
            call.SetTy(retTy)
            return call
        }
    }
    return None
}

private func CreateStringLetIter(typeManager: TypeManager, forInExpr: ForInExpr, tmp: VarDecl,
    index: VarDecl): Option<VarDecl> {
    if (let Some(pattern) <- forInExpr.pattern) {
        if (let Some(varPattern) <- (pattern as VarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                if (let Some(elemCall) <- CreateStringElementCall(typeManager, forInExpr, tmp, index)) {
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

private func CreateFirstFlag(rangeExpr: RangeExpr): VarDecl {
    let flag = CreateVarDecl(IS_FIRST_COMPILER, CreateLitConstExpr(LitConstKind.BOOL, "true", BoolTy()), None)
    flag.isVar = true
    flag.begin = rangeExpr.begin
    flag.end = rangeExpr.end
    flag.curFile = rangeExpr.curFile
    flag.SetTy(BoolTy())
    return flag
}

private func RangeIsIncreasing(rangeExpr: RangeExpr): Bool {
    if (let Some(stepExpr) <- rangeExpr.stepExpr) {
        return !stepExpr.constNumValue.asInt.IsNegativeNum()
    }
    return true
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
        if (let Some(clonedStep) <- CloneExpr(stepExpr)) {
            update.rightExpr = clonedStep
        } else {
            return None
        }
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

private func CreateLetIter(forInExpr: ForInExpr, index: VarDecl): Option<VarDecl> {
    if (let Some(pattern) <- forInExpr.pattern) {
        if (let Some(varPattern) <- (pattern as VarPattern)) {
            if (let Some(varDecl) <- varPattern.varDecl) {
                varDecl.parentPattern = None
                varDecl.initializer = CreateVarRef(index, varDecl)
                varDecl.curFile = forInExpr.curFile
                forInExpr.patternInDesugarExpr = pattern
                forInExpr.pattern = None
                return varDecl
            }
        }
    }
    return None
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

private func CreateFirstIf(forInExpr: ForInExpr, firstFlag: VarDecl, update: AssignExpr): IfExpr {
    let firstRun = IfExpr()
    firstRun.hasElse = true
    firstRun.curFile = forInExpr.curFile
    if (let Some(inExpr) <- forInExpr.inExpression) {
        firstRun.condExpr = CreateVarRef(firstFlag, inExpr)
    } else {
        firstRun.condExpr = CreateVarRef(firstFlag, firstFlag)
    }
    firstRun.begin = forInExpr.inPos
    firstRun.end = forInExpr.inPos + 2
    let thenNodes = ArrayList<Node>()
    let assignFalse = AssignExpr()
    assignFalse.op = TokenKind.ASSIGN
    assignFalse.curFile = forInExpr.curFile
    assignFalse.leftValue = CreateVarRef(firstFlag, firstFlag)
    assignFalse.rightExpr = CreateLitConstExpr(LitConstKind.BOOL, "false", BoolTy())
    assignFalse.SetTy(UnitTy())
    assignFalse.begin = firstRun.begin
    assignFalse.end = firstRun.end
    assignFalse.EnableAttr(Attribute.COMPILER_ADD)
    thenNodes.add(assignFalse)
    let thenBody = CreateBlock(thenNodes, UnitTy())
    if (let Some(body) <- forInExpr.body) {
        thenBody.begin = body.begin
        thenBody.end = body.end
    }
    let elseNodes = ArrayList<Node>()
    elseNodes.add(update)
    let elseBody = CreateBlock(elseNodes, UnitTy())
    if (let Some(loopBody) <- forInExpr.body) {
        elseBody.begin = loopBody.begin
        elseBody.end = loopBody.end
    }
    firstRun.thenBody = thenBody
    firstRun.elseBody = elseBody
    firstRun.SetTy(UnitTy())
    return firstRun
}

private func FinishRangeDesugar(forInExpr: ForInExpr, index: VarDecl, stop: VarDecl, firstFlag: Option<VarDecl>,
    whileExpr: WhileExpr): Unit {
    let nodes = ArrayList<Node>()
    nodes.add(index)
    nodes.add(stop)
    if (let Some(flag) <- firstFlag) {
        nodes.add(flag)
    }
    nodes.add(whileExpr)
    let block = CreateBlock(nodes, UnitTy())
    CopyBasicInfo(forInExpr, block)
    AddCurFile(block, file: forInExpr.curFile)
    if (let Some(whileBody) <- whileExpr.body) {
        RearrangeRefLoop(forInExpr, whileExpr, whileBody)
    }
    forInExpr.desugarExpr = block
    forInExpr.inExpression = None
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
}

private func DesugarClosedRange(forInExpr: ForInExpr, rangeExpr: RangeExpr): Unit {
    if (let Some(index) <- CreateIndexVar(forInExpr, rangeExpr)) {
        if (let Some(stop) <- CreateStopVar(rangeExpr)) {
            if (let Some(update) <- CreateUpdate(forInExpr, rangeExpr, index)) {
                let firstFlag = CreateFirstFlag(rangeExpr)
                let increasing = RangeIsIncreasing(rangeExpr)
                let whileExpr = WhileExpr()
                whileExpr.sugarKind = SugarKind.FOR_IN_EXPR
                CopyBasicInfo(forInExpr, whileExpr)
                let nonClosedOp = if (increasing) { TokenKind.LT } else { TokenKind.GT }
                let rangeCondExpr = CreateRangeCond(forInExpr, index, stop, nonClosedOp)
                let firstFlagRef = CreateVarRef(firstFlag, stop)
                let whileCond = CreateBinaryExpr(rangeCondExpr, firstFlagRef, TokenKind.OR)
                whileCond.SetTy(BoolTy())
                CopyBasicInfo(forInExpr, whileCond)
                whileExpr.condExpr = whileCond
                let bodyNodes = ArrayList<Node>()
                bodyNodes.add(CreateFirstIf(forInExpr, firstFlag, update))
                if (let Some(letValue) <- CreateLetIter(forInExpr, index)) {
                    bodyNodes.add(letValue)
                }
                let closedOp = if (increasing) { TokenKind.LE } else { TokenKind.GE }
                bodyNodes.add(CreateGuard(forInExpr, CreateRangeCond(forInExpr, index, stop, closedOp), true))
                let whileBody = CreateBlock(bodyNodes, UnitTy())
                CopyBasicInfo(forInExpr, whileBody)
                whileExpr.body = whileBody
                whileExpr.SetTy(UnitTy())
                FinishRangeDesugar(forInExpr, index, stop, firstFlag, whileExpr)
            }
        }
    }
}

private func DesugarNonClosedRange(forInExpr: ForInExpr, rangeExpr: RangeExpr): Unit {
    if (let Some(index) <- CreateIndexVar(forInExpr, rangeExpr)) {
        if (let Some(stop) <- CreateStopVar(rangeExpr)) {
            if (let Some(update) <- CreateUpdate(forInExpr, rangeExpr, index)) {
                let increasing = RangeIsIncreasing(rangeExpr)
                let op = if (increasing) { TokenKind.LT } else { TokenKind.GT }
                let rangeCond = CreateRangeCond(forInExpr, index, stop, op)
                let guardExpr = CreateGuard(forInExpr, rangeCond, false)
                let whileExpr = WhileExpr()
                whileExpr.sugarKind = SugarKind.FOR_IN_EXPR
                CopyBasicInfo(forInExpr, whileExpr)
                whileExpr.condExpr = rangeCond
                let bodyNodes = ArrayList<Node>()
                if (let Some(letValue) <- CreateLetIter(forInExpr, index)) {
                    bodyNodes.add(letValue)
                }
                bodyNodes.add(update)
                bodyNodes.add(guardExpr)
                let whileBody = CreateBlock(bodyNodes, UnitTy())
                CopyBasicInfo(forInExpr, whileBody)
                whileExpr.body = whileBody
                whileExpr.SetTy(UnitTy())
                FinishRangeDesugar(forInExpr, index, stop, None, whileExpr)
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
            if (rangeExpr.isClosed) {
                DesugarClosedRange(forInExpr, rangeExpr)
            } else {
                DesugarNonClosedRange(forInExpr, rangeExpr)
            }
        }
    }
}

public func DesugarForInExpr(typeManager: TypeManager, forInExpr: ForInExpr): Unit {
    if (!Ty.IsTyCorrect(forInExpr.GetTy())) {
        return
    }
    if (let Some(_) <- forInExpr.desugarExpr) {
        return
    }
    if (let Some(inExpr) <- forInExpr.inExpression) {
        if (let Some(_) <- (inExpr as RangeExpr)) {
            DesugarForInRangeExpr(forInExpr)
            return
        }
        if (let Some(inTy) <- inExpr.GetTy()) {
            if (inTy.IsString()) {
                DesugarForInStringExpr(typeManager, forInExpr)
            }
        }
    }
}

public func SelfhostPortStatus_Desugar_AfterTypeCheck_ForInExpr(): Bool {
    return true
}
