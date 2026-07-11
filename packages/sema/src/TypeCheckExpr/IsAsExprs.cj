package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*

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

public func ChkIsExpr(typeManager: TypeManager, target: Ty, ie: IsExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let boolTy = SynIsExpr(typeManager, ie)
    if (boolTy.HasInvalidTy()) {
        return false
    }
    if (!typeManager.IsLitBoxableType(boolTy, target)) {
        if (let Some(diagValue) <- diag) {
            DiagMismatchedTypesWithFoundTy(diagValue, ie, target, boolTy)
        }
        let _ = invalidIsExpr(ie)
        return false
    }
    return true
}

public func SynAsExpr(typeManager: TypeManager, ae: AsExpr, optionDecl: Option<EnumDecl>,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(left) <- ae.leftExpr) {
        if (let Some(_) <- validExprTy(typeManager, left)) {
            if (let Some(asTy) <- validTypeNodeTy(ae.asType)) {
                if (let Some(coreOptionDecl) <- optionDecl) {
                    let optionTy = typeManager.GetEnumTy(coreOptionDecl, typeArgs: [asTy])
                    ae.SetTy(optionTy)
                    return optionTy
                } else if (let Some(diagValue) <- diag) {
                    let builder = Diagnose(diagValue, ae, BasicDiagKind.sema_no_core_object)
                    builder.Emit()
                }
            }
        }
    }
    return invalidAsExpr(ae)
}

public func ChkAsExpr(typeManager: TypeManager, target: Ty, ae: AsExpr, optionDecl: Option<EnumDecl>,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let asResultTy = SynAsExpr(typeManager, ae, optionDecl, diag: diag)
    if (asResultTy.HasInvalidTy()) {
        return false
    }
    if (!checkOptionBox(typeManager, target, asResultTy)) {
        if (let Some(diagValue) <- diag) {
            DiagMismatchedTypes(diagValue, ae, target)
        }
        let _ = invalidAsExpr(ae)
        return false
    }
    return true
}

extend TypeChecker {
}
