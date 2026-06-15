package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func invalidReturnExpr(re: ReturnExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    re.SetTy(invalidTy)
    return invalidTy
}

private func hasImportedGenericJava(node: Node): Bool {
    if (let Some(_) <- HasJavaAttr(node)) {
        return node.TestAttr(Attribute.GENERIC) && node.TestAttr(Attribute.IMPORTED)
    }
    return false
}

public func NeedCheckBodyReturn(fb: FuncBody): Bool {
    if (let Some(classLike) <- fb.parentClassLike) {
        if (hasImportedGenericJava(classLike)) {
            return false
        }
    }
    if (let Some(funcDecl) <- fb.funcDecl) {
        if (hasImportedGenericJava(funcDecl)) {
            return false
        }
    }
    return true
}

private func replaceClassThisOutsideClass(re: ReturnExpr, expr: Expr): Unit {
    if (let Some(fb) <- re.refFuncBody) {
        if (let Some(parent) <- fb.parentClassLike) {
            if (let Some(_) <- (parent as ClassDecl)) {
                return
            }
        }
    }
    if (let Some(exprTy) <- expr.GetTy()) {
        if (let Some(classThisTy) <- (exprTy as ClassThisTy)) {
            if (let Some(classDecl) <- classThisTy.decl) {
                if (let Some(classTy) <- classDecl.GetTy()) {
                    expr.SetTy(classTy)
                }
            }
        }
    }
}

private func checkReturnValue(typeManager: TypeManager, targetTy: Ty, expr: Expr): Bool {
    if (let Some(exprTy) <- expr.GetTy()) {
        if (exprTy.HasInvalidTy()) {
            return false
        }
        var actualTy = exprTy
        if (exprTy.IsIdeal()) {
            actualTy = typeManager.ReplaceIdealTy(exprTy)
            expr.SetTy(actualTy)
        }
        return typeManager.CheckTypeCompatibility(targetTy, actualTy) != TypeCompatibility.INCOMPATIBLE
    }
    return false
}

private func synthesizeReturnValue(typeManager: TypeManager, expr: Expr): Bool {
    if (let Some(exprTy) <- expr.GetTy()) {
        if (exprTy.HasInvalidTy()) {
            return false
        }
        if (exprTy.IsIdeal()) {
            expr.SetTy(typeManager.ReplaceIdealTy(exprTy))
        }
        return true
    }
    return false
}

public func SynReturnExpr(typeManager: TypeManager, re: ReturnExpr): Ty {
    if (let Some(fb) <- re.refFuncBody) {
        if (let Some(retTypeNode) <- fb.retType) {
            if (let Some(innerExpr) <- re.expr) {
                let _ = invalidReturnExpr(re)
                var isWellTyped = false
                if (let Some(retTy) <- retTypeNode.GetTy()) {
                    if (!retTy.HasInvalidTy() && !retTy.IsQuest()) {
                        let targetTy = if (let Some(funcDecl) <- fb.funcDecl) {
                            if (IsInstanceConstructor(funcDecl)) {
                                TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
                            } else {
                                retTy
                            }
                        } else {
                            retTy
                        }
                        isWellTyped = checkReturnValue(typeManager, targetTy, innerExpr)
                    } else {
                        isWellTyped = synthesizeReturnValue(typeManager, innerExpr)
                    }
                } else {
                    isWellTyped = synthesizeReturnValue(typeManager, innerExpr)
                }
                replaceClassThisOutsideClass(re, innerExpr)
                if (!isWellTyped && NeedCheckBodyReturn(fb)) {
                    return invalidReturnExpr(re)
                }
                let nothingTy = TypeManager.GetNothingTy()
                re.SetTy(nothingTy)
                return nothingTy
            }
        }
    }
    return invalidReturnExpr(re)
}

public func ChkReturnExpr(typeManager: TypeManager, re: ReturnExpr): Bool {
    return !SynReturnExpr(typeManager, re).HasInvalidTy()
}
