package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SelfhostPortStatus_TypeCheckExpr_LoopExprs(): Bool {
    return true
}

private func LoopInvalid(expr: Expr): Ty {
    return TcInvalid(expr)
}

private func IterablePayload(ty: Ty): Option<Ty> {
    if (ty.name == "Iterable" && ty.typeArgs.size == 1) {
        return Some(ty.typeArgs[0])
    }
    return None
}

private func PromotedIterableElementTy(typeManager: TypeManager, inTy: Ty): Option<Ty> {
    if (let Some(payload) <- IterablePayload(inTy)) {
        return Some(payload)
    }
    for (superTy in typeManager.GetAllSuperTys(inTy).values) {
        if (let Some(payload) <- IterablePayload(superTy)) {
            return Some(payload)
        }
    }
    return None
}

private func IterableElementTy(typeManager: TypeManager, inTy: Ty): Ty {
    if (inTy.IsNothing()) {
        return TypeManager.GetInvalidTy()
    }
    if (let Some(elemTy) <- PromotedIterableElementTy(typeManager, inTy)) {
        return elemTy
    }
    if (inTy.IsArray() && inTy.typeArgs.size == 1) {
        return inTy.typeArgs[0]
    }
    if (inTy.IsStructArray() && inTy.typeArgs.size == 1) {
        return inTy.typeArgs[0]
    }
    if (inTy.IsRange() && inTy.typeArgs.size == 1) {
        return inTy.typeArgs[0]
    }
    if (let Some(varrayTy) <- (inTy as VArrayTy)) {
        if (varrayTy.typeArgs.size == 1) {
            return varrayTy.typeArgs[0]
        }
    }
    if (inTy.IsString()) {
        return TypeManager.GetPrimitiveTy(TypeKind.TYPE_RUNE)
    }
    if (inTy.IsAny() || inTy.IsGeneric()) {
        return typeManager.GetAnyTy()
    }
    return TypeManager.GetInvalidTy()
}

public func SynWhileExpr(typeManager: TypeManager, we: WhileExpr): Ty {
    var ok = true
    if (let Some(condExpr) <- we.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr) && ok
    } else {
        ok = false
    }
    if (let Some(body) <- we.body) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, body)) && ok
    } else {
        ok = false
    }
    if (ok) {
        let unitTy = TcUnitTy()
        we.SetTy(unitTy)
        return unitTy
    }
    return LoopInvalid(we)
}

public func ChkWhileExpr(typeManager: TypeManager, target: Ty, we: WhileExpr): Bool {
    let actualTy = SynWhileExpr(typeManager, we)
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LoopInvalid(we)
    return false
}

public func SynDoWhileExpr(typeManager: TypeManager, dwe: DoWhileExpr): Ty {
    var ok = true
    if (let Some(body) <- dwe.body) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, body)) && ok
    } else {
        ok = false
    }
    if (let Some(condExpr) <- dwe.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr) && ok
    } else {
        ok = false
    }
    if (ok) {
        let unitTy = TcUnitTy()
        dwe.SetTy(unitTy)
        return unitTy
    }
    return LoopInvalid(dwe)
}

public func ChkDoWhileExpr(typeManager: TypeManager, target: Ty, dwe: DoWhileExpr): Bool {
    let actualTy = SynDoWhileExpr(typeManager, dwe)
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LoopInvalid(dwe)
    return false
}

public func SynForInExpr(typeManager: TypeManager, fie: ForInExpr): Ty {
    var ok = true
    var elementTy: Ty = TypeManager.GetInvalidTy()
    if (let Some(inExpression) <- fie.inExpression) {
        let inTy = SynExprShallow(typeManager, inExpression)
        if (Ty.IsTyCorrect(inTy)) {
            elementTy = IterableElementTy(typeManager, TcReplaceIdeal(typeManager, inExpression))
            ok = Ty.IsTyCorrect(elementTy) && ok
        } else {
            ok = false
        }
    } else {
        ok = false
    }
    if (let Some(pattern) <- fie.pattern) {
        ok = TcPatternCheck(typeManager, elementTy, pattern) && ok
    } else {
        ok = false
    }
    if (let Some(patternGuard) <- fie.patternGuard) {
        ok = TcCheckCondition(typeManager, patternGuard) && ok
    }
    if (let Some(body) <- fie.body) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, body)) && ok
    } else {
        ok = false
    }
    if (ok) {
        let unitTy = TcUnitTy()
        fie.SetTy(unitTy)
        return unitTy
    }
    return LoopInvalid(fie)
}

public func ChkForInExpr(typeManager: TypeManager, target: Ty, fie: ForInExpr): Bool {
    let actualTy = SynForInExpr(typeManager, fie)
    if (Ty.IsTyCorrect(actualTy) &&
        typeManager.CheckTypeCompatibility(target, actualTy) != TypeCompatibility.INCOMPATIBLE) {
        return true
    }
    let _ = LoopInvalid(fie)
    return false
}
