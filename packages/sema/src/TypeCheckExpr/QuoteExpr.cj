package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func invalidQuoteExpr(qe: QuoteExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    qe.SetTy(invalidTy)
    return invalidTy
}

public func SynQuoteExpr(qe: QuoteExpr): Ty {
    if (let Some(desugar) <- qe.desugarExpr) {
        if (let Some(desugarTy) <- desugar.GetTy()) {
            if (!desugarTy.HasInvalidTy()) {
                qe.SetTy(desugarTy)
                return desugarTy
            }
        }
    }
    return invalidQuoteExpr(qe)
}

public func ChkQuoteExpr(typeManager: TypeManager, target: Ty, qe: QuoteExpr): Bool {
    let quoteTy = SynQuoteExpr(qe)
    if (quoteTy.HasInvalidTy()) {
        return false
    }
    if (!typeManager.IsSubtype(quoteTy, target)) {
        let _ = invalidQuoteExpr(qe)
        return false
    }
    if (let Some(desugar) <- qe.desugarExpr) {
        if (let Some(desugarTy) <- desugar.GetTy()) {
            if (typeManager.CheckTypeCompatibility(target, desugarTy) == TypeCompatibility.INCOMPATIBLE) {
                let _ = invalidQuoteExpr(qe)
                return false
            }
        } else {
            let _ = invalidQuoteExpr(qe)
            return false
        }
    }
    return true
}
