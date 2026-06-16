package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SelfhostPortStatus_TypeCheckExpr_AssignExpr(): Bool {
    return true
}

private func AssignInvalid(ae: AssignExpr): Ty {
    return TcInvalid(ae)
}

private func IsCompoundIntegerAssign(op: TokenKind): Bool {
    return op == TokenKind.MOD_ASSIGN || op == TokenKind.BITAND_ASSIGN || op == TokenKind.BITOR_ASSIGN ||
        op == TokenKind.BITXOR_ASSIGN || op == TokenKind.LSHIFT_ASSIGN || op == TokenKind.RSHIFT_ASSIGN
}

private func IsCompoundNumericAssign(op: TokenKind): Bool {
    return op == TokenKind.ADD_ASSIGN || op == TokenKind.SUB_ASSIGN || op == TokenKind.MUL_ASSIGN ||
        op == TokenKind.EXP_ASSIGN || op == TokenKind.DIV_ASSIGN || IsCompoundIntegerAssign(op)
}

private func IsCompoundBoolAssign(op: TokenKind): Bool {
    return op == TokenKind.AND_ASSIGN || op == TokenKind.OR_ASSIGN
}

private func IsAssignableExpr(expr: Expr): Bool {
    if (let Some(refExpr) <- (expr as RefExpr)) {
        if (refExpr.isThis && refExpr.isAlone) {
            return false
        }
        if (let Some(target) <- refExpr.ref.target) {
            return target.astKind != ASTKind.FUNC_DECL && !target.TestAttr(Attribute.ENUM_CONSTRUCTOR)
        }
        return true
    }
    if (let Some(memberAccess) <- (expr as MemberAccess)) {
        if (let Some(target) <- memberAccess.target) {
            return target.astKind != ASTKind.FUNC_DECL && !target.TestAttr(Attribute.ENUM_CONSTRUCTOR)
        }
        return true
    }
    if (let Some(subscriptExpr) <- (expr as SubscriptExpr)) {
        return !subscriptExpr.isTupleAccess
    }
    if (let Some(_) <- (expr as TupleLit)) {
        return false
    }
    return expr.TestAttr(Attribute.LEFT_VALUE) || expr.astKind == ASTKind.WILDCARD_EXPR
}

private func PreCheckCompoundAssign(leftTy: Ty, ae: AssignExpr): Bool {
    if (!ae.isCompound) {
        return true
    }
    if (IsCompoundBoolAssign(ae.op)) {
        return leftTy.IsBooleanSubType()
    }
    if (IsCompoundIntegerAssign(ae.op)) {
        return leftTy.IsIntegerSubType()
    }
    if (IsCompoundNumericAssign(ae.op)) {
        return leftTy.IsNumeric()
    }
    return false
}

private func CheckAssignRight(typeManager: TypeManager, leftTy: Ty, ae: AssignExpr): Bool {
    if (let Some(rightExpr) <- ae.rightExpr) {
        if (ae.op == TokenKind.EXP_ASSIGN) {
            let rightTy = SynExprShallow(typeManager, rightExpr)
            if (!Ty.IsTyCorrect(rightTy)) {
                return false
            }
            let i64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
            let u64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UINT64)
            let f64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_FLOAT64)
            if (typeManager.IsSubtype(leftTy, i64Ty)) {
                return typeManager.CheckTypeCompatibility(u64Ty, rightTy) != TypeCompatibility.INCOMPATIBLE
            }
            if (typeManager.IsSubtype(leftTy, f64Ty)) {
                return typeManager.CheckTypeCompatibility(i64Ty, rightTy) != TypeCompatibility.INCOMPATIBLE ||
                    typeManager.CheckTypeCompatibility(f64Ty, rightTy) != TypeCompatibility.INCOMPATIBLE
            }
            return false
        }
        return ChkExprShallow(typeManager, leftTy, rightExpr)
    }
    return false
}

private func SynMultipleAssignExpr(typeManager: TypeManager, ae: AssignExpr): Ty {
    if (let Some(desugar) <- ae.desugarExpr) {
        let desugarTy = SynExprShallow(typeManager, desugar)
        ae.SetTy(desugarTy)
    } else {
        ae.SetTy(TcUnitTy())
    }
    if (let Some(rightExpr) <- ae.rightExpr) {
        let _ = SynExprShallow(typeManager, rightExpr)
    }
    return TcTyOrInvalid(ae)
}

public func SynAssignExpr(typeManager: TypeManager, ae: AssignExpr): Ty {
    if (let Some(desugar) <- ae.desugarExpr) {
        if (let Some(leftValue) <- ae.leftValue) {
            if (leftValue.astKind == ASTKind.TUPLE_LIT) {
                return SynMultipleAssignExpr(typeManager, ae)
            }
        }
        if (let Some(desugarTy) <- desugar.GetTy()) {
            ae.SetTy(desugarTy)
            return desugarTy
        }
    }
    if (let None <- ae.leftValue) {
        return AssignInvalid(ae)
    }
    if (let None <- ae.rightExpr) {
        return AssignInvalid(ae)
    }
    let unitTy = TcUnitTy()
    ae.SetTy(unitTy)
    let leftExpr = ae.leftValue.getOrThrow()
    let rightExpr = ae.rightExpr.getOrThrow()
    if (leftExpr.astKind == ASTKind.WILDCARD_EXPR) {
        let rightTy = SynExprShallow(typeManager, rightExpr)
        if (Ty.IsTyCorrect(rightTy)) {
            let concreteRightTy = TcReplaceIdeal(typeManager, rightExpr)
            leftExpr.SetTy(concreteRightTy)
            return unitTy
        }
        return AssignInvalid(ae)
    }
    let leftTy = SynExprShallow(typeManager, leftExpr)
    if (!Ty.IsTyCorrect(leftTy)) {
        return AssignInvalid(ae)
    }
    let concreteLeftTy = Ty.GetPrimitiveUpperBound(TcReplaceIdeal(typeManager, leftExpr))
    if (!IsAssignableExpr(leftExpr)) {
        return AssignInvalid(ae)
    }
    if (!PreCheckCompoundAssign(concreteLeftTy, ae)) {
        let _ = SynExprShallow(typeManager, rightExpr)
        return AssignInvalid(ae)
    }
    if (!CheckAssignRight(typeManager, concreteLeftTy, ae)) {
        return AssignInvalid(ae)
    }
    ae.SetTy(unitTy)
    return unitTy
}

public func ChkAssignExpr(typeManager: TypeManager, target: Ty, ae: AssignExpr): Bool {
    let actualTy = SynAssignExpr(typeManager, ae)
    if (!Ty.IsTyCorrect(actualTy)) {
        return false
    }
    if (typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = AssignInvalid(ae)
    return false
}
