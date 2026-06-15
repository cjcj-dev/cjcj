package cangjie_compiler::sema.TypeCheckExpr

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func invalidTupleLit(tl: TupleLit): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    tl.SetTy(invalidTy)
    return invalidTy
}

private func unboxOptionType(ty: Ty): Ty {
    var currentTy = ty
    while (!currentTy.HasInvalidTy() && currentTy.IsCoreOptionType()) {
        if (currentTy.typeArgs.size != 1) {
            return TypeManager.GetInvalidTy()
        }
        currentTy = currentTy.typeArgs[0]
    }
    return currentTy
}

private func replaceIdealChildTy(typeManager: TypeManager, expr: Expr): Option<Ty> {
    if (let Some(exprTy) <- expr.GetTy()) {
        if (exprTy.HasInvalidTy()) {
            return None
        }
        if (exprTy.IsIdeal()) {
            let concreteTy = typeManager.ReplaceIdealTy(exprTy)
            expr.SetTy(concreteTy)
            return concreteTy
        }
        return exprTy
    }
    return None
}

public func SynTupleLit(typeManager: TypeManager, tl: TupleLit): Ty {
    let elementTys = ArrayList<Ty>()
    for (child in tl.children) {
        if (let Some(elementTy) <- replaceIdealChildTy(typeManager, child)) {
            elementTys.add(elementTy)
        } else {
            return invalidTupleLit(tl)
        }
    }
    let tupleTy = typeManager.GetTupleTy(elementTys.toArray())
    tl.SetTy(tupleTy)
    return tupleTy
}

public func ChkTupleLit(typeManager: TypeManager, target: Ty, tl: TupleLit): Bool {
    if (target.IsAny()) {
        let actualTy = SynTupleLit(typeManager, tl)
        return !actualTy.HasInvalidTy()
    }

    let targetTy = unboxOptionType(target)
    if (targetTy.HasInvalidTy() || !targetTy.IsTuple()) {
        let _ = invalidTupleLit(tl)
        return false
    }
    if (let Some(targetTuple) <- (targetTy as TupleTy)) {
        if (targetTuple.typeArgs.size != tl.children.size) {
            let _ = SynTupleLit(typeManager, tl)
            return false
        }
        for (idx in 0..targetTuple.typeArgs.size) {
            let child = tl.children[idx]
            if (let Some(childTy) <- replaceIdealChildTy(typeManager, child)) {
                if (childTy.HasInvalidTy() ||
                    typeManager.CheckTypeCompatibility(targetTuple.typeArgs[idx], childTy) ==
                    TypeCompatibility.INCOMPATIBLE) {
                    let _ = SynTupleLit(typeManager, tl)
                    return false
                }
            } else {
                let _ = invalidTupleLit(tl)
                return false
            }
        }
        tl.SetTy(targetTy)
        return true
    }
    let _ = invalidTupleLit(tl)
    return false
}
