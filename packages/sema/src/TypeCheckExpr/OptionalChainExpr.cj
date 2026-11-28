package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::sema.*

private func invalidOptionalChainExpr(oce: OptionalChainExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    if (let Some(innerExpr) <- oce.desugarExpr) {
        innerExpr.SetTy(invalidTy)
    }
    oce.SetTy(invalidTy)
    return invalidTy
}

extend TypeChecker {
    func SynOptionalChainExpr(ctx: CheckerContext, oce: OptionalChainExpr): Ty {
        if (let None <- oce.desugarExpr) {
            return invalidOptionalChainExpr(oce)
        }
        let ty = Synthesize(ctx.Ctx(), ctx.SynthPos(), oce.desugarExpr.getOrThrow())
        oce.SetTy(ty)
        return ty
    }

    func ChkOptionalChainExpr(ctx: ASTContext, target: Ty, oce: OptionalChainExpr): Bool {
        if ((let None <- oce.desugarExpr) ||
            !Ty.IsTyCorrect(SynOptionalChainExpr(CheckerContext(ctx, SynPos.EXPR_ARG), oce))) {
            return false
        }
        let innerExpr = oce.desugarExpr.getOrThrow()
        if (!CheckOptionBox(impl.typeManager, target, innerExpr.GetTy().getOrThrow())) {
            if (let Some(diag) <- impl.diag) { DiagMismatchedTypes(diag, oce, target) }
            let _ = invalidOptionalChainExpr(oce)
            return false
        }
        return true
    }
}
