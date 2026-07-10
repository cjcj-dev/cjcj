package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::sema.*

private func invalidParenExpr(pe: ParenExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    pe.SetTy(invalidTy)
    return invalidTy
}

public func SynParenExpr(typeManager: TypeManager, pe: ParenExpr, synthesizer!: Option<(Expr) -> Ty> = None): Ty {
    if (let Some(innerExpr) <- pe.expr) {
        if (let Some(syn) <- synthesizer) {
            let _ = syn(innerExpr)
        }
        if (let Some(innerTy) <- innerExpr.GetTy()) {
            if (!innerTy.HasInvalidTy()) {
                var resolvedTy = innerTy
                if (innerTy.IsIdeal()) {
                    resolvedTy = typeManager.ReplaceIdealTy(innerTy)
                    innerExpr.SetTy(resolvedTy)
                }
                pe.SetTy(resolvedTy)
                if (innerExpr.isConst) {
                    pe.isConst = true
                    pe.constNumValue = innerExpr.constNumValue
                }
                return resolvedTy
            }
        }
    }
    return invalidParenExpr(pe)
}

public func ChkParenExpr(typeManager: TypeManager, target: Ty, pe: ParenExpr,
    checker!: Option<(Ty, Expr) -> Bool> = None): Bool {
    if (let Some(innerExpr) <- pe.expr) {
        if (let Some(chk) <- checker) {
            if (chk(target, innerExpr)) {
                pe.SetTy(TcTyOrInvalid(innerExpr))
                if (innerExpr.isConst) {
                    pe.isConst = true
                    pe.constNumValue = innerExpr.constNumValue
                }
                return true
            }
            let _ = invalidParenExpr(pe)
            return false
        }
        let actualTy = SynParenExpr(typeManager, pe)
        if (!actualTy.HasInvalidTy() &&
            typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
            pe.SetTy(actualTy)
            if (innerExpr.isConst) {
                pe.isConst = true
                pe.constNumValue = innerExpr.constNumValue
            }
            return true
        }
    }
    let _ = invalidParenExpr(pe)
    return false
}
