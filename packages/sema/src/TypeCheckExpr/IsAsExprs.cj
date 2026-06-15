package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func invalidIsExpr(ie: IsExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    ie.SetTy(invalidTy)
    return invalidTy
}

private func invalidAsExpr(ae: AsExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    ae.SetTy(invalidTy)
    return invalidTy
}

private func validExprTy(typeManager: TypeManager, expr: Expr): Option<Ty> {
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

private func validTypeNodeTy(node: Option<Type>): Option<Ty> {
    if (let Some(typeNode) <- node) {
        if (let Some(typeTy) <- typeNode.GetTy()) {
            if (!typeTy.HasInvalidTy()) {
                return typeTy
            }
        }
    }
    return None
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

public func SynIsExpr(typeManager: TypeManager, ie: IsExpr): Ty {
    if (let Some(left) <- ie.leftExpr) {
        if (let Some(_) <- validExprTy(typeManager, left)) {
            if (let Some(_) <- validTypeNodeTy(ie.isType)) {
                let boolTy = TypeManager.GetBoolTy()
                ie.SetTy(boolTy)
                return boolTy
            }
        }
    }
    return invalidIsExpr(ie)
}

public func ChkIsExpr(typeManager: TypeManager, target: Ty, ie: IsExpr): Bool {
    let boolTy = SynIsExpr(typeManager, ie)
    if (boolTy.HasInvalidTy()) {
        return false
    }
    if (!typeManager.IsLitBoxableType(boolTy, target)) {
        let _ = invalidIsExpr(ie)
        return false
    }
    return true
}

public func SynAsExpr(typeManager: TypeManager, ae: AsExpr, optionDecl: Option<EnumDecl>): Ty {
    if (let Some(left) <- ae.leftExpr) {
        if (let Some(_) <- validExprTy(typeManager, left)) {
            if (let Some(asTy) <- validTypeNodeTy(ae.asType)) {
                if (let Some(coreOptionDecl) <- optionDecl) {
                    let optionTy = typeManager.GetEnumTy(coreOptionDecl, typeArgs: [asTy])
                    ae.SetTy(optionTy)
                    return optionTy
                }
            }
        }
    }
    return invalidAsExpr(ae)
}

public func ChkAsExpr(typeManager: TypeManager, target: Ty, ae: AsExpr, optionDecl: Option<EnumDecl>): Bool {
    let asResultTy = SynAsExpr(typeManager, ae, optionDecl)
    if (asResultTy.HasInvalidTy()) {
        return false
    }
    if (!checkOptionBox(typeManager, target, asResultTy)) {
        let _ = invalidAsExpr(ae)
        return false
    }
    return true
}
