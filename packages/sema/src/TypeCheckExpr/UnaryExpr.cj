package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::sema.*
import cjcj::sema.Desugar.*

private func GetNonParenExpr(expr: Expr): Expr {
    var current = expr
    var keepGoing = true
    while (keepGoing) {
        if (let Some(parenExpr) <- (current as ParenExpr)) {
            if (let Some(innerExpr) <- parenExpr.expr) {
                current = innerExpr
            } else {
                keepGoing = false
            }
        } else {
            keepGoing = false
        }
    }
    return current
}

public func GetLeafUnaryExpr(ue: UnaryExpr): UnaryExpr {
    var leaf = ue
    var keepGoing = true
    while (keepGoing) {
        if (let Some(innerExpr) <- leaf.expr) {
            let bareExpr = GetNonParenExpr(innerExpr)
            if (let Some(nextLeaf) <- (bareExpr as UnaryExpr)) {
                if (let Some(_) <- nextLeaf.desugarExpr) {
                    keepGoing = false
                } else {
                    leaf = nextLeaf
                }
            } else {
                keepGoing = false
            }
        } else {
            keepGoing = false
        }
    }
    return leaf
}

extend TypeChecker {
    private func DiagnoseForUnaryExprWithTarget(ctx: ASTContext, ue: UnaryExpr, target: Ty): Unit {
        let leaf = GetLeafUnaryExpr(ue)
        if ((let Some(operand) <- leaf.expr) && Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, operand)) &&
            ReplaceIdealTy(impl.typeManager, operand, diag: impl.diag)) {
            if (let Some(diag) <- impl.diag) {
                DiagInvalidUnaryExprWithTarget(diag, leaf, target)
            }
        }
    }

    private func DiagnoseForUnaryExpr(ctx: ASTContext, ue: UnaryExpr): Unit {
        let leaf = GetLeafUnaryExpr(ue)
        if ((let Some(operand) <- leaf.expr) && Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, operand)) &&
            ReplaceIdealTy(impl.typeManager, operand, diag: impl.diag)) {
            if (let Some(diag) <- impl.diag) {
                DiagInvalidUnaryExpr(diag, leaf)
            }
        }
    }

    private func SynBuiltinUnaryExpr(ctx: ASTContext, ue: UnaryExpr): Ty {
        if (let None <- ue.expr) {
            return TypeManager.GetInvalidTy()
        }
        let ty = Synthesize(ctx, SynPos.EXPR_ARG, ue.expr.getOrThrow())
        if (!Ty.IsTyCorrect(ty) || !IsUnaryOperator(ue.op)) {
            return TypeManager.GetInvalidTy()
        }
        let typeCandidates = GetUnaryOpTypeCandidates(ue.op)
        if (let Some(tv) <- (ty as GenericsTy)) {
            if (tv.isPlaceholder) {
                match (impl.PickConstaintFromTys(tv, TypeMapToTys(typeCandidates, true), true)) {
                    case MatchResult.UNIQUE =>
                        let result = impl.typeManager.TryGreedySubst(tv)
                        ue.SetTy(result)
                        return result
                    case MatchResult.AMBIGUOUS => return TypeManager.GetInvalidTy()
                    case MatchResult.NONE => return TypeManager.GetInvalidTy()
                }
            }
        }
        for (typeCandidate in typeCandidates) {
            let primitiveTy = TypeManager.GetPrimitiveTy(typeCandidate[1])
            if (impl.typeManager.IsSubtype(ty, primitiveTy)) {
                ue.SetTy(ty)
                return ty
            }
        }
        return TypeManager.GetInvalidTy()
    }

    public func SynUnaryExpr(ctx: ASTContext, ue: UnaryExpr): Ty {
        if (let Some(desugar) <- ue.desugarExpr) {
            return desugar.GetTy().getOrThrow()
        }
        if ((let None <- ue.expr) || !Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, ue.expr.getOrThrow()))) {
            ue.SetTy(TypeManager.GetInvalidTy())
            return TypeManager.GetInvalidTy()
        }
        if (Ty.IsTyCorrect(SynBuiltinUnaryExpr(ctx, ue))) {
            let operand = ue.expr.getOrThrow()
            let _ = ReplaceIdealTy(impl.typeManager, operand, diag: impl.diag)
            ue.SetTy(operand.GetTy().getOrThrow())
            return ue.GetTy().getOrThrow()
        }
        DesugarOperatorOverloadExpr(ctx, ue)
        if ((let Some(desugar2) <- ue.desugarExpr) &&
            Ty.IsTyCorrect(Synthesize(ctx, SynPos.EXPR_ARG, desugar2))) {
            ue.SetTy(desugar2.GetTy().getOrThrow())
            if (let Some(callExpr) <- (desugar2 as CallExpr)) {
                if (let Some(resolved) <- callExpr.resolvedFunction) {
                    ReplaceTarget(ue, Some<Decl>(resolved))
                }
            }
        } else {
            RecoverToUnaryExpr(ue)
            DiagnoseForUnaryExpr(ctx, ue)
            ue.SetTy(TypeManager.GetInvalidTy())
        }
        return ue.GetTy().getOrThrow()
    }

    public func ChkUnaryExpr(ctx: ASTContext, target: Ty, ue: UnaryExpr): Bool {
        if (let Some(desugar) <- ue.desugarExpr) {
            return impl.typeManager.IsSubtype(desugar.GetTy().getOrThrow(), target)
        }
        var isWellTyped = true
        let unboxedTy = UnboxOptionType(target)
        var retTy: Ty = TypeManager.GetInvalidTy()
        if (unboxedTy.IsBuiltin()) {
            try (ds = DiagSuppressor(impl.diag)) {
                isWellTyped = if (let Some(operand) <- ue.expr) { Check(ctx, unboxedTy, operand) } else { false }
                if (let Some(operand2) <- ue.expr) {
                    operand2.SetTy(impl.typeManager.TryGreedySubst(
                        operand2.GetTy().getOrThrow()))
                }
                retTy = SynBuiltinUnaryExpr(ctx, ue)
                isWellTyped = isWellTyped && Ty.IsTyCorrect(retTy) && Ty.IsTyCorrect(target)
            }
        } else {
            retTy = SynBuiltinUnaryExpr(ctx, ue)
            isWellTyped = Ty.IsTyCorrect(retTy) && Ty.IsTyCorrect(target) &&
                impl.typeManager.IsSubtype(retTy, target)
        }
        if (isWellTyped) {
            let operand3 = ue.expr.getOrThrow()
            let _ = ReplaceIdealTy(impl.typeManager, operand3, diag: impl.diag)
            ue.SetTy(operand3.GetTy().getOrThrow())
            return true
        }
        DesugarOperatorOverloadExpr(ctx, ue)
        if ((let Some(desugar3) <- ue.desugarExpr) && Check(ctx, target, desugar3)) {
            ue.SetTy(desugar3.GetTy().getOrThrow())
            if (let Some(callExpr2) <- (desugar3 as CallExpr)) {
                if (let Some(resolved2) <- callExpr2.resolvedFunction) {
                    ReplaceTarget(ue, Some<Decl>(resolved2))
                }
            }
            return true
        }
        let synTy = if (let Some(desugar4) <- ue.desugarExpr) {
            Synthesize(ctx, SynPos.EXPR_ARG, desugar4)
        } else { TypeManager.GetInvalidTy() }
        if (let Some(desugar5) <- ue.desugarExpr) {
            RecoverToUnaryExpr(ue)
            ctx.DeleteDesugarExpr(desugar5)
        }
        retTy = impl.typeManager.ReplaceIdealTy(retTy)
        let retTyMismatch = isWellTyped || (Ty.IsTyCorrect(target) && Ty.IsTyCorrect(synTy))
        if (retTyMismatch) {
            if (let Some(diag) <- impl.diag) {
                DiagMismatchedTypesWithFoundTy(diag, ue, target, if (isWellTyped) { retTy } else { synTy })
            }
        } else if (Ty.IsTyCorrect(target)) {
            DiagnoseForUnaryExprWithTarget(ctx, ue, target)
        } else {
            DiagnoseForUnaryExpr(ctx, ue)
        }
        ue.SetTy(TypeManager.GetInvalidTy())
        return false
    }
}
