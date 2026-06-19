package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SelfhostPortStatus_TypeCheckExpr_LoopExprs(): Bool {
    return true
}

private func LoopInvalid(expr: Expr): Ty {
    return TcInvalid(expr)
}

private func SynLoopBody(typeManager: TypeManager, body: Block): Bool {
    let bodyTy = SynBlock(typeManager, body)
    if (Ty.IsTyCorrect(bodyTy)) {
        body.SetTy(TcUnitTy())
        return true
    }
    return false
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
    if (let Some(genericTy) <- (inTy as GenericsTy)) {
        for (upperTy in genericTy.upperBounds) {
            if (let Some(payloadFromUpper) <- PromotedIterableElementTy(typeManager, upperTy)) {
                return Some(payloadFromUpper)
            }
        }
    }
    for (superTy in typeManager.GetAllSuperTys(inTy).values) {
        if (let Some(payload) <- IterablePayload(superTy)) {
            return Some(payload)
        }
    }
    return None
}

public func ForInIterableElementTy(typeManager: TypeManager, inTy: Ty): Ty {
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
        ok = SynLoopBody(typeManager, body) && ok
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
        ok = SynLoopBody(typeManager, body) && ok
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
            elementTy = ForInIterableElementTy(typeManager, TcReplaceIdeal(typeManager, inExpression))
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
        ok = SynLoopBody(typeManager, body) && ok
    } else {
        ok = false
    }
    if (let Some(pattern) <- fie.pattern) {
        ok = IsIrrefutablePattern(pattern) && ok
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
