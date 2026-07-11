package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::basic.MakeRange as BasicMakeRange
import cjcj::sema.*

private func invalidSyncExpr(se: SynchronizedExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    if (let Some(desugar) <- se.desugarExpr) {
        desugar.SetTy(invalidTy)
    }
    se.SetTy(invalidTy)
    return invalidTy
}

public func ChkSyncExpr(typeManager: TypeManager, se: SynchronizedExpr,
    lockTy!: Option<Ty> = None, targetTy!: Option<Ty> = None, diag!: Option<BasicDiagnosticEngine> = None,
    checker!: Option<(Ty, Expr) -> Bool> = None, synthesizer!: Option<(Node) -> Ty> = None,
    trySynthesizer!: Option<(TryExpr) -> Ty> = None, tryChecker!: Option<(Ty, TryExpr) -> Bool> = None): Bool {
    var isWellTyped = true
    if (let Some(lockTargetTy) <- lockTy) {
        if (let Some(mutexExpr) <- se.mutex) {
            if (let Some(chk) <- checker) {
                isWellTyped = chk(lockTargetTy, mutexExpr) && isWellTyped
            } else if (let Some(mutexTy) <- mutexExpr.GetTy()) {
                if (typeManager.CheckTypeCompatibility(lockTargetTy, mutexTy) == TypeCompatibility.INCOMPATIBLE) {
                    isWellTyped = false
                }
            } else {
                isWellTyped = false
            }
        } else {
            isWellTyped = false
        }
    } else {
        if (let Some(mutexExpr2) <- se.mutex) {
            if (let Some(diagValue) <- diag) {
                let builder = DiagnoseRefactor(diagValue, BasicDiagKindRefactor.sema_use_expr_without_import,
                    mutexExpr2, arguments: ["sync", "synchronized"])
                builder.Emit()
            }
        }
    }

    if (let Some(desugar) <- se.desugarExpr) {
        if (let Some(block) <- (desugar as Block)) {
            if (block.body.size == 3) {
                if (let Some(syn) <- synthesizer) {
                    isWellTyped = Ty.IsTyCorrect(syn(block.body[0])) && isWellTyped
                    try (ds = DiagSuppressor(diag)) {
                        if (Ty.IsTyCorrect(syn(block.body[1]))) {
                            ds.ReportDiag()
                        } else {
                            isWellTyped = false
                        }
                    }
                } else {
                    if (!Ty.IsTyCorrect(block.body[0].GetTy())) {
                        isWellTyped = false
                    }
                    if (!Ty.IsTyCorrect(block.body[1].GetTy())) {
                        isWellTyped = false
                    }
                }
                if (let Some(tryExpr) <- (block.body[2] as TryExpr)) {
                    if (let Some(expectedTy) <- targetTy) {
                        if (let Some(chkTry) <- tryChecker) {
                            isWellTyped = chkTry(expectedTy, tryExpr) && isWellTyped
                        } else if (let Some(tryTy) <- tryExpr.GetTy()) {
                            if (typeManager.CheckTypeCompatibility(expectedTy, tryTy) ==
                                TypeCompatibility.INCOMPATIBLE) {
                                isWellTyped = false
                            }
                        } else {
                            isWellTyped = false
                        }
                    } else if (let Some(synTry) <- trySynthesizer) {
                        isWellTyped = Ty.IsTyCorrect(synTry(tryExpr)) && isWellTyped
                    } else if (!Ty.IsTyCorrect(tryExpr.GetTy())) {
                        isWellTyped = false
                    }
                    if (isWellTyped) {
                        desugar.SetTy(tryExpr.GetTy() ?? TypeManager.GetInvalidTy())
                    } else {
                        desugar.SetTy(TypeManager.GetInvalidTy())
                    }
                    se.SetTy(desugar.GetTy() ?? TypeManager.GetInvalidTy())
                    return isWellTyped
                }
                isWellTyped = false
            }
        }
    } else {
        isWellTyped = false
    }
    let _ = invalidSyncExpr(se)
    return false
}

public func SynSyncExpr(typeManager: TypeManager, se: SynchronizedExpr, lockTy!: Option<Ty> = None,
    diag!: Option<BasicDiagnosticEngine> = None, checker!: Option<(Ty, Expr) -> Bool> = None,
    synthesizer!: Option<(Node) -> Ty> = None, trySynthesizer!: Option<(TryExpr) -> Ty> = None): Ty {
    if (ChkSyncExpr(typeManager, se, lockTy: lockTy, diag: diag, checker: checker, synthesizer: synthesizer,
        trySynthesizer: trySynthesizer)) {
        if (let Some(ty) <- se.GetTy()) {
            return ty
        }
    }
    return invalidSyncExpr(se)
}

extend TypeChecker {
}
