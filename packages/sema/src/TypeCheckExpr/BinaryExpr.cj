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

private func IsIntegerOperator(op: TokenKind): Bool {
    return op == TokenKind.MOD || op == TokenKind.BITAND || op == TokenKind.BITOR ||
        op == TokenKind.BITXOR || IsShiftOperator(op)
}

private func IsOrderedRelationalOperator(op: TokenKind): Bool {
    return op == TokenKind.GT || op == TokenKind.LT || op == TokenKind.GE || op == TokenKind.LE
}

private func IsBuiltinRelationNumericTy(ty: Ty): Bool {
    return ty.IsNumeric() || ty.IsRune()
}

private func IsBuiltinEqualityScalarTy(ty: Ty): Bool {
    return IsBuiltinRelationNumericTy(ty) || ty.IsBoolean() || ty.IsUnit() || ty.IsNothing()
}

private func BinaryInvalid(be: BinaryExpr): Ty {
    return TcInvalid(be)
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

private func PrimitiveRank(kind: TypeKind): Int64 {
    return match (kind) {
        case TypeKind.TYPE_INT8 => 1
        case TypeKind.TYPE_INT16 => 2
        case TypeKind.TYPE_INT32 => 3
        case TypeKind.TYPE_INT64 => 4
        case TypeKind.TYPE_INT_NATIVE => 5
        case TypeKind.TYPE_UINT8 => 6
        case TypeKind.TYPE_UINT16 => 7
        case TypeKind.TYPE_UINT32 => 8
        case TypeKind.TYPE_UINT64 => 9
        case TypeKind.TYPE_UINT_NATIVE => 10
        case TypeKind.TYPE_FLOAT16 => 11
        case TypeKind.TYPE_FLOAT32 => 12
        case TypeKind.TYPE_FLOAT64 => 13
        case TypeKind.TYPE_IDEAL_INT => 0
        case TypeKind.TYPE_IDEAL_FLOAT => 14
        case _ => -1
    }
}

private func NormalizeIdealNumericKind(kind: TypeKind): TypeKind {
    if (kind == TypeKind.TYPE_IDEAL_INT) {
        return TypeKind.TYPE_INT64
    }
    if (kind == TypeKind.TYPE_IDEAL_FLOAT) {
        return TypeKind.TYPE_FLOAT64
    }
    return kind
}

private func PickNumericTy(typeManager: TypeManager, leftTy: Ty, rightTy: Ty): Option<Ty> {
    let leftUpper = Ty.GetPrimitiveUpperBound(leftTy)
    let rightUpper = Ty.GetPrimitiveUpperBound(rightTy)
    if (leftUpper.IsNothing()) {
        return Some(rightUpper)
    }
    if (rightUpper.IsNothing()) {
        return Some(leftUpper)
    }
    if (!leftUpper.IsNumeric() || !rightUpper.IsNumeric()) {
        return None
    }
    if (SameTy(leftUpper, rightUpper)) {
        return Some(leftUpper)
    }
    if (leftUpper.IsIdeal()) {
        if (rightUpper.IsNumeric()) {
            return Some(rightUpper)
        }
    }
    if (rightUpper.IsIdeal()) {
        if (leftUpper.IsNumeric()) {
            return Some(leftUpper)
        }
    }
    let leftRank = PrimitiveRank(leftUpper.kind)
    let rightRank = PrimitiveRank(rightUpper.kind)
    let pickedKind = if (leftRank >= rightRank) { leftUpper.kind } else { rightUpper.kind }
    let normalizedKind = NormalizeIdealNumericKind(pickedKind)
    let _ = typeManager
    return Some(TypeManager.GetPrimitiveTy(normalizedKind))
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
    if (let Some(tys) <- SynthesizeOperands(typeManager, be)) {
        let leftTy = tys[0]
        let rightTy = tys[1]
        if (be.op == TokenKind.EXP) {
            return SynExpoExpr(typeManager, be, leftTy, rightTy)
        }
        if (IsIntegerOperator(be.op) && (!leftTy.IsIntegerSubType() || !rightTy.IsIntegerSubType())) {
            return BinaryInvalid(be)
        }
        if (let Some(resultTy) <- PickNumericTy(typeManager, leftTy, rightTy)) {
            be.SetTy(resultTy)
            return resultTy
        }
    }
    return BinaryInvalid(be)
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
                if (TupleCanEqual(typeManager, leftTy, rightTy)) {
                    let boolTy = TcBoolTy()
                    be.SetTy(boolTy)
                    return boolTy
                }
            }
            return BinaryInvalid(be)
        }
        if (IsOrderedRelationalOperator(be.op)) {
            if (CanBuiltinOrderedCompare(typeManager, leftTy, rightTy)) {
                let boolTy = TcBoolTy()
                be.SetTy(boolTy)
                return boolTy
            }
            return BinaryInvalid(be)
        }
        if (CanBuiltinEqualityCompare(typeManager, leftTy, rightTy)) {
            let boolTy2 = TcBoolTy()
            be.SetTy(boolTy2)
            return boolTy2
        }
    }
    return BinaryInvalid(be)
}

private func CanBuiltinOrderedCompare(typeManager: TypeManager, leftTy: Ty, rightTy: Ty): Bool {
    if (leftTy.IsNothing() || rightTy.IsNothing()) {
        return true
    }
    if (leftTy.IsRune() && rightTy.IsRune()) {
        return true
    }
    if (let Some(_) <- PickNumericTy(typeManager, leftTy, rightTy)) {
        return true
    }
    return false
}

private func CanBuiltinEqualityCompare(typeManager: TypeManager, leftTy: Ty, rightTy: Ty): Bool {
    if (leftTy.IsNothing() || rightTy.IsNothing()) {
        return true
    }
    if (!IsBuiltinEqualityScalarTy(leftTy) || !IsBuiltinEqualityScalarTy(rightTy)) {
        return false
    }
    if (leftTy.IsBoolean() || rightTy.IsBoolean()) {
        return leftTy.IsBoolean() && rightTy.IsBoolean()
    }
    if (leftTy.IsUnit() || rightTy.IsUnit()) {
        return leftTy.IsUnit() && rightTy.IsUnit()
    }
    if (leftTy.IsRune() || rightTy.IsRune()) {
        return leftTy.IsRune() && rightTy.IsRune()
    }
    if (let Some(_) <- PickNumericTy(typeManager, leftTy, rightTy)) {
        return true
    }
    return false
}

private func TupleCanEqual(typeManager: TypeManager, leftTy: Ty, rightTy: Ty): Bool {
    if (let Some(leftTuple) <- (leftTy as TupleTy)) {
        if (let Some(rightTuple) <- (rightTy as TupleTy)) {
            if (leftTuple.typeArgs.size != rightTuple.typeArgs.size) {
                return false
            }
            for (idx in 0..leftTuple.typeArgs.size) {
                let leftArg = leftTuple.typeArgs[idx]
                let rightArg = rightTuple.typeArgs[idx]
                if (leftArg.IsTuple() || rightArg.IsTuple()) {
                    if (!TupleCanEqual(typeManager, leftArg, rightArg)) {
                        return false
                    }
                } else if (!CanBuiltinEqualityCompare(typeManager, leftArg, rightArg)) {
                    return false
                }
            }
            return true
        }
    }
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
    if (be.op == TokenKind.PIPELINE) {
        return SynPipelineExpr(typeManager, be)
    }
    if (be.op == TokenKind.COMPOSITION) {
        return SynCompositionExpr(typeManager, be)
    }
    return BinaryInvalid(be)
}

public func ChkBinaryExpr(typeManager: TypeManager, target: Ty, be: BinaryExpr): Bool {
    if (be.op == TokenKind.COALESCING) {
        return ChkCoalescingExpr(typeManager, target, be)
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
