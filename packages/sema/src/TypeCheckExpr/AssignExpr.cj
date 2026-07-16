package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagSeverity
import cjcj::basic.Diagnostic
import cjcj::sema.*
import cjcj::sema.Desugar.*
import cjcj::utils.CJC_ASSERT

private func DiagCannotAssignToSubscript(diag: BasicDiagnosticEngine,
    se: SubscriptExpr, rightValue: Expr): Unit {
    let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_cannot_assign_to_subscript, se)
    CJC_ASSERT(se.baseExpr.isSome() && Ty.IsTyCorrect(se.baseExpr.getOrThrow().GetTy()))
    if (se.baseExpr.getOrThrow().GetTy().getOrThrow().IsExtendable()) {
        let indexParams = StringBuilder()
        for (idx in 0..se.indexExprs.size) {
            CJC_ASSERT(Ty.IsTyCorrect(se.indexExprs[idx].GetTy()))
            indexParams.append("index${idx}: ${se.indexExprs[idx].GetTy().getOrThrow().String()}, ")
        }
        builder.AddNote("you may want to implement 'operator func[](${indexParams.toString()}" +
            "value!: ${rightValue.GetTy().getOrThrow().String()})' for type '" +
            "${se.baseExpr.getOrThrow().GetTy().getOrThrow().String()}'")
    }
    builder.Emit()
}

private func MaySubscriptAssignOnlyBeOverload(baseExpr: Expr): Bool {
    return Ty.IsTyCorrect(baseExpr.GetTy()) && !baseExpr.GetTy().getOrThrow().IsBuiltin() &&
        !baseExpr.GetTy().getOrThrow().IsRange() && !baseExpr.GetTy().getOrThrow().IsTuple()
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

func IsAssignable(e: Expr, isCompound: Bool,
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

private func DiagnoseForSubscriptAssignExpr(typeManager: TypeManager, ctx: ASTContext,
    ae: AssignExpr, diags: Array<Diagnostic>, synthesizer: (SynPos, Expr) -> Ty,
    diag: BasicDiagnosticEngine): Unit {
    CJC_ASSERT(ae.leftValue.isSome())
    CJC_ASSERT(ae.rightExpr.isSome())
    let se = (ae.leftValue.getOrThrow() as SubscriptExpr).getOrThrow()
    let baseTarget = se.baseExpr.getOrThrow().GetTarget()
    var hasError = false
    for (diagnostic in diags) {
        if (diagnostic.diagSeverity == DiagSeverity.DS_ERROR) {
            hasError = true
        }
    }
    if (!hasError || baseTarget.isNone() || baseTarget.getOrThrow().astKind == ASTKind.VAR_DECL) {
        var areChildrenValid = true
        for (indexExpr in se.indexExprs) {
            areChildrenValid = Ty.IsTyCorrect(synthesizer(SynPos.EXPR_ARG, indexExpr)) &&
                ReplaceIdealTy(typeManager, indexExpr, diag: Some(diag)) && areChildrenValid
        }
        let rightExpr = ae.rightExpr.getOrThrow()
        areChildrenValid = Ty.IsTyCorrect(synthesizer(SynPos.EXPR_ARG, rightExpr)) &&
            ReplaceIdealTy(typeManager, rightExpr, diag: Some(diag)) && areChildrenValid
        if (areChildrenValid) {
            DiagCannotAssignToSubscript(diag, se, rightExpr)
        }
    } else {
        for (diagnostic2 in diags) {
            diag.Diagnose(diagnostic2).Emit()
        }
    }
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

func CheckMultipleAssignExpr(diag: BasicDiagnosticEngine, typeManager: TypeManager,
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

func PreCheckCompoundAssign(ae: AssignExpr, leftTy: Ty, diags: Array<Diagnostic>,
    synthesizer: (SynPos, Expr) -> Ty, diag: BasicDiagnosticEngine): Bool {
    if (ae.isCompound) {
        CJC_ASSERT(GetCompoundAssignBaseOp(ae.op) != TokenKind.ILLEGAL)
        let isInteger = leftTy.kind == TypeKind.TYPE_INT8 || leftTy.kind == TypeKind.TYPE_INT16 ||
            leftTy.kind == TypeKind.TYPE_INT32 || leftTy.kind == TypeKind.TYPE_INT64 ||
            leftTy.kind == TypeKind.TYPE_INT_NATIVE || leftTy.kind == TypeKind.TYPE_UINT8 ||
            leftTy.kind == TypeKind.TYPE_UINT16 || leftTy.kind == TypeKind.TYPE_UINT32 ||
            leftTy.kind == TypeKind.TYPE_UINT64 || leftTy.kind == TypeKind.TYPE_UINT_NATIVE ||
            leftTy.kind == TypeKind.TYPE_IDEAL_INT
        let isNumeric = isInteger || leftTy.kind == TypeKind.TYPE_FLOAT16 ||
            leftTy.kind == TypeKind.TYPE_FLOAT32 || leftTy.kind == TypeKind.TYPE_FLOAT64 ||
            leftTy.kind == TypeKind.TYPE_IDEAL_FLOAT
        let isSupported = match (ae.op) {
            case TokenKind.ADD_ASSIGN | TokenKind.SUB_ASSIGN | TokenKind.MUL_ASSIGN |
                TokenKind.EXP_ASSIGN | TokenKind.DIV_ASSIGN => isNumeric
            case TokenKind.MOD_ASSIGN | TokenKind.BITAND_ASSIGN | TokenKind.BITOR_ASSIGN |
                TokenKind.BITXOR_ASSIGN | TokenKind.LSHIFT_ASSIGN | TokenKind.RSHIFT_ASSIGN => isInteger
            case TokenKind.AND_ASSIGN | TokenKind.OR_ASSIGN => leftTy.kind == TypeKind.TYPE_BOOLEAN
            case _ => false
        }
        if (Ty.IsInitialTy(Some(leftTy)) || !isSupported) {
            let rightExpr = ae.rightExpr.getOrThrow()
            let _ = synthesizer(SynPos.EXPR_ARG, rightExpr)
            if (ae.ShouldDiagnose()) {
                for (diagnostic in diags) {
                    diag.Diagnose(diagnostic).Emit()
                }
                Diagnose(diag, ae, BasicDiagKind.sema_type_incompatible,
                    args: [BasicDiagArgument("compound assignment expression")]).Emit()
            }
            return false
        }
    }
    return true
}

func IsShiftAssignValid(ae: AssignExpr, leftTy: Ty, diag: BasicDiagnosticEngine): Bool {
    if (ae.op != TokenKind.LSHIFT_ASSIGN && ae.op != TokenKind.RSHIFT_ASSIGN) {
        return true
    }
    if (let Some(rightExpr) <- ae.rightExpr) {
        if (let Some(lit) <- (rightExpr as LitConstExpr)) {
            InitializeLitConstValue(lit)
            if (lit.constNumValue.asInt.IsNegativeNum()) {
                Diagnose(diag, rightExpr, BasicDiagKind.sema_negative_shift_count).Emit()
                return false
            }
            if (leftTy.IsIntegerSubType() && lit.constNumValue.asInt.GreaterThanOrEqualBitLen(leftTy.kind)) {
                Diagnose(diag, rightExpr, BasicDiagKind.sema_shift_count_overflow).Emit()
                return false
            }
        }
    }
    return true
}

func InferAssignExprCheckCaseOverloading(typeManager: TypeManager, ctx: ASTContext,
    ae: AssignExpr, diags: ArrayList<Diagnostic>, synthesizer: (SynPos, Expr) -> Ty,
    diag: BasicDiagnosticEngine): Option<Ty> {
    try (ds = DiagSuppressor(diag)) {
        if (ae.desugarExpr.isNone() && ae.leftValue.isSome() &&
            (ae.leftValue.getOrThrow() as SubscriptExpr).isSome()) {
            let se = (ae.leftValue.getOrThrow() as SubscriptExpr).getOrThrow()
            DesugarSubscriptOverloadExpr(ctx, ae)
            if (Ty.IsTyCorrect(synthesizer(SynPos.UNUSED, ae.desugarExpr.getOrThrow()))) {
                ds.ReportDiag()
                let desugar = ae.desugarExpr.getOrThrow()
                ae.SetTy(desugar.GetTy().getOrThrow())
                CJC_ASSERT((desugar as CallExpr).isSome())
                ReplaceTarget(ae, if (let Some(resolvedFunction) <-
                    (desugar as CallExpr).getOrThrow().resolvedFunction) {
                    Some(resolvedFunction)
                } else {
                    None
                })
                return Some(ae.GetTy().getOrThrow())
            }
            RecoverToAssignExpr(ae)
            if (se.baseExpr.isSome() && MaySubscriptAssignOnlyBeOverload(se.baseExpr.getOrThrow())) {
                let stashedDiags = ds.GetSuppressedDiag()
                DiagnoseForSubscriptAssignExpr(typeManager, ctx, ae, stashedDiags, synthesizer, diag)
                ds.ReportDiag()
                return Some(TcTyOrInvalid(ae))
            }
            ctx.DeleteDesugarExpr(ae)
        } else if (ae.isCompound) {
            DesugarOperatorOverloadExpr(ctx, ae)
            if (Ty.IsTyCorrect(synthesizer(SynPos.UNUSED, ae.desugarExpr.getOrThrow()))) {
                ds.ReportDiag()
                let desugarAssign = (ae.desugarExpr.getOrThrow() as AssignExpr).getOrThrow()
                ae.SetTy(desugarAssign.GetTy().getOrThrow())
                let callExpr = (desugarAssign.rightExpr.getOrThrow() as CallExpr).getOrThrow()
                ReplaceTarget(ae, if (let Some(resolvedFunction) <- callExpr.resolvedFunction) {
                    Some(resolvedFunction)
                } else {
                    None
                })
                let memberAccess = (callExpr.baseFunc.getOrThrow() as MemberAccess).getOrThrow()
                CJC_ASSERT(memberAccess.baseExpr.isSome() &&
                    Ty.IsTyCorrect(memberAccess.baseExpr.getOrThrow().GetTy()) && !callExpr.args.isEmpty() &&
                    callExpr.args[0].expr.isSome() && Ty.IsTyCorrect(callExpr.args[0].expr.getOrThrow().GetTy()))
                let baseOp = GetCompoundAssignBaseOp(ae.op)
                CJC_ASSERT(baseOp != TokenKind.ILLEGAL)
                if (IsBuiltinBinaryExpr(baseOp, memberAccess.baseExpr.getOrThrow().GetTy().getOrThrow(),
                    callExpr.args[0].expr.getOrThrow().GetTy().getOrThrow())) {
                    RecoverToAssignExpr(ae)
                }
                return Some(ae.GetTy().getOrThrow())
            }
            RecoverToAssignExpr(ae)
            ctx.DeleteDesugarExpr(ae)
        }
        diags.clear()
        for (diagnostic in ds.GetSuppressedDiag()) {
            diags.add(diagnostic)
        }
    }
    return None
}

extend TypeChecker {
}
