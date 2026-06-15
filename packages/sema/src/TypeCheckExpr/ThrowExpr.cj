package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

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

private func isThrowableClassOrGeneric(typeManager: TypeManager, exprTy: Ty, exceptionTy: Option<Ty>, errorTy: Option<Ty>): Bool {
    if (!exprTy.IsClass() && !exprTy.IsGeneric()) {
        return false
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
            if (exprTy.HasInvalidTy()) {
                return TypeManager.GetInvalidTy()
            }
            if (isFreshResourceException(innerExpr, exprTy) ||
                isThrowableClassOrGeneric(typeManager, exprTy, exceptionTy, errorTy)) {
                return nothingTy
            }
        }
    }
    let invalidTy = TypeManager.GetInvalidTy()
    te.SetTy(invalidTy)
    return invalidTy
}
