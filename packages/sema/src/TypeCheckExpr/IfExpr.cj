package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func SelfhostPortStatus_TypeCheckExpr_IfExpr(): Bool {
    return true
}

private func IfInvalid(ie: IfExpr): Ty {
    return TcInvalid(ie)
}

private func IsIfExprWithoutElse(ie: IfExpr): Bool {
    if (let None <- ie.elseBody) {
        return true
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        if (let Some(elseIf) <- (elseExpr as IfExpr)) {
            return IsIfExprWithoutElse(elseIf)
        }
    }
    return false
}

private func JoinIfBranchTys(typeManager: TypeManager, thenTy: Ty, elseTy: Ty): Ty {
    if (thenTy.IsNothing()) {
        return elseTy
    }
    if (elseTy.IsNothing()) {
        return thenTy
    }
    if (typeManager.CheckTypeCompatibility(thenTy, elseTy) != TypeCompatibility.INCOMPATIBLE) {
        return thenTy
    }
    if (typeManager.CheckTypeCompatibility(elseTy, thenTy) != TypeCompatibility.INCOMPATIBLE) {
        return elseTy
    }
    let tySet = TySet()
    tySet.Add(thenTy)
    tySet.Add(elseTy)
    let supers = typeManager.GetAllCommonSuperTys(tySet)
    if (!supers.values.isEmpty()) {
        return supers.values[0]
    }
    return TypeManager.GetInvalidTy()
}

private func SynIfBranches(typeManager: TypeManager, ie: IfExpr): Bool {
    var ok = true
    if (let Some(thenBody) <- ie.thenBody) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, thenBody)) && ok
    } else {
        ok = false
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        ok = Ty.IsTyCorrect(SynExprShallow(typeManager, elseExpr)) && ok
    }
    return ok
}

public func SynIfExpr(typeManager: TypeManager, ie: IfExpr): Ty {
    var ok = true
    if (let Some(condExpr) <- ie.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr) && ok
    } else {
        ok = false
    }
    ok = SynIfBranches(typeManager, ie) && ok
    if (!ok) {
        return IfInvalid(ie)
    }
    if (IsIfExprWithoutElse(ie)) {
        let unitTy = TcUnitTy()
        ie.SetTy(unitTy)
        return unitTy
    }
    if (let Some(thenBody) <- ie.thenBody) {
        if (let Some(elseExpr) <- ie.elseBody) {
            let thenTy = TcReplaceIdeal(typeManager, thenBody)
            let elseTy = TcReplaceIdeal(typeManager, elseExpr)
            let joinedTy = JoinIfBranchTys(typeManager, thenTy, elseTy)
            if (Ty.IsTyCorrect(joinedTy)) {
                ie.SetTy(joinedTy)
                return joinedTy
            }
        }
    }
    return IfInvalid(ie)
}

private func ChkIfExprNoElse(typeManager: TypeManager, target: Ty, ie: IfExpr): Bool {
    let unitTy = TcUnitTy()
    var ok = true
    if (let Some(thenBody) <- ie.thenBody) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, thenBody)) && ok
    } else {
        ok = false
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        ok = Ty.IsTyCorrect(SynExprShallow(typeManager, elseExpr)) && ok
    }
    ok = typeManager.CheckTypeCompatibility(target, unitTy) != TypeCompatibility.INCOMPATIBLE && ok
    if (ok) {
        ie.SetTy(unitTy)
        return true
    }
    let _ = IfInvalid(ie)
    return false
}

private func ChkIfExprTwoBranches(typeManager: TypeManager, target: Ty, ie: IfExpr): Bool {
    var ok = true
    if (let Some(thenBody) <- ie.thenBody) {
        ok = ChkBlock(typeManager, target, thenBody) && ok
    } else {
        ok = false
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        ok = ChkExprShallow(typeManager, target, elseExpr) && ok
    } else {
        ok = false
    }
    if (ok) {
        ie.SetTy(target)
        return true
    }
    let _ = IfInvalid(ie)
    return false
}

public func ChkIfExpr(typeManager: TypeManager, target: Ty, ie: IfExpr): Bool {
    var ok = true
    if (let Some(condExpr) <- ie.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr) && ok
    } else {
        ok = false
    }
    if (IsIfExprWithoutElse(ie)) {
        ok = ChkIfExprNoElse(typeManager, target, ie) && ok
    } else {
        ok = ChkIfExprTwoBranches(typeManager, target, ie) && ok
    }
    if (!ok) {
        let _ = IfInvalid(ie)
    }
    return ok
}
