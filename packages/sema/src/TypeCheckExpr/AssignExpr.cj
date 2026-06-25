package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*
import cangjie_compiler::sema.Desugar.*

public func SelfhostPortStatus_TypeCheckExpr_AssignExpr(): Bool {
    return true
}

public type AssignRightChecker = (Ty, Expr) -> Bool

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
    if (let Some(parenExpr) <- (expr as ParenExpr)) {
        if (let Some(innerExpr) <- parenExpr.expr) {
            return IsAssignableExpr(innerExpr)
        }
        return false
    }
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
    return expr.TestAttr(Attribute.LEFT_VALUE) || expr.astKind == ASTKind.WILDCARD_EXPR
}

private func CheckSingleAssignTarget(typeManager: TypeManager, leftExpr: Expr, rightTy: Ty): Bool {
    if (leftExpr.astKind == ASTKind.WILDCARD_EXPR) {
        leftExpr.SetTy(rightTy)
        return true
    }
    let leftTy = SynExprShallow(typeManager, leftExpr)
    if (!Ty.IsTyCorrect(leftTy)) {
        return false
    }
    let concreteLeftTy = Ty.GetPrimitiveUpperBound(TcReplaceIdeal(typeManager, leftExpr))
    return IsAssignableExpr(leftExpr) &&
        typeManager.CheckTypeCompatibility(concreteLeftTy, rightTy) != TypeCompatibility.INCOMPATIBLE
}

private func CheckMultipleAssignTarget(typeManager: TypeManager, leftExpr: Expr, rightTy: Ty): Bool {
    if (let Some(parenExpr) <- (leftExpr as ParenExpr)) {
        if (let Some(innerExpr) <- parenExpr.expr) {
            let ok = CheckMultipleAssignTarget(typeManager, innerExpr, rightTy)
            parenExpr.SetTy(TcTyOrInvalid(innerExpr))
            return ok
        }
        return false
    }
    if (let Some(tupleLit) <- (leftExpr as TupleLit)) {
        if (let Some(tupleTy) <- (rightTy as TupleTy)) {
            if (tupleLit.children.size != tupleTy.typeArgs.size) {
                tupleLit.SetTy(TypeManager.GetInvalidTy())
                return false
            }
            var ok = true
            for (idx in 0..tupleLit.children.size) {
                ok = CheckMultipleAssignTarget(typeManager, tupleLit.children[idx], tupleTy.typeArgs[idx]) && ok
            }
            if (ok) {
                tupleLit.SetTy(tupleTy)
            } else {
                tupleLit.SetTy(TypeManager.GetInvalidTy())
            }
            return ok
        }
        tupleLit.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return CheckSingleAssignTarget(typeManager, leftExpr, rightTy)
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

private func CheckAssignRight(typeManager: TypeManager, leftTy: Ty, ae: AssignExpr,
    rightChecker: Option<AssignRightChecker>): Bool {
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
        if (let Some(checker) <- rightChecker) {
            return checker(leftTy, rightExpr)
        }
        return ChkExprShallow(typeManager, leftTy, rightExpr)
    }
    return false
}

private func IsShiftAssignValid(ae: AssignExpr, leftTy: Ty): Bool {
    if (ae.op != TokenKind.LSHIFT_ASSIGN && ae.op != TokenKind.RSHIFT_ASSIGN) {
        return true
    }
    if (let Some(rightExpr) <- ae.rightExpr) {
        if (let Some(lit) <- (rightExpr as LitConstExpr)) {
            InitializeLitConstValue(lit)
            if (lit.constNumValue.asInt.IsNegativeNum()) {
                return false
            }
            if (leftTy.IsIntegerSubType() && lit.constNumValue.asInt.GreaterThanOrEqualBitLen(leftTy.kind)) {
                return false
            }
        }
    }
    return true
}

private func PropagateAssignDesugarTarget(ae: AssignExpr, desugar: Expr): Unit {
    if (let Some(callExpr) <- (desugar as CallExpr)) {
        if (let Some(resolved) <- callExpr.resolvedFunction) {
            ReplaceTarget(ae, Some(resolved))
        }
        return
    }
    if (let Some(assignExpr) <- (desugar as AssignExpr)) {
        if (let Some(rightExpr) <- assignExpr.rightExpr) {
            if (let Some(callExpr2) <- (rightExpr as CallExpr)) {
                if (let Some(resolved2) <- callExpr2.resolvedFunction) {
                    ReplaceTarget(ae, Some(resolved2))
                }
            }
        }
    }
}

private func TrySynAssignOverload(typeManager: TypeManager, ae: AssignExpr): Option<Ty> {
    if (let Some(leftValue) <- ae.leftValue) {
        if (let Some(_) <- (leftValue as SubscriptExpr)) {
            DesugarSubscriptOverloadExpr(ae)
            if (let Some(desugar) <- ae.desugarExpr) {
                let desugarTy = SynExprShallow(typeManager, desugar)
                if (Ty.IsTyCorrect(desugarTy)) {
                    PropagateAssignDesugarTarget(ae, desugar)
                    ae.SetTy(desugarTy)
                    return Some(desugarTy)
                }
                RecoverToAssignExpr(ae)
            }
            return None
        }
    }
    if (ae.isCompound) {
        DesugarOperatorOverloadExpr(ae)
        if (let Some(desugar2) <- ae.desugarExpr) {
            let desugarTy2 = SynExprShallow(typeManager, desugar2)
            if (Ty.IsTyCorrect(desugarTy2)) {
                PropagateAssignDesugarTarget(ae, desugar2)
                ae.SetTy(desugarTy2)
                return Some(desugarTy2)
            }
            RecoverToAssignExpr(ae)
        }
    }
    return None
}

private func SynMultipleAssignExpr(typeManager: TypeManager, ae: AssignExpr): Ty {
    if (let Some(desugar) <- ae.desugarExpr) {
        let desugarTy = SynExprShallow(typeManager, desugar)
        ae.SetTy(desugarTy)
    } else {
        ae.SetTy(TcUnitTy())
    }
    if (let Some(rightExpr) <- ae.rightExpr) {
        let rightTy = SynExprShallow(typeManager, rightExpr)
        if (Ty.IsTyCorrect(rightTy)) {
            if (let Some(leftValue) <- ae.leftValue) {
                if (!CheckMultipleAssignTarget(typeManager, leftValue, TcReplaceIdeal(typeManager, rightExpr))) {
                    return AssignInvalid(ae)
                }
            }
        } else {
            return AssignInvalid(ae)
        }
    }
    return TcTyOrInvalid(ae)
}

public func SynAssignExpr(typeManager: TypeManager, ae: AssignExpr,
    rightChecker!: Option<AssignRightChecker> = None): Ty {
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
    if (let Some(overloadTy) <- TrySynAssignOverload(typeManager, ae)) {
        return overloadTy
    }
    let unitTy = TcUnitTy()
    ae.SetTy(unitTy)
    let leftExpr = ae.leftValue.getOrThrow()
    let rightExpr = ae.rightExpr.getOrThrow()
    if (leftExpr.astKind == ASTKind.TUPLE_LIT) {
        return SynMultipleAssignExpr(typeManager, ae)
    }
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
    if (!PreCheckCompoundAssign(concreteLeftTy, ae)) {
        let _ = SynExprShallow(typeManager, rightExpr)
        return AssignInvalid(ae)
    }
    if (!IsAssignableExpr(leftExpr)) {
        return AssignInvalid(ae)
    }
    if (!CheckAssignRight(typeManager, concreteLeftTy, ae, rightChecker)) {
        return AssignInvalid(ae)
    }
    if (!IsShiftAssignValid(ae, concreteLeftTy)) {
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
