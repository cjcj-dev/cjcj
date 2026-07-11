package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*
import cjcj::sema.Desugar.*
import cjcj::utils.CORE_PACKAGE_NAME as UTILS_CORE_PACKAGE_NAME
import cjcj::utils.STD_LIB_OPTION

public type BinaryOperandSynthesizer = (Expr) -> Ty
public type BinaryOperandChecker = (Ty, Expr) -> Bool

private func IsArithmeticOperator(op: TokenKind): Bool {
    return op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL ||
        op == TokenKind.DIV || op == TokenKind.EXP || op == TokenKind.MOD ||
        op == TokenKind.BITAND || op == TokenKind.BITOR || op == TokenKind.BITXOR
}

private func IsRelationalOperator(op: TokenKind): Bool {
    return op == TokenKind.EQUAL || op == TokenKind.NOTEQ || op == TokenKind.GT ||
        op == TokenKind.LT || op == TokenKind.GE || op == TokenKind.LE
}

private func IsLogicalOperator(op: TokenKind): Bool {
    return op == TokenKind.AND || op == TokenKind.OR
}

private func IsShiftOperator(op: TokenKind): Bool {
    return op == TokenKind.LSHIFT || op == TokenKind.RSHIFT
}

private func BinaryInvalid(be: BinaryExpr): Ty {
    return TcInvalid(be)
}

private class TargetSnapshot {
    let node: Node
    let target: Option<Decl>
    let targets: ArrayList<Decl> = ArrayList<Decl>()

    init(node: Node) {
        this.node = node
        this.target = node.GetTarget()
        for (value in node.GetTargets()) {
            targets.add(value)
        }
    }

    func Restore(): Unit {
        node.SetTarget(target)
        if (let Some(refExpr) <- (node as RefExpr)) {
            refExpr.ref.targets.clear()
            for (value in targets) {
                refExpr.ref.targets.add(value)
            }
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            memberAccess.targets.clear()
            for (value2 in targets) {
                memberAccess.targets.add(value2)
            }
        } else if (let Some(refType) <- (node as RefType)) {
            refType.ref.targets.clear()
            for (value3 in targets) {
                refType.ref.targets.add(value3)
            }
        }
    }
}

private func CollectTargetSnapshots(node: Node): ArrayList<TargetSnapshot> {
    let snapshots = ArrayList<TargetSnapshot>()
    let walker = Walker(node, visitPre: { current: Node =>
        if ((let Some(_) <- current.GetTarget()) || !current.GetTargets().isEmpty()) {
            snapshots.add(TargetSnapshot(current))
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return snapshots
}

private func ClearExprKeepTargets(expr: Expr): Unit {
    let snapshots = CollectTargetSnapshots(expr)
    expr.Clear()
    for (snapshot in snapshots) {
        snapshot.Restore()
    }
}

private func GetChildBinaryExpr(child: Expr): Option<BinaryExpr> {
    if (let Some(binary) <- (child as BinaryExpr)) {
        if (let None <- binary.desugarExpr) {
            return Some(binary)
        }
    }
    if (let Some(parenExpr) <- (child as ParenExpr)) {
        if (let Some(innerExpr) <- parenExpr.expr) {
            if (let Some(innerBinary) <- (innerExpr as BinaryExpr)) {
                if (let None <- innerBinary.desugarExpr) {
                    return Some(innerBinary)
                }
            }
        }
    }
    return None
}

private func HasInvalidChild(be: BinaryExpr): Bool {
    let stack = ArrayList<Node>()
    stack.add(be)
    while (!stack.isEmpty()) {
        let current = stack[stack.size - 1]
        stack.remove(at: stack.size - 1)
        if (let Some(expr) <- (current as Expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                stack.add(desugar)
                continue
            }
        }
        if (current.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN)) {
            return true
        }
        if (let Some(expr2) <- (current as Expr)) {
            if (expr2.IsReferenceExpr() && !Ty.IsInitialTy(expr2.GetTy())) {
                if ((let None <- expr2.GetTarget()) && !Ty.IsTyCorrect(expr2.GetTy())) {
                    return true
                }
                continue
            }
        }
        let children = current.Children()
        var idx = children.size
        while (idx > 0) {
            idx--
            stack.add(children[idx])
        }
    }
    return false
}

private func MarkOutermostBinaryExpr(setOutermost: Bool, node: Node): Unit {
    let shouldMark = Box<Bool>(setOutermost)
    let walker = Walker(node, visitPre: { current: Node =>
        if (let Some(binary) <- (current as BinaryExpr)) {
            if (shouldMark.value) {
                binary.EnableAttr(Attribute.IS_OUTERMOST)
            }
            if (let Some(leftExpr) <- binary.leftExpr) {
                MarkOutermostBinaryExpr(false, leftExpr)
            }
            if (let Some(rightExpr) <- binary.rightExpr) {
                MarkOutermostBinaryExpr(false, rightExpr)
            }
            shouldMark.value = true
            return VisitAction.SKIP_CHILDREN
        } else if (let Some(parenExpr) <- (current as ParenExpr)) {
            if (let Some(innerExpr) <- parenExpr.expr) {
                MarkOutermostBinaryExpr(shouldMark.value, innerExpr)
            }
            return VisitAction.SKIP_CHILDREN
        } else {
            shouldMark.value = true
        }
        return VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public func MarkOutermostBinaryExpressions(pkg: Package): Unit {
    MarkOutermostBinaryExpr(true, pkg)
}

private func SynBinaryLeafs(typeManager: TypeManager, be: BinaryExpr,
    synthesizer: Option<BinaryOperandSynthesizer>): Unit {
    let stack = ArrayList<Node>()
    stack.add(be)
    while (!stack.isEmpty()) {
        let current = stack[stack.size - 1]
        stack.remove(at: stack.size - 1)
        if (let Some(expr) <- (current as Expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                stack.add(desugar)
                continue
            }
        }
        if (current.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN) || (let Some(_) <- (current as Pattern))) {
            continue
        }
        var skipChildren = false
        if (let Some(callExpr) <- (current as CallExpr)) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                SetIsNotAlone(baseFunc)
                if (let Some(nameRef) <- (baseFunc as NameReferenceExpr)) {
                    nameRef.callOrPattern = Some(callExpr)
                }
            }
        } else if (let Some(memberAccess) <- (current as MemberAccess)) {
            if (!IsFieldOperator(memberAccess.field.Val())) {
                let _ = SynBinaryOperand(typeManager, memberAccess, synthesizer)
                skipChildren = true
            }
        } else if (let Some(refExpr) <- (current as RefExpr)) {
            let _ = SynBinaryOperand(typeManager, refExpr, synthesizer)
        }
        if (!skipChildren) {
            let children = current.Children()
            var idx = children.size
            while (idx > 0) {
                idx--
                stack.add(children[idx])
            }
        }
    }
}

private func DiagnoseForBinaryExpr(typeManager: TypeManager, be: BinaryExpr,
    synthesizer: Option<BinaryOperandSynthesizer>, diag: Option<BasicDiagnosticEngine>): Unit {
    let pivotStack = ArrayList<BinaryExpr>()
    pivotStack.add(be)
    while (true) {
        let pivot = pivotStack[pivotStack.size - 1]
        if (Ty.IsTyCorrect(pivot.GetTy()) || !pivot.ShouldDiagnose(allowCompilerAdd: true)) {
            return
        }
        if ((let None <- pivot.leftExpr) || (let None <- pivot.rightExpr)) {
            return
        }
        let leftExpr = pivot.leftExpr.getOrThrow()
        let rightExpr = pivot.rightExpr.getOrThrow()
        if (Ty.IsInitialTy(leftExpr.GetTy())) {
            try (ds = DiagSuppressor(diag)) {
                let _ = SynBinaryOperand(typeManager, leftExpr, synthesizer)
            }
        }
        if (!Ty.IsTyCorrect(leftExpr.GetTy())) {
            if (let Some(newPivot) <- GetChildBinaryExpr(leftExpr)) {
                pivotStack.add(newPivot)
                continue
            }
            if (!Ty.IsTyCorrect(SynBinaryOperand(typeManager, leftExpr, synthesizer))) {
                let _ = SynBinaryOperand(typeManager, rightExpr, synthesizer)
                return
            }
        }
        if (Ty.IsInitialTy(rightExpr.GetTy())) {
            try (ds2 = DiagSuppressor(diag)) {
                let _ = SynBinaryOperand(typeManager, rightExpr, synthesizer)
            }
        }
        if (!Ty.IsTyCorrect(rightExpr.GetTy())) {
            if (let Some(newPivot2) <- GetChildBinaryExpr(rightExpr)) {
                pivotStack.add(newPivot2)
                continue
            }
            if (!Ty.IsTyCorrect(SynBinaryOperand(typeManager, rightExpr, synthesizer))) {
                return
            }
        }
        break
    }
    while (pivotStack.size > 1) {
        let pivot = pivotStack[pivotStack.size - 1]
        pivotStack.remove(at: pivotStack.size - 1)
        if (!Ty.IsTyCorrect(SynBinaryOperand(typeManager, pivot, synthesizer))) {
            return
        }
    }
    let finalPivot = pivotStack[pivotStack.size - 1]
    if ((let None <- finalPivot.leftExpr) || (let None <- finalPivot.rightExpr)) {
        return
    }
    let finalLeft = finalPivot.leftExpr.getOrThrow()
    let finalRight = finalPivot.rightExpr.getOrThrow()
    let _ = SynBinaryOperand(typeManager, finalLeft, synthesizer)
    let _ = SynBinaryOperand(typeManager, finalRight, synthesizer)
    if (ReplaceIdealTy(typeManager, finalLeft, diag: diag) && ReplaceIdealTy(typeManager, finalRight, diag: diag)) {
        if (let Some(diagValue) <- diag) {
            DiagInvalidBinaryExpr(diagValue, finalPivot)
        }
    }
}

private func SynBinaryOperand(typeManager: TypeManager, expr: Expr,
    synthesizer: Option<BinaryOperandSynthesizer>): Ty {
    if (let Some(syn) <- synthesizer) {
        return syn(expr)
    }
    return SynExprShallow(typeManager, expr)
}

private func ChkBinaryOperand(typeManager: TypeManager, target: Ty, expr: Expr,
    ctx: Option<ASTContext>, checker: Option<BinaryOperandChecker>): Bool {
    if (let Some(chk) <- checker) {
        return chk(target, expr)
    }
    return ChkExprShallow(typeManager, target, expr, ctx: ctx)
}

private func PropagateBinaryDesugarTarget(be: BinaryExpr, desugar: Expr): Unit {
    if (let Some(callExpr) <- (desugar as CallExpr)) {
        if (let Some(resolved) <- callExpr.resolvedFunction) {
            ReplaceTarget(be, Some(resolved))
        }
    }
}

private func HasTupleEqualityOperands(be: BinaryExpr): Bool {
    if (be.op != TokenKind.EQUAL && be.op != TokenKind.NOTEQ) {
        return false
    }
    if (let Some(leftExpr) <- be.leftExpr) {
        if (let Some(rightExpr) <- be.rightExpr) {
            if (let Some(leftTy) <- leftExpr.GetTy()) {
                if (let Some(rightTy) <- rightExpr.GetTy()) {
                    return leftTy.IsTuple() && rightTy.IsTuple()
                }
            }
        }
    }
    return false
}

private func ShouldTryBinaryOverload(be: BinaryExpr): Bool {
    return IsOverloadableOperator(be.op) && !HasTupleEqualityOperands(be)
}

private func TrySynBinaryOverload(typeManager: TypeManager, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None): Option<Ty> {
    let _ = checker
    if (!ShouldTryBinaryOverload(be)) {
        return None
    }
    DesugarOperatorOverloadExpr(be, ctx: ctx)
    if (let Some(desugar) <- be.desugarExpr) {
        let desugarTy = SynBinaryOperand(typeManager, desugar, synthesizer)
        if (Ty.IsTyCorrect(desugarTy)) {
            PropagateBinaryDesugarTarget(be, desugar)
            be.SetTy(desugarTy)
            return Some(desugarTy)
        }
        RecoverToBinaryExpr(be)
    }
    be.SetTy(TypeManager.GetInvalidTy())
    return None
}

private func TryChkBinaryOverload(typeManager: TypeManager, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None): Bool {
    let _ = synthesizer
    if (!ShouldTryBinaryOverload(be)) {
        return false
    }
    DesugarOperatorOverloadExpr(be, ctx: ctx)
    if (let Some(desugar) <- be.desugarExpr) {
        if (ChkBinaryOperand(typeManager, target, desugar, ctx, checker)) {
            PropagateBinaryDesugarTarget(be, desugar)
            be.SetTy(TcTyOrInvalid(desugar))
            return true
        }
        RecoverToBinaryExpr(be)
    }
    return false
}

private func IsFlowOperator(op: TokenKind): Bool {
    return op == TokenKind.PIPELINE || op == TokenKind.COMPOSITION
}

private func IsAloneThisOrSuperExpr(expr: Expr): Bool {
    if (let Some(refExpr) <- (expr as RefExpr)) {
        return refExpr.isAlone && (refExpr.isThis || refExpr.isSuper)
    }
    return false
}

private func FlowOperandsValid(be: BinaryExpr): Bool {
    if (let Some(rightExpr) <- be.rightExpr) {
        if (IsAloneThisOrSuperExpr(rightExpr)) {
            return false
        }
    } else {
        return false
    }
    if (be.op == TokenKind.COMPOSITION) {
        if (let Some(leftExpr) <- be.leftExpr) {
            if (IsAloneThisOrSuperExpr(leftExpr)) {
                return false
            }
        } else {
            return false
        }
    }
    return true
}

private func PrepareFlowOperands(typeManager: TypeManager, be: BinaryExpr): Bool {
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        return false
    }
    let leftValue = be.leftExpr.getOrThrow()
    let rightValue = be.rightExpr.getOrThrow()
    rightValue.isInFlowExpr = true
    let leftTy = SynExprShallow(typeManager, leftValue)
    let rightTy = SynExprShallow(typeManager, rightValue)
    if (!Ty.IsTyCorrect(leftTy) || !Ty.IsTyCorrect(rightTy)) {
        if (be.op == TokenKind.COMPOSITION) {
            let _ = BinaryInvalid(be)
            return false
        }
        ClearExprKeepTargets(leftValue)
        ClearExprKeepTargets(rightValue)
    }
    return FlowOperandsValid(be)
}

private func FuncDeclHasNamedParam(fd: FuncDecl): Bool {
    if (let Some(body) <- fd.funcBody) {
        if (!body.paramLists.isEmpty()) {
            for (param in body.paramLists[0].params) {
                if (param.isNamedParam) {
                    return true
                }
            }
        }
    }
    return false
}

private func RefExprTargetIsFuncDeclAndHasNamedParam(re: RefExpr): Bool {
    if (let Some(target) <- re.ref.target) {
        if (let Some(funcDecl) <- (target as FuncDecl)) {
            return FuncDeclHasNamedParam(funcDecl)
        }
    }
    return false
}

private func FlowOperandsHaveNamedParam(callExpr: CallExpr): Bool {
    for (arg in callExpr.args) {
        if (let Some(argExpr) <- arg.expr) {
            if (let Some(refExpr) <- (argExpr as RefExpr)) {
                if (RefExprTargetIsFuncDeclAndHasNamedParam(refExpr)) {
                    return true
                }
            }
        }
    }
    return false
}

private func TrySynFlowDesugar(typeManager: TypeManager, be: BinaryExpr): (Bool, Ty) {
    if (!PrepareFlowOperands(typeManager, be)) {
        return (true, TypeManager.GetInvalidTy())
    }
    DesugarInTypeCheck(be)
    if (let Some(desugar) <- be.desugarExpr) {
        let desugarTy = SynExprShallow(typeManager, desugar)
        if (Ty.IsTyCorrect(desugarTy)) {
            if (let Some(callExpr) <- (desugar as CallExpr)) {
                if (FlowOperandsHaveNamedParam(callExpr)) {
                    RecoverToBinaryExpr(be)
                    return (true, BinaryInvalid(be))
                }
            }
            PropagateBinaryDesugarTarget(be, desugar)
            be.SetTy(desugarTy)
            return (true, desugarTy)
        }
        RecoverToBinaryExpr(be)
    }
    return (false, TypeManager.GetInvalidTy())
}

private func TryChkFlowDesugar(typeManager: TypeManager, target: Ty, be: BinaryExpr): (Bool, Bool) {
    if (!PrepareFlowOperands(typeManager, be)) {
        return (true, false)
    }
    DesugarInTypeCheck(be)
    if (let Some(desugar) <- be.desugarExpr) {
        if (ChkExprShallow(typeManager, target, desugar)) {
            if (let Some(callExpr) <- (desugar as CallExpr)) {
                if (FlowOperandsHaveNamedParam(callExpr)) {
                    RecoverToBinaryExpr(be)
                    let _ = BinaryInvalid(be)
                    return (true, false)
                }
            }
            PropagateBinaryDesugarTarget(be, desugar)
            be.SetTy(TcTyOrInvalid(desugar))
            return (true, true)
        }
        RecoverToBinaryExpr(be)
    }
    return (false, false)
}

private func IsArithmeticIntegerKind(kind: TypeKind): Bool {
    return kind == TypeKind.TYPE_INT8 || kind == TypeKind.TYPE_INT16 || kind == TypeKind.TYPE_INT32 ||
        kind == TypeKind.TYPE_INT64 || kind == TypeKind.TYPE_INT_NATIVE || kind == TypeKind.TYPE_UINT8 ||
        kind == TypeKind.TYPE_UINT16 || kind == TypeKind.TYPE_UINT32 || kind == TypeKind.TYPE_UINT64 ||
        kind == TypeKind.TYPE_UINT_NATIVE || kind == TypeKind.TYPE_IDEAL_INT
}

private func IsArithmeticNumericKind(kind: TypeKind): Bool {
    return IsArithmeticIntegerKind(kind) || kind == TypeKind.TYPE_FLOAT16 || kind == TypeKind.TYPE_FLOAT32 ||
        kind == TypeKind.TYPE_FLOAT64 || kind == TypeKind.TYPE_IDEAL_FLOAT
}

private func IsRelationNumericKind(kind: TypeKind): Bool {
    return IsArithmeticNumericKind(kind) || kind == TypeKind.TYPE_RUNE
}

private func IsBinaryCandidateKind(op: TokenKind, kind: TypeKind): Bool {
    if (op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL || op == TokenKind.DIV) {
        return IsArithmeticNumericKind(kind)
    }
    if (op == TokenKind.MOD || op == TokenKind.BITAND || op == TokenKind.BITOR || op == TokenKind.BITXOR ||
        op == TokenKind.LSHIFT || op == TokenKind.RSHIFT) {
        return IsArithmeticIntegerKind(kind)
    }
    if (op == TokenKind.EQUAL || op == TokenKind.NOTEQ) {
        return IsRelationNumericKind(kind) || kind == TypeKind.TYPE_BOOLEAN || kind == TypeKind.TYPE_UNIT
    }
    if (op == TokenKind.GT || op == TokenKind.LT || op == TokenKind.GE || op == TokenKind.LE) {
        return IsRelationNumericKind(kind)
    }
    return false
}

private func IsBinaryCandidateTy(op: TokenKind, ty: Ty): Bool {
    if (ty.IsNothing() || ty.IsPlaceholder()) {
        return true
    }
    let upper = Ty.GetPrimitiveUpperBound(ty)
    if (upper.IsNothing() || upper.IsPlaceholder()) {
        return true
    }
    return IsBinaryCandidateKind(op, upper.kind)
}

private func AddConcreteIntegerKinds(kinds: ArrayList<TypeKind>): Unit {
    kinds.add(TypeKind.TYPE_INT8)
    kinds.add(TypeKind.TYPE_INT16)
    kinds.add(TypeKind.TYPE_INT32)
    kinds.add(TypeKind.TYPE_INT64)
    kinds.add(TypeKind.TYPE_INT_NATIVE)
    kinds.add(TypeKind.TYPE_UINT8)
    kinds.add(TypeKind.TYPE_UINT16)
    kinds.add(TypeKind.TYPE_UINT32)
    kinds.add(TypeKind.TYPE_UINT64)
    kinds.add(TypeKind.TYPE_UINT_NATIVE)
}

private func AddConcreteNumericKinds(kinds: ArrayList<TypeKind>): Unit {
    AddConcreteIntegerKinds(kinds)
    kinds.add(TypeKind.TYPE_FLOAT16)
    kinds.add(TypeKind.TYPE_FLOAT32)
    kinds.add(TypeKind.TYPE_FLOAT64)
}

private func GetConcreteBinaryCandidateKinds(op: TokenKind): ArrayList<TypeKind> {
    let kinds = ArrayList<TypeKind>()
    if (op == TokenKind.ADD || op == TokenKind.SUB || op == TokenKind.MUL || op == TokenKind.DIV) {
        AddConcreteNumericKinds(kinds)
    } else if (op == TokenKind.MOD || op == TokenKind.BITAND || op == TokenKind.BITOR ||
        op == TokenKind.BITXOR || op == TokenKind.LSHIFT || op == TokenKind.RSHIFT) {
        AddConcreteIntegerKinds(kinds)
    } else if (op == TokenKind.EXP) {
        kinds.add(TypeKind.TYPE_INT64)
        kinds.add(TypeKind.TYPE_FLOAT64)
    }
    return kinds
}

private func BuiltinBinaryResultTy(op: TokenKind, operandTy: Ty, isArithmetic: Bool): Ty {
    if (!isArithmetic || IsRelationalOperator(op)) {
        return TcBoolTy()
    }
    return operandTy
}

private func SynBuiltinBinaryFromRight(typeManager: TypeManager, be: BinaryExpr,
    isArithmetic: Bool, ctx!: Option<ASTContext> = None,
    synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Option<Ty> {
    let _ = isArithmetic
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        be.SetTy(TypeManager.GetInvalidTy())
        return Some(TypeManager.GetInvalidTy())
    }
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    var targetRight: Ty = TypeManager.GetInvalidTy()
    try (ds = DiagSuppressor(diag)) {
        let rightTy = SynBinaryOperand(typeManager, rightExpr, synthesizer)
        if (!Ty.IsTyCorrect(rightTy)) {
            be.SetTy(TypeManager.GetInvalidTy())
            return None
        }
        targetRight = Ty.GetPrimitiveUpperBound(TcReplaceIdeal(typeManager, rightExpr))
    }
    let isWellTyped = Ty.IsTyCorrect(targetRight) &&
        (targetRight.IsNothing() || targetRight.IsPrimitiveSubType() || targetRight.IsTuple() ||
            targetRight.IsPlaceholder())
    if (!isWellTyped) {
        let _ = SynBinaryOperand(typeManager, leftExpr, synthesizer)
        be.SetTy(TypeManager.GetInvalidTy())
        return Some(TypeManager.GetInvalidTy())
    }
    try (ds = DiagSuppressor(diag)) {
        ClearExprKeepTargets(leftExpr)
        if (ChkBinaryOperand(typeManager, targetRight, leftExpr, ctx, checker)) {
            ds.ReportDiag()
            let solvedRight = typeManager.TryGreedySubst(targetRight)
            rightExpr.SetTy(solvedRight)
            be.SetTy(solvedRight)
            return Some(solvedRight)
        }
    }
    be.SetTy(TypeManager.GetInvalidTy())
    return None
}

private func SynBuiltinBinaryFromLeft(typeManager: TypeManager, be: BinaryExpr,
    isArithmetic: Bool, ctx!: Option<ASTContext> = None,
    synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    let _ = isArithmetic
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        return BinaryInvalid(be)
    }
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    let leftTy = SynBinaryOperand(typeManager, leftExpr, synthesizer)
    let targetLeft = TcReplaceIdeal(typeManager, leftExpr)
    let isWellTyped = Ty.IsTyCorrect(leftTy) && Ty.IsTyCorrect(targetLeft) &&
        (targetLeft.IsNothing() || targetLeft.IsPrimitiveSubType() || targetLeft.IsTuple() ||
            targetLeft.IsPlaceholder())
    if (!isWellTyped) {
        let _ = SynBinaryOperand(typeManager, rightExpr, synthesizer)
        return BinaryInvalid(be)
    }
    try (ds = DiagSuppressor(diag)) {
        if (ChkBinaryOperand(typeManager, targetLeft, rightExpr, ctx, checker)) {
            ds.ReportDiag()
            be.SetTy(targetLeft)
            return targetLeft
        }
    }
    return BinaryInvalid(be)
}

private func ChkExpoExprExponent(typeManager: TypeManager, exponent: Expr, exTys: ArrayList<Ty>,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    var isWellTyped = true
    let pass = ArrayList<Bool>()
    try (cs = typeManager.constraints.CommitScope()) {
        for (ty in exTys) {
            try (ds = DiagSuppressor(diag)) {
                pass.add(ChkBinaryOperand(typeManager, ty, exponent, ctx, checker))
            }
        }
        typeManager.constraints.Reset()
    }

    var answers: Int64 = 0
    for (value in pass) {
        if (value) {
            answers++
        }
    }
    if (answers > 1) {
        if (let Some(diagValue) <- diag) {
            diagValue.Diagnose(exponent.begin, BasicDiagKind.sema_ambiguous_expo_right_operand_type).Emit()
        }
        isWellTyped = false
    } else if (answers == 1) {
        var idx: Int64 = 0
        while (!pass[idx]) {
            idx++
        }
        let ty = exTys[idx]
        isWellTyped = ChkBinaryOperand(typeManager, ty, exponent, ctx, checker)
    } else {
        isWellTyped = false
        if (CanSkipDiag(exponent)) {
            let _ = SynBinaryOperand(typeManager, exponent, synthesizer)
        } else {
            var tgtTyStr = ""
            if (exTys.size == 1) {
                tgtTyStr = exTys[0].String()
            } else {
                var idx2: Int64 = 0
                while (idx2 < exTys.size - 1) {
                    tgtTyStr += exTys[idx2].String() + "' or '"
                    idx2++
                }
                tgtTyStr += exTys[exTys.size - 1].String()
            }
            if (let Some(diagValue2) <- diag) {
                DiagMismatchedTypesWithFoundTy(diagValue2, exponent, tgtTyStr,
                    Ty.ToString(exponent.GetTy()), note: "the type of the right operand must be " +
                    tgtTyStr + " in this case")
            }
        }
    }
    return isWellTyped
}

func CheckExponentByBaseTy(impl: TypeCheckerImpl, baseTy: Ty, base: Expr, exponent: Expr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let typeManager = impl.typeManager
    let i64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    let u64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT64)
    let f64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_FLOAT64)
    var isExponentWellTyped = true
    if (baseTy.IsPlaceholder()) {
        let validCombos = ArrayList<(Ty, Ty)>()
        validCombos.add((i64Ty, u64Ty))
        validCombos.add((f64Ty, i64Ty))
        validCombos.add((f64Ty, f64Ty))
        let _ = SynBinaryOperand(typeManager, exponent, synthesizer)
        let _ = TcReplaceIdeal(typeManager, exponent)
        if (!Ty.IsTyCorrect(exponent.GetTy())) {
            isExponentWellTyped = false
        } else {
            match (impl.PickConstaintFromTys(baseTy, exponent.GetTy().getOrThrow(), validCombos, true)) {
                case MatchResult.UNIQUE => ()
                case MatchResult.AMBIGUOUS => isExponentWellTyped = false
                case MatchResult.NONE => isExponentWellTyped = false
            }
        }
    }
    if (isExponentWellTyped && typeManager.IsSubtype(baseTy, i64Ty)) {
        let exponentTys = ArrayList<Ty>()
        exponentTys.add(u64Ty)
        isExponentWellTyped = ChkExpoExprExponent(typeManager, exponent, exponentTys, ctx: ctx,
            synthesizer: synthesizer, checker: checker, diag: diag)
    } else if (isExponentWellTyped && typeManager.IsSubtype(baseTy, f64Ty)) {
        let exponentTys = ArrayList<Ty>()
        exponentTys.add(i64Ty)
        exponentTys.add(f64Ty)
        isExponentWellTyped = ChkExpoExprExponent(typeManager, exponent, exponentTys, ctx: ctx,
            synthesizer: synthesizer, checker: checker, diag: diag)
    } else {
        isExponentWellTyped = false
        if (Ty.IsTyCorrect(baseTy)) {
            if (let Some(diagValue) <- diag) {
                DiagMismatchedTypesWithFoundTy(diagValue, base, "Int64' or 'Float64", baseTy.String(),
                    note: "the type of the left operand of an exponentiation expression must be either 'Int64' or 'Float64'")
            }
        }
        let _ = SynBinaryOperand(typeManager, exponent, synthesizer)
    }
    return isExponentWellTyped
}

private func SynExpoExpr(impl: TypeCheckerImpl, be: BinaryExpr, ctx: Option<ASTContext>,
    synthesizer: Option<BinaryOperandSynthesizer>, checker: Option<BinaryOperandChecker>,
    diag: Option<BasicDiagnosticEngine>): Ty {
    let typeManager = impl.typeManager
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        return BinaryInvalid(be)
    }
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    let _ = SynBinaryOperand(typeManager, leftExpr, synthesizer)
    let _ = TcReplaceIdeal(typeManager, leftExpr)
    let baseTy = leftExpr.GetTy() ?? TypeManager.GetInvalidTy()
    let isExponentWellTyped = CheckExponentByBaseTy(impl, baseTy, leftExpr, rightExpr, ctx: ctx,
        synthesizer: synthesizer, checker: checker, diag: diag)
    if (Ty.IsTyCorrect(leftExpr.GetTy()) && isExponentWellTyped) {
        let resultTy = leftExpr.GetTy().getOrThrow()
        be.SetTy(resultTy)
        return resultTy
    }
    return BinaryInvalid(be)
}

private func SynArithmeticOrRelationalExpr(impl: TypeCheckerImpl, be: BinaryExpr,
    isArithmetic!: Bool = true, ctx!: Option<ASTContext> = None,
    synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    let typeManager = impl.typeManager
    if (isArithmetic && be.op == TokenKind.EXP) {
        return SynExpoExpr(impl, be, ctx, synthesizer, checker, diag)
    }
    var ty = if (let Some(resultTy) <- SynBuiltinBinaryFromRight(typeManager, be, isArithmetic, ctx: ctx,
        synthesizer: synthesizer, checker: checker, diag: diag)) {
        resultTy
    } else {
        ClearExprKeepTargets(be)
        SynBuiltinBinaryFromLeft(typeManager, be, isArithmetic, ctx: ctx,
            synthesizer: synthesizer, checker: checker, diag: diag)
    }
    if (!Ty.IsTyCorrect(ty)) {
        return BinaryInvalid(be)
    }
    let typeCandidates = GetBinaryOpTypeCandidates(be.op)
    if (typeCandidates.isEmpty()) {
        return BinaryInvalid(be)
    }
    ty = Ty.GetPrimitiveUpperBound(ty)
    if (let Some(tv) <- (ty as GenericsTy)) {
        if (tv.isPlaceholder) {
            match (impl.PickConstaintFromTys(tv, TypeMapToTys(typeCandidates, true), true)) {
                case MatchResult.UNIQUE =>
                    let resultTy = typeManager.TryGreedySubst(tv)
                    be.SetTy(resultTy)
                    return resultTy
                case MatchResult.AMBIGUOUS => return BinaryInvalid(be)
                case MatchResult.NONE => ()
            }
        }
    }
    if (!ty.IsNothing() && !IsBinaryCandidateKind(be.op, ty.kind)) {
        return BinaryInvalid(be)
    }
    let resultTy = BuiltinBinaryResultTy(be.op, ty, isArithmetic)
    be.SetTy(resultTy)
    return resultTy
}

private func SynthesizeOperands(typeManager: TypeManager, be: BinaryExpr,
    synthesizer!: Option<BinaryOperandSynthesizer> = None): Option<(Ty, Ty)> {
    if (let Some(leftExpr) <- be.leftExpr) {
        if (let Some(rightExpr) <- be.rightExpr) {
            let leftTy = SynBinaryOperand(typeManager, leftExpr, synthesizer)
            let rightTy = SynBinaryOperand(typeManager, rightExpr, synthesizer)
            if (Ty.IsTyCorrect(leftTy) && Ty.IsTyCorrect(rightTy)) {
                return Some((TcReplaceIdeal(typeManager, leftExpr), TcReplaceIdeal(typeManager, rightExpr)))
            }
        }
    }
    return None
}

private func SynArithmeticExpr(impl: TypeCheckerImpl, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    return SynArithmeticOrRelationalExpr(impl, be, isArithmetic: true, ctx: ctx,
        synthesizer: synthesizer, checker: checker, diag: diag)
}

private func SynRelationalExpr(impl: TypeCheckerImpl, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    let typeManager = impl.typeManager
    let relationTy = SynArithmeticOrRelationalExpr(impl, be, isArithmetic: false, ctx: ctx,
        synthesizer: synthesizer, checker: checker, diag: diag)
    if (Ty.IsTyCorrect(relationTy)) {
        return relationTy
    }
    if (let Some(tys) <- SynthesizeOperands(typeManager, be, synthesizer: synthesizer)) {
        let leftTy = tys[0]
        let rightTy = tys[1]
        if (leftTy.IsTuple() || rightTy.IsTuple()) {
            if ((be.op == TokenKind.EQUAL || be.op == TokenKind.NOTEQ) && leftTy.IsTuple() && rightTy.IsTuple()) {
                if (CheckTupleCanEqual(typeManager, be, leftTy, rightTy)) {
                    let boolTy = TcBoolTy()
                    be.SetTy(boolTy)
                    return boolTy
                }
            }
            return BinaryInvalid(be)
        }
    }
    return BinaryInvalid(be)
}

private func SynRelationalExpr(typeManager: TypeManager, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    return SynRelationalExpr(TypeCheckerImpl(typeManager: typeManager, diag: diag), be, ctx: ctx,
        synthesizer: synthesizer, checker: checker, diag: diag)
}

private func HasSideEffect(expr: Expr): Bool {
    return expr.astKind != ASTKind.TUPLE_LIT && expr.astKind != ASTKind.REF_EXPR
}

private func CloneExprOrInvalid(expr: Expr): Option<Expr> {
    return ASTCloner.Clone(expr) as Expr
}

private func GetTupleElements(expr: Expr): ArrayList<Expr> {
    let elements = ArrayList<Expr>()
    if (let Some(tupleLit) <- (expr as TupleLit)) {
        for (child in tupleLit.children) {
            if (let Some(clonedChild) <- CloneExprOrInvalid(child)) {
                elements.add(clonedChild)
            }
        }
        return elements
    }
    let exprTy = expr.GetTy() ?? TypeManager.GetInvalidTy()
    if (let Some(tupleTy) <- (exprTy as TupleTy)) {
        let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let hasSideEffect = HasSideEffect(expr)
        var mapExpr: Option<Expr> = None
        for (idx in 0..tupleTy.typeArgs.size) {
            if (let Some(clonedBase) <- CloneExprOrInvalid(expr)) {
                if (hasSideEffect) {
                    if (let None <- mapExpr) {
                        mapExpr = clonedBase
                    }
                    clonedBase.mapExpr = mapExpr
                }
                let tupleAccess = SubscriptExpr()
                tupleAccess.isTupleAccess = true
                tupleAccess.baseExpr = clonedBase
                let indexExpr = CreateLitConstExpr(LitConstKind.INTEGER, "${idx}", int64Ty)
                tupleAccess.indexExprs.add(indexExpr)
                tupleAccess.SetTy(tupleTy.typeArgs[idx])
                tupleAccess.curFile = expr.curFile
                elements.add(tupleAccess)
            }
        }
    }
    return elements
}

private func CheckTupleCanEqual(typeManager: TypeManager, be: BinaryExpr, leftTy: Ty, rightTy: Ty): Bool {
    if (let Some(leftTuple) <- (leftTy as TupleTy)) {
        if (let Some(rightTuple) <- (rightTy as TupleTy)) {
            if (leftTuple.typeArgs.size != rightTuple.typeArgs.size) {
                be.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
                be.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            let leftExpr = be.leftExpr.getOrThrow()
            let rightExpr = be.rightExpr.getOrThrow()
            let leftElements = GetTupleElements(leftExpr)
            let rightElements = GetTupleElements(rightExpr)
            if (leftElements.size != leftTuple.typeArgs.size || rightElements.size != rightTuple.typeArgs.size) {
                be.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            let boolTy = TcBoolTy()
            var tupleCmpExpr: Expr = CreateLitConstExpr(LitConstKind.BOOL,
                if (be.op == TokenKind.EQUAL) { "true" } else { "false" }, boolTy)
            let connectionOp = if (be.op == TokenKind.EQUAL) { TokenKind.AND } else { TokenKind.OR }
            for (idx in 0..leftElements.size) {
                let elementCmpExpr = CreateBinaryExpr(leftElements[idx], rightElements[idx], be.op)
                elementCmpExpr.EnableAttr(Attribute.IMPLICIT_ADD)
                CopyBasicInfo(be, elementCmpExpr)
                let returnTy = SynBinaryExpr(typeManager, elementCmpExpr)
                if (!Ty.IsTyCorrect(returnTy) || !returnTy.IsBoolean()) {
                    be.SetTy(TypeManager.GetInvalidTy())
                    return false
                }
                let connectionExpr = CreateBinaryExpr(tupleCmpExpr, elementCmpExpr, connectionOp)
                connectionExpr.SetTy(boolTy)
                tupleCmpExpr = connectionExpr
            }
            if (HasSideEffect(leftExpr) || HasSideEffect(rightExpr)) {
                tupleCmpExpr.EnableAttr(Attribute.SIDE_EFFECT)
            }
            be.SetTy(boolTy)
            be.desugarExpr = tupleCmpExpr
            return true
        }
    }
    be.SetTy(TypeManager.GetInvalidTy())
    return false
}

private func SynLogicalExpr(typeManager: TypeManager, be: BinaryExpr,
    checker!: Option<BinaryOperandChecker> = None): Ty {
    var ok = true
    if (let Some(leftExpr) <- be.leftExpr) {
        let leftOk = if (let Some(chk) <- checker) {
            chk(TcBoolTy(), leftExpr)
        } else {
            TcCheckCondition(typeManager, leftExpr)
        }
        ok = leftOk && ok
    } else {
        ok = false
    }
    if (let Some(rightExpr) <- be.rightExpr) {
        let rightOk = if (let Some(chk2) <- checker) {
            chk2(TcBoolTy(), rightExpr)
        } else {
            TcCheckCondition(typeManager, rightExpr)
        }
        ok = rightOk && ok
    } else {
        ok = false
    }
    if (ok) {
        let boolTy = TcBoolTy()
        be.SetTy(boolTy)
        return boolTy
    }
    return BinaryInvalid(be)
}

private func SynShiftExpr(typeManager: TypeManager, be: BinaryExpr,
    synthesizer!: Option<BinaryOperandSynthesizer> = None): Ty {
    if (let Some(tys) <- SynthesizeOperands(typeManager, be, synthesizer: synthesizer)) {
        let leftTy = tys[0]
        let rightTy = tys[1]
        if ((leftTy.IsIntegerSubType() || leftTy.IsNothing()) && (rightTy.IsIntegerSubType() || rightTy.IsNothing())) {
            be.SetTy(leftTy)
            return leftTy
        }
    }
    return BinaryInvalid(be)
}

private func SynPipelineExpr(typeManager: TypeManager, be: BinaryExpr,
    synthesizer!: Option<BinaryOperandSynthesizer> = None): Ty {
    if (let Some(tys) <- SynthesizeOperands(typeManager, be, synthesizer: synthesizer)) {
        let leftTy = tys[0]
        let rightTy = tys[1]
        if (let Some(funcTy) <- (rightTy as FuncTy)) {
            if (funcTy.paramTys.size == 1 &&
                typeManager.CheckTypeCompatibility(funcTy.paramTys[0], leftTy) != TypeCompatibility.INCOMPATIBLE) {
                be.SetTy(funcTy.retTy)
                return funcTy.retTy
            }
        }
    }
    return BinaryInvalid(be)
}

private func SynCompositionExpr(typeManager: TypeManager, be: BinaryExpr,
    synthesizer!: Option<BinaryOperandSynthesizer> = None): Ty {
    if (let Some(tys) <- SynthesizeOperands(typeManager, be, synthesizer: synthesizer)) {
        let leftTy = tys[0]
        let rightTy = tys[1]
        if (let Some(leftFunc) <- (leftTy as FuncTy)) {
            if (let Some(rightFunc) <- (rightTy as FuncTy)) {
                if (leftFunc.paramTys.size == 1 && rightFunc.paramTys.size == 1 &&
                    typeManager.CheckTypeCompatibility(rightFunc.paramTys[0], leftFunc.retTy) !=
                        TypeCompatibility.INCOMPATIBLE) {
                    let composedTy = typeManager.GetFunctionTy([leftFunc.paramTys[0]], rightFunc.retTy)
                    be.SetTy(composedTy)
                    return composedTy
                }
            }
        }
    }
    return BinaryInvalid(be)
}

private func SynFlowExpr(typeManager: TypeManager, be: BinaryExpr,
    synthesizer!: Option<BinaryOperandSynthesizer> = None): Ty {
    let desugarResult = TrySynFlowDesugar(typeManager, be)
    if (desugarResult[0]) {
        return desugarResult[1]
    }
    if (be.op == TokenKind.PIPELINE) {
        return SynPipelineExpr(typeManager, be, synthesizer: synthesizer)
    }
    if (be.op == TokenKind.COMPOSITION) {
        return SynCompositionExpr(typeManager, be, synthesizer: synthesizer)
    }
    return BinaryInvalid(be)
}

private func ChkFlowExpr(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
    if (let Some(existingTy) <- be.GetTy()) {
        if (Ty.IsTyCorrect(existingTy)) {
            return typeManager.CheckTypeCompatibility(target, existingTy) != TypeCompatibility.INCOMPATIBLE
        }
    }
    let desugarResult = TryChkFlowDesugar(typeManager, target, be)
    if (desugarResult[0]) {
        return desugarResult[1]
    }
    let actualTy = if (be.op == TokenKind.PIPELINE) {
        SynPipelineExpr(typeManager, be)
    } else {
        SynCompositionExpr(typeManager, be)
    }
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = BinaryInvalid(be)
    return false
}

private func IsCoalescingLeftTyValid(impl: TypeCheckerImpl, ty: Ty): Bool {
    var realTy = ty
    if (ty.IsPlaceholder()) {
        if (let Some(genericTy) <- (ty as GenericsTy)) {
            if (let Some(manager) <- impl.importManager) {
                if (let Some(optionDecl) <- manager.GetCoreDecl<Decl>(STD_LIB_OPTION)) {
                    realTy = if (let Some(optionTy) <- optionDecl.GetTy()) {
                        impl.typeManager.ConstrainByCtor(genericTy, optionTy) ?? TypeManager.GetInvalidTy()
                    } else {
                        TypeManager.GetInvalidTy()
                    }
                } else {
                    realTy = TypeManager.GetInvalidTy()
                }
            } else {
                realTy = TypeManager.GetInvalidTy()
            }
        }
    }
    if (!Ty.IsTyCorrect(realTy) || !realTy.IsEnum()) {
        return false
    }
    let enumTy = match (realTy as EnumTy) {
        case Some(value) => value
        case None => return false
    }
    let enumDecl = match (enumTy.declPtr) {
        case Some(value) => value
        case None => return false
    }
    if (enumDecl.fullPackageName != UTILS_CORE_PACKAGE_NAME || enumTy.typeArgs.size != 1) {
        return false
    } else if (enumDecl.identifier == STD_LIB_OPTION) {
        return true
    }
    return false
}

private func SynCoalescingExpr(impl: TypeCheckerImpl, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None): Ty {
    let typeManager = impl.typeManager
    if (let Some(leftExpr) <- be.leftExpr) {
        let leftTy = SynBinaryOperand(typeManager, leftExpr, synthesizer)
        if (!Ty.IsTyCorrect(leftTy)) {
            return BinaryInvalid(be)
        }
        var concreteLeftTy = TcReplaceIdeal(typeManager, leftExpr)
        if (!IsCoalescingLeftTyValid(impl, concreteLeftTy)) {
            return BinaryInvalid(be)
        }
        concreteLeftTy = typeManager.TryGreedySubst(concreteLeftTy)
        leftExpr.SetTy(concreteLeftTy)
        if (concreteLeftTy.typeArgs.size != 1) {
            return BinaryInvalid(be)
        }
        let unboxedTy = concreteLeftTy.typeArgs[0]
        if (let Some(rightExpr) <- be.rightExpr) {
            if (ChkBinaryOperand(typeManager, unboxedTy, rightExpr, ctx, checker)) {
                be.SetTy(unboxedTy)
                return unboxedTy
            }
        }
    }
    return BinaryInvalid(be)
}

private func ChkCoalescingExpr(impl: TypeCheckerImpl, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None): Bool {
    let typeManager = impl.typeManager
    if (let Some(leftExpr) <- be.leftExpr) {
        let leftTy = SynBinaryOperand(typeManager, leftExpr, synthesizer)
        if (!Ty.IsTyCorrect(leftTy)) {
            let _ = BinaryInvalid(be)
            return false
        }
        var concreteLeftTy = TcReplaceIdeal(typeManager, leftExpr)
        if (!IsCoalescingLeftTyValid(impl, concreteLeftTy)) {
            let _ = BinaryInvalid(be)
            return false
        }
        concreteLeftTy = typeManager.TryGreedySubst(concreteLeftTy)
        leftExpr.SetTy(concreteLeftTy)
        if (concreteLeftTy.typeArgs.size != 1) {
            let _ = BinaryInvalid(be)
            return false
        }
        let unboxedTy = concreteLeftTy.typeArgs[0]
        if (typeManager.CheckTypeCompatibility(target, unboxedTy) == TypeCompatibility.INCOMPATIBLE) {
            let _ = BinaryInvalid(be)
            return false
        }
        if (let Some(rightExpr) <- be.rightExpr) {
            if (ChkBinaryOperand(typeManager, target, rightExpr, ctx, checker)) {
                be.SetTy(target)
                return true
            }
        }
    }
    let _ = BinaryInvalid(be)
    return false
}

private func ChkConcreteBinaryOperandPair(typeManager: TypeManager, candidateTy: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, checker!: Option<BinaryOperandChecker> = None): Bool {
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        return false
    }
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    ClearExprKeepTargets(leftExpr)
    ClearExprKeepTargets(rightExpr)
    let leftOk = ChkBinaryOperand(typeManager, candidateTy, leftExpr, ctx, checker)
    let rightOk = ChkBinaryOperand(typeManager, candidateTy, rightExpr, ctx, checker)
    if (leftOk && rightOk) {
        be.SetTy(candidateTy)
        return true
    }
    return false
}

private func ChkExpoExprWithTarget(typeManager: TypeManager, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, checker!: Option<BinaryOperandChecker> = None): Bool {
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        let _ = BinaryInvalid(be)
        return false
    }
    let i64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    let u64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT64)
    let f64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_FLOAT64)
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    if (typeManager.IsSubtype(i64Ty, target)) {
        ClearExprKeepTargets(leftExpr)
        ClearExprKeepTargets(rightExpr)
        let leftI64Ok = ChkBinaryOperand(typeManager, i64Ty, leftExpr, ctx, checker)
        let rightU64Ok = ChkBinaryOperand(typeManager, u64Ty, rightExpr, ctx, checker)
        if (leftI64Ok && rightU64Ok) {
            be.SetTy(i64Ty)
            return true
        }
    }
    if (typeManager.IsSubtype(f64Ty, target)) {
        ClearExprKeepTargets(leftExpr)
        ClearExprKeepTargets(rightExpr)
        let leftF64Ok = ChkBinaryOperand(typeManager, f64Ty, leftExpr, ctx, checker)
        ClearExprKeepTargets(rightExpr)
        let rightI64Ok = ChkBinaryOperand(typeManager, i64Ty, rightExpr, ctx, checker)
        ClearExprKeepTargets(rightExpr)
        let rightF64Ok = ChkBinaryOperand(typeManager, f64Ty, rightExpr, ctx, checker)
        if (leftF64Ok && rightI64Ok && !rightF64Ok) {
            ClearExprKeepTargets(rightExpr)
            if (ChkBinaryOperand(typeManager, i64Ty, rightExpr, ctx, checker)) {
                be.SetTy(f64Ty)
                return true
            }
        }
        if (leftF64Ok && rightF64Ok && !rightI64Ok) {
            ClearExprKeepTargets(rightExpr)
            if (ChkBinaryOperand(typeManager, f64Ty, rightExpr, ctx, checker)) {
                be.SetTy(f64Ty)
                return true
            }
        }
        if (leftF64Ok && rightI64Ok && rightF64Ok) {
            let _ = BinaryInvalid(be)
            return false
        }
    }
    let _ = BinaryInvalid(be)
    return false
}

private func ChkArithmeticExprBuiltin(typeManager: TypeManager, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, checker!: Option<BinaryOperandChecker> = None): Bool {
    let targetTy = UnboxOptionType(target)
    if (!Ty.IsTyCorrect(targetTy)) {
        return false
    }
    if (be.op == TokenKind.EXP) {
        return ChkExpoExprWithTarget(typeManager, targetTy, be, ctx: ctx, checker: checker)
    }
    let candidateKinds = GetConcreteBinaryCandidateKinds(be.op)
    for (kindValue in candidateKinds) {
        let candidateTy = TypeManager.GetPrimitiveTy(kindValue)
        if (typeManager.IsSubtype(candidateTy, targetTy) &&
            ChkConcreteBinaryOperandPair(typeManager, candidateTy, be, ctx: ctx, checker: checker)) {
            return true
        }
    }
    let _ = BinaryInvalid(be)
    return false
}

private func TargetAcceptsBool(typeManager: TypeManager, target: Ty): Bool {
    let boolTy = TcBoolTy()
    return target.IsBoolean() || typeManager.IsLitBoxableType(boolTy, target)
}

private func ChkRelationalExprBuiltin(typeManager: TypeManager, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (!TargetAcceptsBool(typeManager, target)) {
        return false
    }
    let relationTy = SynRelationalExpr(typeManager, be, ctx: ctx, synthesizer: synthesizer, checker: checker,
        diag: diag)
    if (Ty.IsTyCorrect(relationTy) && relationTy.IsBoolean()) {
        return true
    }
    let _ = BinaryInvalid(be)
    return false
}

private func ChkLogicalExprBuiltin(typeManager: TypeManager, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, checker!: Option<BinaryOperandChecker> = None): Bool {
    if (!TargetAcceptsBool(typeManager, target)) {
        let _ = BinaryInvalid(be)
        return false
    }
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        let _ = BinaryInvalid(be)
        return false
    }
    let boolTy = TcBoolTy()
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    ClearExprKeepTargets(leftExpr)
    ClearExprKeepTargets(rightExpr)
    let leftOk = ChkBinaryOperand(typeManager, boolTy, leftExpr, ctx, checker)
    let rightOk = ChkBinaryOperand(typeManager, boolTy, rightExpr, ctx, checker)
    if (leftOk && rightOk) {
        be.SetTy(boolTy)
        return true
    }
    let _ = BinaryInvalid(be)
    return false
}

private func ChkShiftExprBuiltin(typeManager: TypeManager, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None): Bool {
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        let _ = BinaryInvalid(be)
        return false
    }
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    ClearExprKeepTargets(leftExpr)
    ClearExprKeepTargets(rightExpr)
    let leftOk = ChkBinaryOperand(typeManager, target, leftExpr, ctx, checker)
    let leftTy = leftExpr.GetTy() ?? TypeManager.GetInvalidTy()
    let rightTy = SynBinaryOperand(typeManager, rightExpr, synthesizer)
    if (!leftOk || !Ty.IsTyCorrect(rightTy)) {
        let _ = BinaryInvalid(be)
        return false
    }
    let concreteLeftTy = Ty.GetPrimitiveUpperBound(TcReplaceIdeal(typeManager, leftExpr))
    let concreteRightTy = Ty.GetPrimitiveUpperBound(TcReplaceIdeal(typeManager, rightExpr))
    if (IsBinaryCandidateTy(be.op, concreteLeftTy) && IsBinaryCandidateTy(be.op, concreteRightTy)) {
        be.SetTy(leftTy)
        return true
    }
    let _ = BinaryInvalid(be)
    return false
}

private func ChkBuiltinBinaryExpr(typeManager: TypeManager, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    if (IsArithmeticOperator(be.op)) {
        return ChkArithmeticExprBuiltin(typeManager, target, be, ctx: ctx, checker: checker)
    }
    if (IsRelationalOperator(be.op)) {
        return ChkRelationalExprBuiltin(typeManager, target, be, ctx: ctx,
            synthesizer: synthesizer, checker: checker, diag: diag)
    }
    if (IsLogicalOperator(be.op)) {
        return ChkLogicalExprBuiltin(typeManager, target, be, ctx: ctx, checker: checker)
    }
    if (IsShiftOperator(be.op)) {
        return ChkShiftExprBuiltin(typeManager, target, be, ctx: ctx, synthesizer: synthesizer, checker: checker)
    }
    return false
}

public func SynBinaryExpr(impl: TypeCheckerImpl, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    let typeManager = impl.typeManager
    if (let Some(desugar) <- be.desugarExpr) {
        if (let Some(desugarTy) <- desugar.GetTy()) {
            PropagateBinaryDesugarTarget(be, desugar)
            be.SetTy(desugarTy)
            return desugarTy
        }
    }
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        return BinaryInvalid(be)
    }
    if (IsLogicalOperator(be.op)) {
        try (ds = DiagSuppressor(diag)) {
            let logicalTy = SynLogicalExpr(typeManager, be, checker: checker)
            if (Ty.IsTyCorrect(logicalTy)) {
                ds.ReportDiag()
                return logicalTy
            }
        }
        if (be.TestAttr(Attribute.IS_OUTERMOST)) {
            SynBinaryLeafs(typeManager, be, synthesizer)
        }
        if (HasInvalidChild(be)) {
            if (be.TestAttr(Attribute.IS_OUTERMOST)) {
                DiagnoseForBinaryExpr(typeManager, be, synthesizer, diag)
            }
            be.SetTy(TypeManager.GetInvalidTy())
            return be.GetTy() ?? TypeManager.GetInvalidTy()
        }
    } else if (IsArithmeticOperator(be.op)) {
        try (ds2 = DiagSuppressor(diag)) {
            let builtinTy = SynArithmeticExpr(impl, be, ctx: ctx, synthesizer: synthesizer, checker: checker,
                diag: diag)
            if (Ty.IsTyCorrect(builtinTy)) {
                ds2.ReportDiag()
                return builtinTy
            }
        }
        if (be.TestAttr(Attribute.IS_OUTERMOST)) {
            SynBinaryLeafs(typeManager, be, synthesizer)
        }
        if (HasInvalidChild(be)) {
            if (be.TestAttr(Attribute.IS_OUTERMOST)) {
                DiagnoseForBinaryExpr(typeManager, be, synthesizer, diag)
            }
            be.SetTy(TypeManager.GetInvalidTy())
            return be.GetTy() ?? TypeManager.GetInvalidTy()
        }
        if (let Some(overloadTy) <- TrySynBinaryOverload(typeManager, be, ctx: ctx,
            synthesizer: synthesizer, checker: checker)) {
            return overloadTy
        }
    } else if (IsRelationalOperator(be.op)) {
        try (ds3 = DiagSuppressor(diag)) {
            let builtinTy2 = SynRelationalExpr(impl, be, ctx: ctx, synthesizer: synthesizer, checker: checker,
                diag: diag)
            if (Ty.IsTyCorrect(builtinTy2)) {
                ds3.ReportDiag()
                return builtinTy2
            }
        }
        if (be.TestAttr(Attribute.IS_OUTERMOST)) {
            SynBinaryLeafs(typeManager, be, synthesizer)
        }
        if (HasInvalidChild(be)) {
            if (be.TestAttr(Attribute.IS_OUTERMOST)) {
                DiagnoseForBinaryExpr(typeManager, be, synthesizer, diag)
            }
            be.SetTy(TypeManager.GetInvalidTy())
            return be.GetTy() ?? TypeManager.GetInvalidTy()
        }
        if (let Some(overloadTy2) <- TrySynBinaryOverload(typeManager, be, ctx: ctx,
            synthesizer: synthesizer, checker: checker)) {
            return overloadTy2
        }
    } else if (IsShiftOperator(be.op)) {
        try (ds4 = DiagSuppressor(diag)) {
            let builtinTy3 = SynShiftExpr(typeManager, be, synthesizer: synthesizer)
            if (Ty.IsTyCorrect(builtinTy3)) {
                ds4.ReportDiag()
                return builtinTy3
            }
        }
        if (be.TestAttr(Attribute.IS_OUTERMOST)) {
            SynBinaryLeafs(typeManager, be, synthesizer)
        }
        if (HasInvalidChild(be)) {
            if (be.TestAttr(Attribute.IS_OUTERMOST)) {
                DiagnoseForBinaryExpr(typeManager, be, synthesizer, diag)
            }
            be.SetTy(TypeManager.GetInvalidTy())
            return be.GetTy() ?? TypeManager.GetInvalidTy()
        }
        if (let Some(overloadTy3) <- TrySynBinaryOverload(typeManager, be, ctx: ctx,
            synthesizer: synthesizer, checker: checker)) {
            return overloadTy3
        }
    } else if (be.op == TokenKind.COALESCING) {
        return SynCoalescingExpr(impl, be, ctx: ctx, synthesizer: synthesizer, checker: checker)
    } else if (IsFlowOperator(be.op)) {
        return SynFlowExpr(typeManager, be, synthesizer: synthesizer)
    } else {
        be.SetTy(TypeManager.GetInvalidTy())
    }
    if (be.TestAttr(Attribute.IS_OUTERMOST)) {
        SynBinaryLeafs(typeManager, be, synthesizer)
    }
    DiagnoseForBinaryExpr(typeManager, be, synthesizer, diag)
    return be.GetTy() ?? TypeManager.GetInvalidTy()
}

public func SynBinaryExpr(typeManager: TypeManager, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    return SynBinaryExpr(TypeCheckerImpl(typeManager: typeManager, diag: diag), be, ctx: ctx,
        synthesizer: synthesizer, checker: checker, diag: diag)
}

public func ChkBinaryExpr(impl: TypeCheckerImpl, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let typeManager = impl.typeManager
    if (be.op == TokenKind.COALESCING) {
        return ChkCoalescingExpr(impl, target, be, ctx: ctx, synthesizer: synthesizer, checker: checker)
    }
    if (IsFlowOperator(be.op)) {
        return ChkFlowExpr(typeManager, target, be)
    }
    try (ds = DiagSuppressor(diag)) {
        if (ChkBuiltinBinaryExpr(typeManager, target, be, ctx: ctx, synthesizer: synthesizer, checker: checker,
            diag: diag)) {
            ds.ReportDiag()
            return true
        }
    }
    if (TryChkBinaryOverload(typeManager, target, be, ctx: ctx, synthesizer: synthesizer, checker: checker)) {
        return true
    }
    ClearExprKeepTargets(be)
    let actualTy = SynBinaryExpr(typeManager, be, ctx: ctx, synthesizer: synthesizer, checker: checker, diag: diag)
    if (Ty.IsTyCorrect(actualTy)) {
        if (let Some(diagValue) <- diag) {
            DiagMismatchedTypes(diagValue, be, target)
        }
        RecoverToBinaryExpr(be)
    }
    if (be.TestAttr(Attribute.IS_OUTERMOST)) {
        SynBinaryLeafs(typeManager, be, synthesizer)
    }
    let _ = BinaryInvalid(be)
    return false
}

public func ChkBinaryExpr(typeManager: TypeManager, target: Ty, be: BinaryExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<BinaryOperandSynthesizer> = None,
    checker!: Option<BinaryOperandChecker> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    return ChkBinaryExpr(TypeCheckerImpl(typeManager: typeManager, diag: diag), target, be, ctx: ctx,
        synthesizer: synthesizer, checker: checker, diag: diag)
}

extend TypeChecker {
}
