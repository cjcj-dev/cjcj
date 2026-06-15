package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func invalidSyncExpr(se: SynchronizedExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    if (let Some(desugar) <- se.desugarExpr) {
        desugar.SetTy(invalidTy)
    }
    se.SetTy(invalidTy)
    return invalidTy
}

private func validExprTy(expr: Expr): Option<Ty> {
    if (let Some(ty) <- expr.GetTy()) {
        if (!ty.HasInvalidTy()) {
            return ty
        }
    }
    return None
}

private func desugaredSyncTy(se: SynchronizedExpr): Option<Ty> {
    if (let Some(desugar) <- se.desugarExpr) {
        if (let Some(block) <- (desugar as Block)) {
            if (block.body.size == 3) {
                if (let Some(tryExpr) <- (block.body[2] as Expr)) {
                    if (let Some(tryTy) <- validExprTy(tryExpr)) {
                        desugar.SetTy(tryTy)
                        return tryTy
                    }
                }
            }
        }
        return validExprTy(desugar)
    }
    return None
}

public func ChkSyncExpr(typeManager: TypeManager, se: SynchronizedExpr,
    lockTy!: Option<Ty> = None, targetTy!: Option<Ty> = None): Bool {
    var isWellTyped = true
    if (let Some(lockTargetTy) <- lockTy) {
        if (let Some(mutexExpr) <- se.mutex) {
            if (let Some(mutexTy) <- validExprTy(mutexExpr)) {
                if (typeManager.CheckTypeCompatibility(lockTargetTy, mutexTy) == TypeCompatibility.INCOMPATIBLE) {
                    isWellTyped = false
                }
            } else {
                isWellTyped = false
            }
        } else {
            isWellTyped = false
        }
    } else {
        isWellTyped = false
    }

    if (let Some(actualTy) <- desugaredSyncTy(se)) {
        if (let Some(expectedTy) <- targetTy) {
            if (typeManager.CheckTypeCompatibility(expectedTy, actualTy) == TypeCompatibility.INCOMPATIBLE) {
                isWellTyped = false
            }
        }
        if (isWellTyped) {
            se.SetTy(actualTy)
            return true
        }
    }
    let _ = invalidSyncExpr(se)
    return false
}

public func SynSyncExpr(typeManager: TypeManager, se: SynchronizedExpr, lockTy!: Option<Ty> = None): Ty {
    if (ChkSyncExpr(typeManager, se, lockTy: lockTy)) {
        if (let Some(ty) <- se.GetTy()) {
            return ty
        }
    }
    return invalidSyncExpr(se)
}
