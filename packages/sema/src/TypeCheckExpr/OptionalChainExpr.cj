package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func invalidOptionalChainExpr(oce: OptionalChainExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    if (let Some(innerExpr) <- oce.desugarExpr) {
        innerExpr.SetTy(invalidTy)
    }
    oce.SetTy(invalidTy)
    return invalidTy
}

private func optionalChainPayload(oce: OptionalChainExpr): Option<Expr> {
    if (let Some(innerExpr) <- oce.desugarExpr) {
        return innerExpr
    }
    return oce.expr
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

public func SynOptionalChainExpr(typeManager: TypeManager, oce: OptionalChainExpr): Ty {
    let _ = typeManager
    if (let Some(innerExpr) <- optionalChainPayload(oce)) {
        if (let Some(innerTy) <- innerExpr.GetTy()) {
            if (!innerTy.HasInvalidTy()) {
                oce.SetTy(innerTy)
                return innerTy
            }
        }
    }
    return invalidOptionalChainExpr(oce)
}

public func ChkOptionalChainExpr(typeManager: TypeManager, target: Ty, oce: OptionalChainExpr): Bool {
    let actualTy = SynOptionalChainExpr(typeManager, oce)
    if (actualTy.HasInvalidTy()) {
        return false
    }
    if (!checkOptionBox(typeManager, target, actualTy)) {
        let _ = invalidOptionalChainExpr(oce)
        return false
    }
    return true
}
