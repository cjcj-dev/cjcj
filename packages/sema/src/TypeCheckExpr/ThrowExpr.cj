package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagKind as BasicDiagKind
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
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
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
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
    if (let Some(diagValue) <- diag) {
        let builder = diagValue.Diagnose(te.begin, te.end, BasicDiagKind.sema_throw_expr_with_wrong_type)
        builder.Emit()
    }
    let invalidTy = TypeManager.GetInvalidTy()
    te.SetTy(invalidTy)
    return invalidTy
}
