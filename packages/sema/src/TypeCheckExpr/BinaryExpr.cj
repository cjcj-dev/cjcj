package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*
import cangjie_compiler::sema.Desugar.*

public func SelfhostPortStatus_TypeCheckExpr_BinaryExpr(): Bool {
    return true
}

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

private func BinaryOperandsReady(typeManager: TypeManager, be: BinaryExpr): Bool {
    if (let Some(leftExpr) <- be.leftExpr) {
        if (let Some(rightExpr) <- be.rightExpr) {
            let leftTy = SynExprShallow(typeManager, leftExpr)
            let rightTy = SynExprShallow(typeManager, rightExpr)
            if (Ty.IsTyCorrect(leftTy) && Ty.IsTyCorrect(rightTy)) {
                let _ = TcReplaceIdeal(typeManager, leftExpr)
                let _ = TcReplaceIdeal(typeManager, rightExpr)
                return true
            }
        }
    }
    return false
}

private func TrySynBinaryOverload(typeManager: TypeManager, be: BinaryExpr): Option<Ty> {
    if (!ShouldTryBinaryOverload(be) || !BinaryOperandsReady(typeManager, be)) {
        return None
    }
    DesugarOperatorOverloadExpr(be)
    if (let Some(desugar) <- be.desugarExpr) {
        let desugarTy = SynExprShallow(typeManager, desugar)
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

private func TryChkBinaryOverload(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
    if (!ShouldTryBinaryOverload(be) || !BinaryOperandsReady(typeManager, be)) {
        return false
    }
    DesugarOperatorOverloadExpr(be)
    if (let Some(desugar) <- be.desugarExpr) {
        if (ChkExprShallow(typeManager, target, desugar)) {
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
    isArithmetic: Bool): Option<Ty> {
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        be.SetTy(TypeManager.GetInvalidTy())
        return Some(TypeManager.GetInvalidTy())
    }
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    let rightTy = SynExprShallow(typeManager, rightExpr)
    if (!Ty.IsTyCorrect(rightTy)) {
        be.SetTy(TypeManager.GetInvalidTy())
        return None
    }
    let targetRight = Ty.GetPrimitiveUpperBound(TcReplaceIdeal(typeManager, rightExpr))
    if (!IsBinaryCandidateTy(be.op, targetRight)) {
        let _ = SynExprShallow(typeManager, leftExpr)
        be.SetTy(TypeManager.GetInvalidTy())
        return Some(TypeManager.GetInvalidTy())
    }
    ClearExprKeepTargets(leftExpr)
    if (ChkExprShallow(typeManager, targetRight, leftExpr)) {
        let solvedRight = typeManager.TryGreedySubst(targetRight)
        rightExpr.SetTy(solvedRight)
        let resultTy = BuiltinBinaryResultTy(be.op, solvedRight, isArithmetic)
        be.SetTy(resultTy)
        return Some(resultTy)
    }
    be.SetTy(TypeManager.GetInvalidTy())
    return None
}

private func SynBuiltinBinaryFromLeft(typeManager: TypeManager, be: BinaryExpr,
    isArithmetic: Bool): Ty {
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        return BinaryInvalid(be)
    }
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    let leftTy = SynExprShallow(typeManager, leftExpr)
    if (!Ty.IsTyCorrect(leftTy)) {
        let _ = SynExprShallow(typeManager, rightExpr)
        return BinaryInvalid(be)
    }
    let targetLeft = Ty.GetPrimitiveUpperBound(TcReplaceIdeal(typeManager, leftExpr))
    if (!IsBinaryCandidateTy(be.op, targetLeft)) {
        let _ = SynExprShallow(typeManager, rightExpr)
        return BinaryInvalid(be)
    }
    ClearExprKeepTargets(rightExpr)
    if (ChkExprShallow(typeManager, targetLeft, rightExpr)) {
        let solvedLeft = typeManager.TryGreedySubst(targetLeft)
        leftExpr.SetTy(solvedLeft)
        let resultTy = BuiltinBinaryResultTy(be.op, solvedLeft, isArithmetic)
        be.SetTy(resultTy)
        return resultTy
    }
    return BinaryInvalid(be)
}

private func SynArithmeticOrRelationalExpr(typeManager: TypeManager, be: BinaryExpr,
    isArithmetic!: Bool = true): Ty {
    if (isArithmetic && be.op == TokenKind.EXP) {
        if (let Some(tys) <- SynthesizeOperands(typeManager, be)) {
            return SynExpoExpr(typeManager, be, tys[0], tys[1])
        }
        return BinaryInvalid(be)
    }
    if (let Some(resultTy) <- SynBuiltinBinaryFromRight(typeManager, be, isArithmetic)) {
        if (Ty.IsTyCorrect(resultTy)) {
            return resultTy
        }
        return BinaryInvalid(be)
    }
    ClearExprKeepTargets(be)
    return SynBuiltinBinaryFromLeft(typeManager, be, isArithmetic)
}

private func SynthesizeOperands(typeManager: TypeManager, be: BinaryExpr): Option<(Ty, Ty)> {
    if (let Some(leftExpr) <- be.leftExpr) {
        if (let Some(rightExpr) <- be.rightExpr) {
            let leftTy = SynExprShallow(typeManager, leftExpr)
            let rightTy = SynExprShallow(typeManager, rightExpr)
            if (Ty.IsTyCorrect(leftTy) && Ty.IsTyCorrect(rightTy)) {
                return Some((TcReplaceIdeal(typeManager, leftExpr), TcReplaceIdeal(typeManager, rightExpr)))
            }
        }
    }
    return None
}

private func SynArithmeticExpr(typeManager: TypeManager, be: BinaryExpr): Ty {
    return SynArithmeticOrRelationalExpr(typeManager, be, isArithmetic: true)
}

private func SynExpoExpr(typeManager: TypeManager, be: BinaryExpr, leftTy: Ty, rightTy: Ty): Ty {
    let i64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    let u64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT64)
    let f64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_FLOAT64)
    if (typeManager.IsSubtype(leftTy, i64Ty) && typeManager.IsSubtype(rightTy, u64Ty)) {
        be.SetTy(i64Ty)
        return i64Ty
    }
    if (typeManager.IsSubtype(leftTy, f64Ty) &&
        (typeManager.IsSubtype(rightTy, i64Ty) || typeManager.IsSubtype(rightTy, f64Ty))) {
        be.SetTy(f64Ty)
        return f64Ty
    }
    return BinaryInvalid(be)
}

private func SynRelationalExpr(typeManager: TypeManager, be: BinaryExpr): Ty {
    if (let Some(tys) <- SynthesizeOperands(typeManager, be)) {
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
    ClearExprKeepTargets(be)
    return SynArithmeticOrRelationalExpr(typeManager, be, isArithmetic: false)
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

private func SynLogicalExpr(typeManager: TypeManager, be: BinaryExpr): Ty {
    var ok = true
    if (let Some(leftExpr) <- be.leftExpr) {
        ok = TcCheckCondition(typeManager, leftExpr) && ok
    } else {
        ok = false
    }
    if (let Some(rightExpr) <- be.rightExpr) {
        ok = TcCheckCondition(typeManager, rightExpr) && ok
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

private func SynShiftExpr(typeManager: TypeManager, be: BinaryExpr): Ty {
    if (let Some(tys) <- SynthesizeOperands(typeManager, be)) {
        let leftTy = tys[0]
        let rightTy = tys[1]
        if ((leftTy.IsIntegerSubType() || leftTy.IsNothing()) && (rightTy.IsIntegerSubType() || rightTy.IsNothing())) {
            be.SetTy(leftTy)
            return leftTy
        }
    }
    return BinaryInvalid(be)
}

private func SynPipelineExpr(typeManager: TypeManager, be: BinaryExpr): Ty {
    if (let Some(tys) <- SynthesizeOperands(typeManager, be)) {
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

private func SynCompositionExpr(typeManager: TypeManager, be: BinaryExpr): Ty {
    if (let Some(tys) <- SynthesizeOperands(typeManager, be)) {
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

private func SynFlowExpr(typeManager: TypeManager, be: BinaryExpr): Ty {
    let desugarResult = TrySynFlowDesugar(typeManager, be)
    if (desugarResult[0]) {
        return desugarResult[1]
    }
    if (be.op == TokenKind.PIPELINE) {
        return SynPipelineExpr(typeManager, be)
    }
    if (be.op == TokenKind.COMPOSITION) {
        return SynCompositionExpr(typeManager, be)
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

private func SynCoalescingExpr(typeManager: TypeManager, be: BinaryExpr): Ty {
    if (let Some(leftExpr) <- be.leftExpr) {
        let leftTy = SynExprShallow(typeManager, leftExpr)
        if (!Ty.IsTyCorrect(leftTy)) {
            return BinaryInvalid(be)
        }
        let concreteLeftTy = TcReplaceIdeal(typeManager, leftExpr)
        if (!concreteLeftTy.IsCoreOptionType() || concreteLeftTy.typeArgs.size != 1) {
            return BinaryInvalid(be)
        }
        let unboxedTy = concreteLeftTy.typeArgs[0]
        if (let Some(rightExpr) <- be.rightExpr) {
            if (ChkExprShallow(typeManager, unboxedTy, rightExpr)) {
                be.SetTy(unboxedTy)
                return unboxedTy
            }
        }
    }
    return BinaryInvalid(be)
}

private func ChkCoalescingExpr(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
    if (let Some(leftExpr) <- be.leftExpr) {
        let leftTy = SynExprShallow(typeManager, leftExpr)
        if (!Ty.IsTyCorrect(leftTy)) {
            let _ = BinaryInvalid(be)
            return false
        }
        let concreteLeftTy = TcReplaceIdeal(typeManager, leftExpr)
        if (!concreteLeftTy.IsCoreOptionType() || concreteLeftTy.typeArgs.size != 1) {
            let _ = BinaryInvalid(be)
            return false
        }
        let unboxedTy = concreteLeftTy.typeArgs[0]
        if (typeManager.CheckTypeCompatibility(target, unboxedTy) == TypeCompatibility.INCOMPATIBLE) {
            let _ = BinaryInvalid(be)
            return false
        }
        if (let Some(rightExpr) <- be.rightExpr) {
            if (ChkExprShallow(typeManager, target, rightExpr)) {
                be.SetTy(target)
                return true
            }
        }
    }
    let _ = BinaryInvalid(be)
    return false
}

private func ChkConcreteBinaryOperandPair(typeManager: TypeManager, candidateTy: Ty, be: BinaryExpr): Bool {
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        return false
    }
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    ClearExprKeepTargets(leftExpr)
    ClearExprKeepTargets(rightExpr)
    let leftOk = ChkExprShallow(typeManager, candidateTy, leftExpr)
    let rightOk = ChkExprShallow(typeManager, candidateTy, rightExpr)
    if (leftOk && rightOk) {
        be.SetTy(candidateTy)
        return true
    }
    return false
}

private func ChkExpoExprWithTarget(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
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
        let leftI64Ok = ChkExprShallow(typeManager, i64Ty, leftExpr)
        let rightU64Ok = ChkExprShallow(typeManager, u64Ty, rightExpr)
        if (leftI64Ok && rightU64Ok) {
            be.SetTy(i64Ty)
            return true
        }
    }
    if (typeManager.IsSubtype(f64Ty, target)) {
        ClearExprKeepTargets(leftExpr)
        ClearExprKeepTargets(rightExpr)
        let leftF64Ok = ChkExprShallow(typeManager, f64Ty, leftExpr)
        ClearExprKeepTargets(rightExpr)
        let rightI64Ok = ChkExprShallow(typeManager, i64Ty, rightExpr)
        ClearExprKeepTargets(rightExpr)
        let rightF64Ok = ChkExprShallow(typeManager, f64Ty, rightExpr)
        if (leftF64Ok && rightI64Ok && !rightF64Ok) {
            ClearExprKeepTargets(rightExpr)
            if (ChkExprShallow(typeManager, i64Ty, rightExpr)) {
                be.SetTy(f64Ty)
                return true
            }
        }
        if (leftF64Ok && rightF64Ok && !rightI64Ok) {
            ClearExprKeepTargets(rightExpr)
            if (ChkExprShallow(typeManager, f64Ty, rightExpr)) {
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

private func ChkArithmeticExprBuiltin(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
    let targetTy = UnboxOptionType(target)
    if (!Ty.IsTyCorrect(targetTy)) {
        return false
    }
    if (be.op == TokenKind.EXP) {
        return ChkExpoExprWithTarget(typeManager, targetTy, be)
    }
    let candidateKinds = GetConcreteBinaryCandidateKinds(be.op)
    for (kindValue in candidateKinds) {
        let candidateTy = TypeManager.GetPrimitiveTy(kindValue)
        if (typeManager.IsSubtype(candidateTy, targetTy) &&
            ChkConcreteBinaryOperandPair(typeManager, candidateTy, be)) {
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

private func ChkRelationalExprBuiltin(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
    if (!TargetAcceptsBool(typeManager, target)) {
        return false
    }
    let relationTy = SynRelationalExpr(typeManager, be)
    if (Ty.IsTyCorrect(relationTy) && relationTy.IsBoolean()) {
        return true
    }
    let _ = BinaryInvalid(be)
    return false
}

private func ChkLogicalExprBuiltin(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
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
    let leftOk = ChkExprShallow(typeManager, boolTy, leftExpr)
    let rightOk = ChkExprShallow(typeManager, boolTy, rightExpr)
    if (leftOk && rightOk) {
        be.SetTy(boolTy)
        return true
    }
    let _ = BinaryInvalid(be)
    return false
}

private func ChkShiftExprBuiltin(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
    if ((let None <- be.leftExpr) || (let None <- be.rightExpr)) {
        let _ = BinaryInvalid(be)
        return false
    }
    let leftExpr = be.leftExpr.getOrThrow()
    let rightExpr = be.rightExpr.getOrThrow()
    ClearExprKeepTargets(leftExpr)
    ClearExprKeepTargets(rightExpr)
    let leftOk = ChkExprShallow(typeManager, target, leftExpr)
    let leftTy = leftExpr.GetTy() ?? TypeManager.GetInvalidTy()
    let rightTy = SynExprShallow(typeManager, rightExpr)
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

private func ChkBuiltinBinaryExpr(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
    if (IsArithmeticOperator(be.op)) {
        return ChkArithmeticExprBuiltin(typeManager, target, be)
    }
    if (IsRelationalOperator(be.op)) {
        return ChkRelationalExprBuiltin(typeManager, target, be)
    }
    if (IsLogicalOperator(be.op)) {
        return ChkLogicalExprBuiltin(typeManager, target, be)
    }
    if (IsShiftOperator(be.op)) {
        return ChkShiftExprBuiltin(typeManager, target, be)
    }
    return false
}

public func SynBinaryExpr(typeManager: TypeManager, be: BinaryExpr): Ty {
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
        return SynLogicalExpr(typeManager, be)
    }
    if (IsArithmeticOperator(be.op)) {
        let builtinTy = SynArithmeticExpr(typeManager, be)
        if (Ty.IsTyCorrect(builtinTy)) {
            return builtinTy
        }
        if (let Some(overloadTy) <- TrySynBinaryOverload(typeManager, be)) {
            return overloadTy
        }
        return BinaryInvalid(be)
    }
    if (IsRelationalOperator(be.op)) {
        let builtinTy2 = SynRelationalExpr(typeManager, be)
        if (Ty.IsTyCorrect(builtinTy2)) {
            return builtinTy2
        }
        if (let Some(overloadTy2) <- TrySynBinaryOverload(typeManager, be)) {
            return overloadTy2
        }
        return BinaryInvalid(be)
    }
    if (IsShiftOperator(be.op)) {
        let builtinTy3 = SynShiftExpr(typeManager, be)
        if (Ty.IsTyCorrect(builtinTy3)) {
            return builtinTy3
        }
        if (let Some(overloadTy3) <- TrySynBinaryOverload(typeManager, be)) {
            return overloadTy3
        }
        return BinaryInvalid(be)
    }
    if (be.op == TokenKind.COALESCING) {
        return SynCoalescingExpr(typeManager, be)
    }
    if (IsFlowOperator(be.op)) {
        return SynFlowExpr(typeManager, be)
    }
    return BinaryInvalid(be)
}

public func ChkBinaryExpr(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
    if (be.op == TokenKind.COALESCING) {
        return ChkCoalescingExpr(typeManager, target, be)
    }
    if (IsFlowOperator(be.op)) {
        return ChkFlowExpr(typeManager, target, be)
    }
    if (ChkBuiltinBinaryExpr(typeManager, target, be)) {
        return true
    }
    if (!HasTupleEqualityOperands(be)) {
        ClearExprKeepTargets(be)
    }
    let actualTy = SynBinaryExpr(typeManager, be)
    if (!Ty.IsTyCorrect(actualTy)) {
        if (TryChkBinaryOverload(typeManager, target, be)) {
            return true
        }
        return false
    }
    if (typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    if (TryChkBinaryOverload(typeManager, target, be)) {
        return true
    }
    let _ = BinaryInvalid(be)
    return false
}
