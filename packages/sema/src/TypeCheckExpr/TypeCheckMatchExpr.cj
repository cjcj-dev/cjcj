package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::sema.*
import cjcj::sema.Desugar.*

// C++ src/Sema/TypeCheckMatchExpr.cpp:45-56 CheckMatchExprSetTy.
private func CheckMatchExprSetTy(me: MatchExpr, target: Ty, typeManager: TypeManager,
    matchCaseTys: TySet): Unit {
    if (matchCaseTys.Contains(target)) {
        me.SetTy(target)
        return
    }
    let joinRes = JoinAsVisibleTy(typeManager, matchCaseTys, curFile: me.curFile)
    match (joinRes) {
        case ErrOrTy.TY(joinedTy) => me.SetTy(joinedTy)
        case ErrOrTy.ERR(_) => me.SetTy(target)
    }
}

extend TypeChecker {
    // C++ src/Sema/TypeCheckMatchExpr.cpp:60-66 SynMatchExpr.
    func SynMatchExpr(ctx: ASTContext, me: MatchExpr): Ty {
        if (let Some(selector) <- me.selector) {
            let _ = Synthesize(ctx, SynPos.NONE, selector)
            let _ = ReplaceIdealTy(impl.typeManager, selector, diag: impl.diag)
            return SynMatchExprHasSelector(impl.typeManager, ctx, impl.diag, me,
                exprChecker: Some({ target: Ty, expr: Expr => Check(ctx, target, expr) }),
                exprSynthesizer: Some({ expr: Expr => Synthesize(ctx, SynPos.NONE, expr) }),
                desugarCallExpr: Some({ callExpr: CallExpr => DesugarCallExpr(callExpr) }))
        }
        return SynMatchExprNoSelector(ctx, me)
    }

    // C++ src/Sema/TypeCheckMatchExpr.cpp:68-74 ChkMatchExpr.
    func ChkMatchExpr(ctx: ASTContext, target: Ty, me: MatchExpr): Bool {
        if (let Some(selector) <- me.selector) {
            let _ = Synthesize(ctx, SynPos.EXPR_ARG, selector)
            return ChkMatchExprHasSelector(impl.typeManager, ctx, impl.diag, target, me,
                exprChecker: Some({ target2: Ty, expr: Expr => Check(ctx, target2, expr) }),
                desugarCallExpr: Some({ callExpr: CallExpr => DesugarCallExpr(callExpr) }))
        }
        return ChkMatchExprNoSelector(ctx, target, me)
    }

    // C++ src/Sema/TypeCheckMatchExpr.cpp:285-299 SynMatchCaseNoSelector.
    func SynMatchCaseNoSelector(ctx: ASTContext, mco: MatchCaseOther): Ty {
        let matchExpr = mco.matchExpr.getOrThrow()
        if (let Some(wildcard) <- (matchExpr as WildcardExpr)) {
            wildcard.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
        } else if (!Check(ctx, TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN), matchExpr)) {
            matchExpr.SetTy(TypeManager.GetInvalidTy())
        }

        mco.SetTy(Synthesize(ctx, SynPos.EXPR_ARG, mco.exprOrDecls.getOrThrow()))
        return mco.GetTy().getOrThrow()
    }

    // C++ src/Sema/TypeCheckMatchExpr.cpp:423-445 ChkMatchCaseNoSelector.
    func ChkMatchCaseNoSelector(ctx: ASTContext, target: Ty, mco: MatchCaseOther): Bool {
        var ret = true
        let matchExpr = mco.matchExpr.getOrThrow()
        if (let Some(wildcard) <- (matchExpr as WildcardExpr)) {
            wildcard.SetTy(TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN))
        } else if (!Check(ctx, TypeManager.GetPrimitiveTy(TypeKind.TYPE_BOOLEAN), matchExpr)) {
            matchExpr.SetTy(TypeManager.GetInvalidTy())
            ret = false
        }

        let exprOrDecls = mco.exprOrDecls.getOrThrow()
        if (Check(ctx, target, exprOrDecls)) {
            mco.SetTy(exprOrDecls.GetTy().getOrThrow())
        } else {
            mco.SetTy(TypeManager.GetInvalidTy())
            ret = false
        }
        return ret
    }

    // C++ src/Sema/TypeCheckMatchExpr.cpp:189-222 SynMatchExprNoSelector.
    func SynMatchExprNoSelector(ctx: ASTContext, me: MatchExpr): Ty {
        let matchCaseTys = TySet()
        var hasInvalidCase = false
        for (mco in me.matchCaseOthers) {
            if (!Ty.IsTyCorrect(SynMatchCaseNoSelector(ctx, mco))) {
                hasInvalidCase = true
            } else {
                matchCaseTys.Add(mco.GetTy().getOrThrow())
            }
        }
        if (hasInvalidCase) {
            me.SetTy(TypeManager.GetInvalidTy())
            return me.GetTy().getOrThrow()
        }

        let joinRes = JoinAsVisibleTy(impl.typeManager, matchCaseTys, curFile: me.curFile)
        let (optErrs, joinedMeTy) = SetJoinedType(me.GetTy() ?? TypeManager.GetInvalidTy(), joinRes)
        me.SetTy(joinedMeTy)
        if (let Some(errMsg) <- optErrs) {
            if (let Some(diag) <- impl.diag) {
                let builder = Diagnose(diag, me, BasicDiagKind.sema_type_incompatible,
                    args: [BasicDiagArgument("MatchCase")])
                builder.AddNote(errMsg)
                builder.Emit()
            }
        }

        if (!CheckMatchExprNoSelectorExhaustiveness(me, diag: impl.diag)) {
            me.SetTy(TypeManager.GetInvalidTy())
            return me.GetTy().getOrThrow()
        }
        return me.GetTy().getOrThrow()
    }

    // C++ src/Sema/TypeCheckMatchExpr.cpp:262-283 ChkMatchExprNoSelector.
    func ChkMatchExprNoSelector(ctx: ASTContext, target: Ty, me: MatchExpr): Bool {
        var isWellTyped = true
        let matchCaseTys = TySet()
        for (mco in me.matchCaseOthers) {
            if (!ChkMatchCaseNoSelector(ctx, target, mco)) {
                isWellTyped = false
            } else {
                matchCaseTys.Add(mco.GetTy().getOrThrow())
            }
        }

        if (isWellTyped) {
            CheckMatchExprSetTy(me, target, impl.typeManager, matchCaseTys)
            if (!CheckMatchExprNoSelectorExhaustiveness(me, diag: impl.diag)) {
                isWellTyped = false
            }
        }
        me.SetTy(if (isWellTyped) { me.GetTy().getOrThrow() } else { TypeManager.GetInvalidTy() })
        return isWellTyped
    }
}
