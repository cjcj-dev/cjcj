package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*

// C++ src/Sema/TypeCheckExpr/TryExpr.cpp:129-147.
public func PromoteToCommandTy(typeManager: TypeManager, cause: Node, cmdTy: Ty, commandTy: Option<Ty>,
    diag: Option<BasicDiagnosticEngine>): Option<ClassTy> {
    if (cmdTy.IsInvalid()) {
        return None
    }
    if (let Some(targetTy) <- commandTy) {
        let promotedTys = Promotion(typeManager).Promote(cmdTy, targetTy)
        if (promotedTys.values.size != 1) {
            if (let Some(diagValue) <- diag) {
                DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_command_incompatible_type,
                    cause, Ty.ToString(Some(cmdTy))).Emit()
            }
            return None
        }
        return promotedTys.values[0] as ClassTy
    }
    return None
}

// C++ src/Sema/TypeCheckExpr/PerformExpr.cpp:15-30.
public func SynPerformExpr(typeManager: TypeManager, pe: PerformExpr, commandTy!: Option<Ty> = None,
    synthesizer!: Option<(Expr) -> Ty> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(innerExpr) <- pe.expr) {
        let exprTy = synthesizer.getOrThrow()(innerExpr)
        if (!Ty.IsTyCorrect(exprTy)) {
            pe.SetTy(TypeManager.GetInvalidTy())
            return pe.GetTy().getOrThrow()
        }
        if (let Some(promotedTy) <- PromoteToCommandTy(typeManager, innerExpr, exprTy, commandTy, diag)) {
            pe.SetTy(promotedTy.typeArgs[0])
        } else {
            pe.SetTy(TypeManager.GetInvalidTy())
        }
        return pe.GetTy().getOrThrow()
    }
    pe.SetTy(TypeManager.GetInvalidTy())
    return pe.GetTy().getOrThrow()
}

extend TypeChecker {
}
