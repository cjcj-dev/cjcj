package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func invalidIncOrDecExpr(ide: IncOrDecExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    ide.SetTy(invalidTy)
    return invalidTy
}

private func validTyOf(node: Node): Option<Ty> {
    if (let Some(ty) <- node.GetTy()) {
        if (!ty.HasInvalidTy()) {
            return ty
        }
    }
    return None
}

public func SynIncOrDecExpr(ide: IncOrDecExpr): Ty {
    if (let Some(desugar) <- ide.desugarExpr) {
        if (let Some(assignExpr) <- (desugar as AssignExpr)) {
            if (let Some(leftValue) <- assignExpr.leftValue) {
                if (let Some(leftTy) <- validTyOf(leftValue)) {
                    if (!leftTy.IsInteger()) {
                        return invalidIncOrDecExpr(ide)
                    }
                    if (let Some(desugarTy) <- validTyOf(desugar)) {
                        ide.SetTy(desugarTy)
                        return desugarTy
                    }
                }
            }
        }
    }
    return invalidIncOrDecExpr(ide)
}

public func ChkIncOrDecExpr(typeManager: TypeManager, target: Ty, ide: IncOrDecExpr): Bool {
    let actualTy = SynIncOrDecExpr(ide)
    if (!actualTy.HasInvalidTy() && typeManager.IsSubtype(actualTy, target)) {
        return true
    }
    let _ = invalidIncOrDecExpr(ide)
    return false
}
