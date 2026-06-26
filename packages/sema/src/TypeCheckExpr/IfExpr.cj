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

private func JoinIfBranchTys(typeManager: TypeManager, thenTy: Ty, elseTy: Ty, curFile: Option<File>): Ty {
    if (!Ty.IsTyCorrect(thenTy) || !Ty.IsTyCorrect(elseTy)) {
        return TypeManager.GetInvalidTy()
    }
    if (thenTy.IsNothing()) {
        return elseTy
    }
    if (elseTy.IsNothing()) {
        return thenTy
    }
    let tys = TySet()
    tys.Add(thenTy)
    tys.Add(elseTy)
    return JoinAsVisibleTy(typeManager, tys, curFile: curFile)
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
            let thenTy = typeManager.GetThisRealTy(TcReplaceIdeal(typeManager, thenBody))
            let elseTy = typeManager.GetThisRealTy(TcReplaceIdeal(typeManager, elseExpr))
            thenBody.SetTy(thenTy)
            elseExpr.SetTy(elseTy)
            let joinedTy = JoinIfBranchTys(typeManager, thenTy, elseTy, ie.curFile)
            if (Ty.IsTyCorrect(joinedTy)) {
                ie.SetTy(joinedTy)
                return joinedTy
            }
        }
    }
    return IfInvalid(ie)
}

private func ChkIfExprNoElse(typeManager: TypeManager, target: Ty, ie: IfExpr,
    ctx!: Option<ASTContext> = None): Bool {
    let unitTy = TcUnitTy()
    var ok = true
    if (let Some(thenBody) <- ie.thenBody) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, thenBody)) && ok
    } else {
        ok = false
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        ok = ChkExprShallow(typeManager, unitTy, elseExpr, ctx: ctx) && ok
    }
    ok = typeManager.CheckTypeCompatibility(target, unitTy) != TypeCompatibility.INCOMPATIBLE && ok
    if (ok) {
        ie.SetTy(unitTy)
        return true
    }
    let _ = IfInvalid(ie)
    return false
}

private func ChkIfExprTwoBranches(typeManager: TypeManager, target: Ty, ie: IfExpr,
    ctx!: Option<ASTContext> = None): Bool {
    var ok = true
    if (let Some(thenBody) <- ie.thenBody) {
        ok = ChkBlock(typeManager, target, thenBody) && ok
    } else {
        ok = false
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        ok = ChkExprShallow(typeManager, target, elseExpr, ctx: ctx) && ok
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

public func ChkIfExpr(typeManager: TypeManager, target: Ty, ie: IfExpr,
    ctx!: Option<ASTContext> = None): Bool {
    var ok = true
    if (let Some(condExpr) <- ie.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr) && ok
    } else {
        ok = false
    }
    if (IsIfExprWithoutElse(ie)) {
        ok = ChkIfExprNoElse(typeManager, target, ie, ctx: ctx) && ok
    } else {
        ok = ChkIfExprTwoBranches(typeManager, target, ie, ctx: ctx) && ok
    }
    if (!ok) {
        let _ = IfInvalid(ie)
    }
    return ok
}
