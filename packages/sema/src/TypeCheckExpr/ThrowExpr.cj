package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private let CORE_PACKAGE_NAME: String = "std.core"
private let CLASS_EXCEPTION_NAME: String = "Exception"
private let CLASS_ERROR_NAME: String = "Error"
private let RESOURCE_NAME: String = "v-freshExc"

private func isFreshResourceException(expr: Expr, exprTy: Ty): Bool {
    if (!exprTy.IsEnum()) {
        return false
    }
    if (let Some(refExpr) <- (expr as RefExpr)) {
        return refExpr.ref.identifier.Val() == RESOURCE_NAME
    }
    return false
}

private func isCoreNamedTy(ty: Ty, name: String): Bool {
    if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        if (!decl.fullPackageName.isEmpty()) {
            return decl.fullPackageName == CORE_PACKAGE_NAME && decl.identifier.Val() == name
        }
    }
    return false
}

private func isCoreThrowableTy(typeManager: TypeManager, ty: Ty): Bool {
    if (isCoreNamedTy(ty, CLASS_EXCEPTION_NAME) || isCoreNamedTy(ty, CLASS_ERROR_NAME)) {
        return true
    }
    if (let Some(genericTy) <- (ty as GenericsTy)) {
        for (upperTy in genericTy.upperBounds) {
            if (isCoreThrowableTy(typeManager, upperTy)) {
                return true
            }
        }
    }
    for (superTy in typeManager.GetAllSuperTys(ty).values) {
        if (isCoreNamedTy(superTy, CLASS_EXCEPTION_NAME) || isCoreNamedTy(superTy, CLASS_ERROR_NAME)) {
            return true
        }
    }
    return false
}

private func constructorCallObjectTy(expr: Expr): Option<Ty> {
    if (let Some(callExpr) <- (expr as CallExpr)) {
        var target: Option<FuncDecl> = callExpr.resolvedFunction
        if (let None <- target) {
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                if (let Some(baseTarget) <- baseFunc.GetTarget()) {
                    target = baseTarget as FuncDecl
                }
            }
        }
        if (let Some(funcDecl) <- target) {
            if (funcDecl.TestAttr(Attribute.CONSTRUCTOR)) {
                if (let Some(outerDecl) <- funcDecl.outerDecl) {
                    return outerDecl.GetTy()
                }
            }
        }
    }
    return None
}

private func effectiveThrowOperandTy(expr: Expr, exprTy: Ty): Ty {
    if (let Some(objectTy) <- constructorCallObjectTy(expr)) {
        if (exprTy.IsUnit() || !isCoreThrowableTy(TypeManager(), exprTy)) {
            expr.SetTy(objectTy)
            return objectTy
        }
    }
    return exprTy
}

private func isThrowableClassOrGeneric(typeManager: TypeManager, exprTy: Ty, exceptionTy: Option<Ty>, errorTy: Option<Ty>): Bool {
    if (!exprTy.IsClass() && !exprTy.IsGeneric()) {
        return false
    }
    if (isCoreThrowableTy(typeManager, exprTy)) {
        return true
    }
    if (let Some(coreExceptionTy) <- exceptionTy) {
        if (typeManager.IsSubtype(exprTy, coreExceptionTy)) {
            return true
        }
    }
    if (let Some(coreErrorTy) <- errorTy) {
        if (typeManager.IsSubtype(exprTy, coreErrorTy)) {
            return true
        }
    }
    return false
}

public func SynThrowExpr(typeManager: TypeManager, te: ThrowExpr,
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None): Ty {
    let nothingTy = TypeManager.GetNothingTy()
    te.SetTy(nothingTy)
    if (let Some(innerExpr) <- te.expr) {
        if (let Some(exprTy) <- innerExpr.GetTy()) {
            let thrownTy = effectiveThrowOperandTy(innerExpr, exprTy)
            if (thrownTy.HasInvalidTy()) {
                return TypeManager.GetInvalidTy()
            }
            if (isFreshResourceException(innerExpr, exprTy) ||
                isThrowableClassOrGeneric(typeManager, thrownTy, exceptionTy, errorTy)) {
                return nothingTy
            }
        }
    }
    let invalidTy = TypeManager.GetInvalidTy()
    te.SetTy(invalidTy)
    return invalidTy
}
