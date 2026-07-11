package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.Diagnostic
import cjcj::sema.*
import cjcj::sema.Desugar.*
import cjcj::utils.CJC_ASSERT

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

private func IsAssignableSubScriptExpr(se: SubscriptExpr, isCompound: Bool,
    diags: Array<Diagnostic>, diag: BasicDiagnosticEngine): Bool {
    let isOperatorOverload = se.desugarExpr.isSome()
    if (se.desugarExpr.isSome()) {
        RecoverToSubscriptExpr(se)
    }
    if (se.isTupleAccess) {
        for (diagnostic in diags) {
            diag.Diagnose(diagnostic).Emit()
        }
        DiagInvalidAssign(diag, se, "tuple element")
        return false
    }
    CJC_ASSERT(se.baseExpr.isSome() && !se.indexExprs.isEmpty())
    let diagKind = if (isCompound) {
        BasicDiagKind.sema_subscript_get_set_not_supported
    } else {
        BasicDiagKind.sema_subscript_set_not_supported
    }
    let indexTy = TypeManager.GetNonNullTy(se.indexExprs[0].GetTy() ?? TypeManager.GetInvalidTy())
    let baseTy = TypeManager.GetNonNullTy(se.baseExpr.getOrThrow().GetTy() ?? TypeManager.GetInvalidTy())
    if ((!baseTy.IsArray() && (let None <- (baseTy as VArrayTy))) ||
        (isOperatorOverload && !indexTy.IsInteger())) {
        for (diagnostic2 in diags) {
            diag.Diagnose(diagnostic2).Emit()
        }
        Diagnose(diag, se, diagKind,
            args: [BasicDiagArgument(baseTy.String()), BasicDiagArgument(indexTy.String())]).Emit()
        return false
    }
    return true
}

private func IsAssignable(e: Expr, isCompound: Bool,
    diags: Array<Diagnostic>, diag: BasicDiagnosticEngine): Bool {
    if (let Some(leftRef) <- (e as RefExpr)) {
        if (let Some(target) <- leftRef.ref.target) {
            if (target.astKind == ASTKind.FUNC_DECL) {
                for (diagnostic in diags) {
                    diag.Diagnose(diagnostic).Emit()
                }
                let targetName = if (target.TestAttr(Attribute.MACRO_FUNC)) {
                    "macro"
                } else if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    "enum constructor"
                } else {
                    "func"
                }
                DiagInvalidAssign(diag, e, targetName)
                return false
            }
        }
        if (leftRef.isThis && leftRef.isAlone) {
            for (diagnostic2 in diags) {
                diag.Diagnose(diagnostic2).Emit()
            }
            Diagnose(diag, e, BasicDiagKind.sema_invalid_assignment_to_this_expr).Emit()
            return false
        }
    } else if (let Some(memberAccess) <- (e as MemberAccess)) {
        if (let Some(memberTarget) <- memberAccess.target) {
            if (memberTarget.astKind == ASTKind.FUNC_DECL) {
                for (diagnostic3 in diags) {
                    diag.Diagnose(diagnostic3).Emit()
                }
                let memberTargetName = if (memberTarget.TestAttr(Attribute.MACRO_FUNC)) {
                    "macro"
                } else if (memberTarget.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
                    "enum constructor"
                } else {
                    "func"
                }
                DiagInvalidAssign(diag, e, memberTargetName)
                return false
            }
        }
        let isVArraySize = memberAccess.baseExpr.isSome() &&
            Ty.IsTyCorrect(memberAccess.baseExpr.getOrThrow().GetTy()) &&
            (memberAccess.baseExpr.getOrThrow().GetTy().getOrThrow() as VArrayTy).isSome() &&
            memberAccess.desugarExpr.isSome() &&
            memberAccess.desugarExpr.getOrThrow().astKind == ASTKind.LIT_CONST_EXPR
        if (isVArraySize) {
            for (diagnostic4 in diags) {
                diag.Diagnose(diagnostic4).Emit()
            }
            DiagCannotAssignToImmutable(diag, memberAccess, memberAccess)
            return false
        }
    } else if (let Some(subscriptExpr) <- (e as SubscriptExpr)) {
        if (!IsAssignableSubScriptExpr(subscriptExpr, isCompound, diags, diag)) {
            return false
        }
    }
    return true
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

private func CheckMatchOfDimensionAndTypes(diag: BasicDiagnosticEngine, typeManager: TypeManager,
    tysOfExpr: ArrayList<Option<Ty>>, indexOfExprTys: Box<Int64>, tupleLit: TupleLit,
    tupleTy: TupleTy, rightExpr: Expr): Bool {
    if (tupleLit.children.size != tupleTy.typeArgs.size) {
        DiagInvalidMultipleAssignExpr(diag, tupleLit, rightExpr,
            "the tuple has ${tupleLit.children.size}-elements, found one with ${tupleTy.typeArgs.size}-elements")
        return false
    }
    var indexOfRightTy: Int64 = 0
    for (leftValue in tupleLit.children) {
        let rightTy = tupleTy.typeArgs[indexOfRightTy]
        indexOfRightTy++
        let leftDiagInfo = if (Ty.IsTyCorrect(leftValue.GetTy()) && !leftValue.IsInvalid()) {
            "'${leftValue.GetTy().getOrThrow().String()}'"
        } else {
            "it"
        }
        if (let Some(nestedTupleLit) <- (leftValue as TupleLit)) {
            if (let None <- (rightTy as TupleTy)) {
                DiagInvalidMultipleAssignExpr(diag, leftValue, rightExpr,
                    "can not assign ${leftDiagInfo} with '${rightExpr.GetTy().getOrThrow().String()}'")
                return false
            }
            let success = CheckMatchOfDimensionAndTypes(diag, typeManager, tysOfExpr, indexOfExprTys,
                nestedTupleLit, (rightTy as TupleTy).getOrThrow(), rightExpr)
            if (!success) {
                return false
            }
            continue
        }
        CJC_ASSERT(indexOfExprTys.value < tysOfExpr.size)
        let typeMatch = (Ty.IsTyCorrect(leftValue.GetTy()) &&
            typeManager.IsSubtype(rightTy, leftValue.GetTy().getOrThrow())) ||
            Ty.IsTyCorrect(tysOfExpr[indexOfExprTys.value])
        indexOfExprTys.value++
        if (!typeMatch) {
            DiagInvalidMultipleAssignExpr(diag, leftValue, rightExpr,
                "can not assign ${leftDiagInfo} with '${rightTy.String()}'")
            return false
        }
    }
    return true
}

private func CheckMultipleAssignExpr(diag: BasicDiagnosticEngine, typeManager: TypeManager,
    assignExpr: AssignExpr): Unit {
    let tupleLit = (assignExpr.leftValue.getOrThrow() as TupleLit).getOrThrow()
    let rightExpr = assignExpr.rightExpr.getOrThrow()
    CJC_ASSERT(Ty.IsTyCorrect(rightExpr.GetTy()))
    let tysOfDesugarExpr = ArrayList<Option<Ty>>()
    let indexOfDesugaredTys = Box<Int64>(0)
    let block = (assignExpr.desugarExpr.getOrThrow() as Block).getOrThrow()
    for (node in block.body) {
        if (node.astKind == ASTKind.VAR_DECL) {
            continue
        }
        tysOfDesugarExpr.add(node.GetTy())
    }
    if (let None <- (rightExpr.GetTy().getOrThrow() as TupleTy)) {
        let leftDiagInfo = if (Ty.IsTyCorrect(tupleLit.GetTy()) && !tupleLit.IsInvalid()) {
            "'${tupleLit.GetTy().getOrThrow().String()}'"
        } else {
            "it"
        }
        DiagInvalidMultipleAssignExpr(diag, tupleLit, rightExpr,
            "can not assign ${leftDiagInfo} with '${rightExpr.GetTy().getOrThrow().String()}'")
        assignExpr.SetTy(TypeManager.GetInvalidTy())
        return
    }
    let success = CheckMatchOfDimensionAndTypes(diag, typeManager, tysOfDesugarExpr, indexOfDesugaredTys,
        tupleLit, (rightExpr.GetTy().getOrThrow() as TupleTy).getOrThrow(), rightExpr)
    if (!success) {
        assignExpr.SetTy(TypeManager.GetInvalidTy())
    }
}

private func PreCheckCompoundAssign(leftTy: Ty, ae: AssignExpr,
    diag: Option<BasicDiagnosticEngine>): Bool {
    if (!ae.isCompound) {
        return true
    }
    var isSupported = false
    if (IsCompoundBoolAssign(ae.op)) {
        isSupported = leftTy.IsBooleanSubType()
    } else if (IsCompoundIntegerAssign(ae.op)) {
        isSupported = leftTy.IsIntegerSubType()
    } else if (IsCompoundNumericAssign(ae.op)) {
        isSupported = leftTy.IsNumeric()
    }
    if (isSupported) {
        return true
    }
    if (ae.ShouldDiagnose()) {
        if (let Some(diagValue) <- diag) {
            Diagnose(diagValue, ae, BasicDiagKind.sema_type_incompatible,
                args: [BasicDiagArgument("compound assignment expression")]).Emit()
        }
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
        ReplaceTarget(ae, callExpr.resolvedFunction)
        return
    }
    if (let Some(assignExpr) <- (desugar as AssignExpr)) {
        if (let Some(rightExpr) <- assignExpr.rightExpr) {
            if (let Some(callExpr2) <- (rightExpr as CallExpr)) {
                ReplaceTarget(ae, callExpr2.resolvedFunction)
            }
        }
    }
}

private func TrySynAssignOverload(typeManager: TypeManager, ae: AssignExpr,
    ctx!: Option<ASTContext> = None, synthesizer!: Option<(Expr) -> Ty> = None): Option<Ty> {
    if (let Some(leftValue) <- ae.leftValue) {
        if (let Some(_) <- (leftValue as SubscriptExpr)) {
            DesugarSubscriptOverloadExpr(ae)
            if (let Some(desugar) <- ae.desugarExpr) {
                let desugarTy = if (let Some(syn) <- synthesizer) {
                    syn(desugar)
                } else {
                    SynExprShallow(typeManager, desugar, ctx: ctx)
                }
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
            let desugarTy2 = if (let Some(syn2) <- synthesizer) {
                syn2(desugar2)
            } else {
                SynExprShallow(typeManager, desugar2, ctx: ctx)
            }
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

private func SynMultipleAssignExpr(typeManager: TypeManager, ae: AssignExpr,
    diag: Option<BasicDiagnosticEngine>): Ty {
    if (let Some(desugar) <- ae.desugarExpr) {
        let desugarTy = SynExprShallow(typeManager, desugar)
        ae.SetTy(desugarTy)
    } else {
        ae.SetTy(TcUnitTy())
    }
    if (let Some(rightExpr) <- ae.rightExpr) {
        let rightTy = SynExprShallow(typeManager, rightExpr)
        if (Ty.IsTyCorrect(rightTy)) {
            rightExpr.SetTy(TcReplaceIdeal(typeManager, rightExpr))
            if (let Some(diagValue) <- diag) {
                try (ds = DiagSuppressor(diagValue)) {
                    let _ = SynExprShallow(typeManager, ae.leftValue.getOrThrow(), diag: diag)
                }
                CheckMultipleAssignExpr(diagValue, typeManager, ae)
            }
        } else {
            return TcTyOrInvalid(ae)
        }
    }
    return TcTyOrInvalid(ae)
}

public func SynAssignExpr(typeManager: TypeManager, ae: AssignExpr,
    rightChecker!: Option<AssignRightChecker> = None, ctx!: Option<ASTContext> = None,
    synthesizer!: Option<(Expr) -> Ty> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(desugar) <- ae.desugarExpr) {
        if (let Some(leftValue) <- ae.leftValue) {
            if (leftValue.astKind == ASTKind.TUPLE_LIT) {
                return SynMultipleAssignExpr(typeManager, ae, diag)
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
    if (let Some(overloadTy) <- TrySynAssignOverload(typeManager, ae, ctx: ctx, synthesizer: synthesizer)) {
        return overloadTy
    }
    let unitTy = TcUnitTy()
    ae.SetTy(unitTy)
    let leftExpr = ae.leftValue.getOrThrow()
    let rightExpr = ae.rightExpr.getOrThrow()
    if (leftExpr.astKind == ASTKind.TUPLE_LIT) {
        return SynMultipleAssignExpr(typeManager, ae, diag)
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
    if (!PreCheckCompoundAssign(concreteLeftTy, ae, diag)) {
        let _ = SynExprShallow(typeManager, rightExpr)
        return AssignInvalid(ae)
    }
    if (!IsAssignableExpr(leftExpr)) {
        return AssignInvalid(ae)
    }
    if (!ae.isCompound && leftExpr.TyKind() == TypeKind.TYPE_RUNE && IsSingleRuneStringLiteral(rightExpr)) {
        rightExpr.SetTy(leftTy)
    } else if (!ae.isCompound && leftExpr.TyKind() == TypeKind.TYPE_UINT8 && IsSingleByteStringLiteral(rightExpr)) {
        rightExpr.SetTy(leftTy)
        if (let Some(lit) <- (rightExpr as LitConstExpr)) {
            let _ = ChkLitConstExprRange(lit)
        }
    } else if (!CheckAssignRight(typeManager, concreteLeftTy, ae, rightChecker)) {
        return AssignInvalid(ae)
    }
    if (!IsShiftAssignValid(ae, concreteLeftTy)) {
        return AssignInvalid(ae)
    }
    ae.SetTy(unitTy)
    return unitTy
}

public func ChkAssignExpr(typeManager: TypeManager, target: Ty, ae: AssignExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let actualTy = SynAssignExpr(typeManager, ae, diag: diag)
    if (!Ty.IsTyCorrect(actualTy)) {
        return false
    }
    if (typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = AssignInvalid(ae)
    return false
}
