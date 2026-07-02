package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagArgument as BasicDiagArgument
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::sema.*
import cangjie_compiler::utils.CJC_ASSERT

private func LoopInvalid(expr: Expr): Ty {
    return TcInvalid(expr)
}

private func GetIterableTy(typeManager: TypeManager, ctx: ASTContext, ty: Ty): Ty {
    if (ty.IsNothing()) {
        return TypeManager.GetInvalidTy()
    }
    let iterableInterface = GetCoreDecl(ctx, "Iterable")
    if (let Some(genTy) <- (ty as GenericsTy)) {
        if (genTy.isPlaceholder) {
            let iterableTy = iterableInterface.getOrThrow().GetTy().getOrThrow()
            return typeManager.ConstrainByCtor(genTy, iterableTy) ?? TypeManager.GetInvalidTy()
        }
    }
    if (let Some(iterableDecl) <- iterableInterface) {
        let iterableTy = iterableDecl.GetTy().getOrThrow()
        let promotedTys = Promotion(typeManager).Promote(ty, iterableTy)
        CJC_ASSERT(promotedTys.values.size <= 1)
        if (promotedTys.values.isEmpty()) {
            return TypeManager.GetInvalidTy()
        }
        return promotedTys.values[0]
    }
    return TypeManager.GetInvalidTy()
}

public func SynWhileExpr(typeManager: TypeManager, we: WhileExpr, ctx!: Option<ASTContext> = None): Ty {
    var ok = true
    if (let Some(condExpr) <- we.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr, ctx: ctx) && ok
    } else {
        ok = false
    }
    if (let Some(body) <- we.body) {
        let bodyTy = SynBlock(typeManager, body, pos: SynPos.UNUSED)
        if (Ty.IsTyCorrect(bodyTy)) {
            body.SetTy(TcUnitTy())
        } else {
            ok = false
        }
    } else {
        ok = false
    }
    if (ok) {
        let unitTy = TcUnitTy()
        we.SetTy(unitTy)
        return unitTy
    }
    return LoopInvalid(we)
}

public func ChkWhileExpr(typeManager: TypeManager, target: Ty, we: WhileExpr, ctx!: Option<ASTContext> = None): Bool {
    let actualTy = SynWhileExpr(typeManager, we, ctx: ctx)
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LoopInvalid(we)
    return false
}

public func SynDoWhileExpr(typeManager: TypeManager, dwe: DoWhileExpr, ctx!: Option<ASTContext> = None): Ty {
    var ok = true
    if (let Some(body) <- dwe.body) {
        let bodyTy = SynBlock(typeManager, body, pos: SynPos.UNUSED)
        if (Ty.IsTyCorrect(bodyTy)) {
            body.SetTy(TcUnitTy())
        } else {
            ok = false
        }
    } else {
        ok = false
    }
    if (let Some(condExpr) <- dwe.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr, ctx: ctx) && ok
    } else {
        ok = false
    }
    if (ok) {
        let unitTy = TcUnitTy()
        dwe.SetTy(unitTy)
        return unitTy
    }
    return LoopInvalid(dwe)
}

public func ChkDoWhileExpr(typeManager: TypeManager, target: Ty, dwe: DoWhileExpr, ctx!: Option<ASTContext> = None): Bool {
    let actualTy = SynDoWhileExpr(typeManager, dwe, ctx: ctx)
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LoopInvalid(dwe)
    return false
}

public func SynForInExpr(typeManager: TypeManager, fie: ForInExpr, ctx: ASTContext,
    synthesizer!: Option<(ASTContext, SynPos, Node) -> Ty> = None,
    checker!: Option<(ASTContext, Ty, Expr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    var ok = true
    var elementTy: Ty = TypeManager.GetInvalidTy()
    if (let Some(inExpression) <- fie.inExpression) {
        let inTy = if (let Some(realSynthesizer) <- synthesizer) {
            realSynthesizer(ctx, SynPos.EXPR_ARG, inExpression)
        } else {
            SynExprShallow(typeManager, inExpression, ctx: Some(ctx), diag: diag)
        }
        ok = Ty.IsTyCorrect(inTy) && ReplaceIdealTy(typeManager, inExpression, diag: diag) && ok
        if (let Some(realInTy) <- inExpression.GetTy()) {
            let iterableTy = GetIterableTy(typeManager, ctx, realInTy)
            if (Ty.IsTyCorrect(iterableTy)) {
                CJC_ASSERT(!iterableTy.typeArgs.isEmpty())
                elementTy = iterableTy.typeArgs[0]
            } else {
                ok = false
                if (!CanSkipDiag(inExpression)) {
                    if (let Some(diagValue) <- diag) {
                        diagValue.Diagnose(inExpression.begin, inExpression.end,
                            BasicDiagKind.sema_expr_in_forin_must_has_iterator,
                            args: [BasicDiagArgument(Ty.ToString(inExpression.GetTy()))]).Emit()
                    }
                }
            }
        } else {
            ok = false
            if (!CanSkipDiag(inExpression)) {
                if (let Some(diagValue2) <- diag) {
                    diagValue2.Diagnose(inExpression.begin, inExpression.end,
                        BasicDiagKind.sema_expr_in_forin_must_has_iterator,
                        args: [BasicDiagArgument(Ty.ToString(inExpression.GetTy()))]).Emit()
                }
            }
        }
    } else {
        ok = false
    }
    if (let Some(pattern) <- fie.pattern) {
        ok = ChkPattern(typeManager, ctx, elementTy, pattern, isPatternInMatch: false, diag: diag) && ok
    } else {
        ok = false
    }
    if (let Some(patternGuard) <- fie.patternGuard) {
        let guardOk = if (let Some(realChecker) <- checker) {
            realChecker(ctx, TcBoolTy(), patternGuard)
        } else {
            ChkExprShallow(typeManager, TcBoolTy(), patternGuard, ctx: Some(ctx), diag: diag)
        }
        if (!guardOk) {
            ok = false
            if (!CanSkipDiag(patternGuard)) {
                if (let Some(diagValue3) <- diag) {
                    diagValue3.Diagnose(patternGuard.begin, patternGuard.end,
                        BasicDiagKind.sema_wrong_forin_guard).Emit()
                }
            }
        }
    }
    if (let Some(body) <- fie.body) {
        let bodyTy = if (let Some(realSynthesizer2) <- synthesizer) {
            realSynthesizer2(ctx, SynPos.UNUSED, body)
        } else {
            SynBlock(typeManager, body, pos: SynPos.UNUSED, diag: diag)
        }
        if (Ty.IsTyCorrect(bodyTy)) {
            body.SetTy(TcUnitTy())
        } else {
            ok = false
        }
    } else {
        ok = false
    }
    if (let Some(pattern) <- fie.pattern) {
        if (!IsIrrefutablePattern(pattern)) {
            ok = false
            if (let Some(diagValue4) <- diag) {
                diagValue4.Diagnose(fie.begin, fie.end,
                    BasicDiagKind.sema_forin_pattern_must_be_irrefutable).Emit()
            }
        }
    }
    if (ok) {
        let unitTy = TcUnitTy()
        fie.SetTy(unitTy)
        return unitTy
    }
    return LoopInvalid(fie)
}

public func ChkForInExpr(typeManager: TypeManager, target: Ty, fie: ForInExpr, ctx: ASTContext,
    synthesizer!: Option<(ASTContext, SynPos, Node) -> Ty> = None,
    checker!: Option<(ASTContext, Ty, Expr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    var isWellTyped = typeManager.IsSubtype(TcUnitTy(), target)
    if (!isWellTyped) {
        if (let Some(diagValue) <- diag) {
            DiagMismatchedTypesWithFoundTy(diagValue, fie, target, TcUnitTy())
        }
    }
    isWellTyped = Ty.IsTyCorrect(SynForInExpr(typeManager, fie, ctx, synthesizer: synthesizer,
        checker: checker, diag: diag)) && isWellTyped
    if (!isWellTyped) {
        let _ = LoopInvalid(fie)
    }
    return isWellTyped
}
