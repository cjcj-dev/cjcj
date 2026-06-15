package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func invalidResumeExpr(re: ResumeExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    re.SetTy(invalidTy)
    return invalidTy
}

private func typedExpr(expr: Option<Expr>): Option<Ty> {
    if (let Some(innerExpr) <- expr) {
        if (let Some(exprTy) <- innerExpr.GetTy()) {
            if (!exprTy.HasInvalidTy()) {
                return exprTy
            }
        }
    }
    return None
}

private func isThrowableTy(typeManager: TypeManager, ty: Ty, exceptionTy: Option<Ty>, errorTy: Option<Ty>): Bool {
    if (let Some(coreExceptionTy) <- exceptionTy) {
        if (typeManager.IsSubtype(ty, coreExceptionTy)) {
            return true
        }
    }
    if (let Some(coreErrorTy) <- errorTy) {
        if (typeManager.IsSubtype(ty, coreErrorTy)) {
            return true
        }
    }
    return false
}

public func SynResumeExpr(typeManager: TypeManager, re: ResumeExpr,
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None): Ty {
    var resumptionParamTy = typeManager.GetAnyTy()
    if (let Some(handler) <- re.enclosing) {
        if (let Some(handlerResultTy) <- handler.commandResultTy) {
            resumptionParamTy = handlerResultTy
        }
        re.SetTy(TypeManager.GetNothingTy())
    } else {
        return invalidResumeExpr(re)
    }

    if (let Some(_) <- re.throwingExpr) {
        if (let Some(throwingTy) <- typedExpr(re.throwingExpr)) {
            if (!isThrowableTy(typeManager, throwingTy, exceptionTy, errorTy)) {
                return invalidResumeExpr(re)
            }
        } else {
            return invalidResumeExpr(re)
        }
    } else if (let Some(_) <- re.withExpr) {
        if (let Some(withTy) <- typedExpr(re.withExpr)) {
            if (typeManager.CheckTypeCompatibility(resumptionParamTy, withTy) == TypeCompatibility.INCOMPATIBLE) {
                return invalidResumeExpr(re)
            }
        } else {
            return invalidResumeExpr(re)
        }
    } else {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        if (!typeManager.IsSubtype(resumptionParamTy, unitTy)) {
            return invalidResumeExpr(re)
        }
    }
    let nothingTy = TypeManager.GetNothingTy()
    re.SetTy(nothingTy)
    return nothingTy
}
