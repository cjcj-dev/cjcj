package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::sema.*
import cjcj::utils.CJC_NULLPTR_CHECK

private func invalidOptionalChainExpr(oce: OptionalChainExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    if (let Some(innerExpr) <- oce.desugarExpr) {
        innerExpr.SetTy(invalidTy)
    }
    oce.SetTy(invalidTy)
    return invalidTy
}

private func checkOptionBox(typeManager: TypeManager, target: Ty, ty: Ty): Bool {
    if (typeManager.IsSubtype(ty, target)) {
        return true
    }
    if (target.HasInvalidTy() || !target.IsCoreOptionType()) {
        return false
    }
    if (typeManager.IsTyEqual(ty, target)) {
        return true
    }
    var currentTarget = target
    while (!currentTarget.HasInvalidTy() && currentTarget.IsCoreOptionType()) {
        if (currentTarget.typeArgs.size != 1) {
            return false
        }
        currentTarget = currentTarget.typeArgs[0]
        if (typeManager.IsTyEqual(ty, currentTarget)) {
            return true
        }
    }
    return false
}

private func diagMismatchedTypes(diag: Option<BasicDiagnosticEngine>, oce: OptionalChainExpr, target: Ty): Unit {
    if (let Some(diagValue) <- diag) {
        if (!Ty.IsTyCorrect(oce.GetTy()) || !oce.ShouldDiagnose(allowCompilerAdd: true)) {
            return
        }
        let builder = DiagnoseRefactor(diagValue,
            BasicDiagKindRefactor.sema_mismatched_types,
            oce)
        builder.AddMainHintArguments([target.String(), (oce.GetTy() ?? TypeManager.GetInvalidTy()).String()])
        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
    }
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
