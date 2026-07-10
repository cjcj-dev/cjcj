package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::sema.*

private func invalidResumeExpr(re: ResumeExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    re.SetTy(invalidTy)
    return invalidTy
}

public func SynResumeExpr(typeManager: TypeManager, re: ResumeExpr,
    exceptionTy!: Option<Ty> = None, errorTy!: Option<Ty> = None,
    synthesizer!: Option<(Expr) -> Ty> = None, checker!: Option<(Ty, Expr) -> Bool> = None,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    var resumptionParamTy = typeManager.GetAnyTy()
    if (let Some(handler) <- re.enclosing) {
        if (let Some(handlerResultTy) <- handler.commandResultTy) {
            resumptionParamTy = handlerResultTy
        }
        re.SetTy(TypeManager.GetNothingTy())
    } else {
        if (let Some(diagValue) <- diag) {
            let builder = diagValue.DiagnoseRefactor(BasicDiagKindRefactor.sema_implicit_resume_outside_handler,
                BasicMakeRange(re.begin, re.end))
            builder.Emit()
        }
        let _ = invalidResumeExpr(re)
    }

    if (let Some(throwingExpr) <- re.throwingExpr) {
        if (let Some(syn) <- synthesizer) {
            let _ = syn(throwingExpr)
        }
        if (let Some(throwingTy) <- throwingExpr.GetTy()) {
            var isThrowable = false
            if (let Some(coreExceptionTy) <- exceptionTy) {
                isThrowable = typeManager.IsSubtype(throwingTy, coreExceptionTy) || isThrowable
            }
            if (let Some(coreErrorTy) <- errorTy) {
                isThrowable = typeManager.IsSubtype(throwingTy, coreErrorTy) || isThrowable
            }
            if (!isThrowable) {
                if (let Some(diagValue2) <- diag) {
                    let builder2 = diagValue2.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_resume_throwing_mismatch_type, BasicMakeRange(re.begin, re.end))
                    builder2.Emit()
                }
                let _ = invalidResumeExpr(re)
            }
        } else {
            let _ = invalidResumeExpr(re)
        }
    } else if (let Some(withExpr) <- re.withExpr) {
        if (let Some(chk) <- checker) {
            if (!chk(resumptionParamTy, withExpr)) {
                let _ = invalidResumeExpr(re)
            }
        } else if (let Some(withTy) <- withExpr.GetTy()) {
            if (typeManager.CheckTypeCompatibility(resumptionParamTy, withTy) == TypeCompatibility.INCOMPATIBLE) {
                let _ = invalidResumeExpr(re)
            }
        } else {
            let _ = invalidResumeExpr(re)
        }
    } else {
        let unitTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_UNIT)
        if (!typeManager.IsSubtype(resumptionParamTy, unitTy)) {
            if (let Some(diagValue3) <- diag) {
                let builder3 = diagValue3.DiagnoseRefactor(BasicDiagKindRefactor.sema_resume_no_with,
                    BasicMakeRange(re.begin, re.end), arguments: [resumptionParamTy.String()])
                builder3.Emit()
            }
            let _ = invalidResumeExpr(re)
        }
    }
    return re.GetTy() ?? TypeManager.GetInvalidTy()
}
