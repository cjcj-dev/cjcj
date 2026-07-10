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
        let builder = diagValue.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_mismatched_types,
            BasicMakeRange(oce.begin, oce.end))
        builder.AddMainHintArguments([target.String(), (oce.GetTy() ?? TypeManager.GetInvalidTy()).String()])
        // GAP_TODO: emission blocked on sema TypeCheckCall call-path parity (spurious fires during self-compile; see C++ dtor auto-emit DiagnosticEngine.cpp:314)
    }
}

public func SynOptionalChainExpr(typeManager: TypeManager, oce: OptionalChainExpr,
    synthesizer!: Option<(Expr) -> Ty> = None): Ty {
    CJC_NULLPTR_CHECK(oce.desugarExpr)
    let innerExpr = oce.desugarExpr.getOrThrow()
    let innerTy = if (let Some(syn) <- synthesizer) {
        syn(innerExpr)
    } else {
        SynExprShallow(typeManager, innerExpr)
    }
    oce.SetTy(innerTy)
    return innerTy
}

public func ChkOptionalChainExpr(typeManager: TypeManager, target: Ty, oce: OptionalChainExpr,
    synthesizer!: Option<(Expr) -> Ty> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let actualTy = SynOptionalChainExpr(typeManager, oce, synthesizer: synthesizer)
    if (actualTy.HasInvalidTy()) {
        return false
    }
    if (!checkOptionBox(typeManager, target, actualTy)) {
        diagMismatchedTypes(diag, oce, target)
        let _ = invalidOptionalChainExpr(oce)
        return false
    }
    return true
}
