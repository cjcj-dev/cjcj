package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*

private func IfInvalid(ie: IfExpr): Ty {
    return TcInvalid(ie)
}

private func IsIfExprWithoutElse(ie: IfExpr): Bool {
    if (let None <- ie.elseBody) {
        return true
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        if (let Some(elseIf) <- (elseExpr as IfExpr)) {
            return IsIfExprWithoutElse(elseIf)
        }
    }
    return false
}

private func JoinIfBranchTys(typeManager: TypeManager, thenTy: Ty, elseTy: Ty, curFile: Option<File>): ErrOrTy {
    if (!Ty.IsTyCorrect(thenTy) || !Ty.IsTyCorrect(elseTy)) {
        return ErrOrTy.TY(TypeManager.GetInvalidTy())
    }
    if (thenTy.IsNothing()) {
        return ErrOrTy.TY(elseTy)
    }
    if (elseTy.IsNothing()) {
        return ErrOrTy.TY(thenTy)
    }
    let tys = TySet()
    tys.Add(thenTy)
    tys.Add(elseTy)
    return JoinAsVisibleTy(typeManager, tys, curFile: curFile)
}

public func SynIfExpr(typeManager: TypeManager, ie: IfExpr, diag: BasicDiagnosticEngine,
    pos!: SynPos = SynPos.NONE): Ty {
    var ok = true
    if (let Some(condExpr) <- ie.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr) && ok
    } else {
        ok = false
    }
    if (let Some(thenBody) <- ie.thenBody) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, thenBody, pos: SynPos.EXPR_ARG, diag: Some(diag))) && ok
    } else {
        ok = false
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        ok = Ty.IsTyCorrect(SynExprShallow(typeManager, elseExpr, diag: Some(diag))) && ok
    }
    if (!ok) {
        return IfInvalid(ie)
    }
    if (IsIfExprWithoutElse(ie)) {
        let unitTy = TcUnitTy()
        ie.SetTy(unitTy)
        return unitTy
    }
    if (let Some(thenBody) <- ie.thenBody) {
        if (let Some(elseExpr) <- ie.elseBody) {
            let thenTy = typeManager.GetThisRealTy(TcReplaceIdeal(typeManager, thenBody))
            let elseTy = typeManager.GetThisRealTy(TcReplaceIdeal(typeManager, elseExpr))
            thenBody.SetTy(thenTy)
            elseExpr.SetTy(elseTy)
            if (pos == SynPos.UNUSED) {
                let unitTy2 = TcUnitTy()
                ie.SetTy(unitTy2)
                return unitTy2
            }
            let joinRes = JoinIfBranchTys(typeManager, thenTy, elseTy, ie.curFile)
            let (optErrs, joinedTy) = SetJoinedType(ie.GetTy() ?? TypeManager.GetInvalidTy(), joinRes)
            if (let Some(errMsg) <- optErrs) {
                var diagMessage = "types " + Ty.ToString(Some(thenTy)) + " and " + Ty.ToString(Some(elseTy))
                diagMessage += if (let Some(sourceExpr) <- ie.sourceExpr) {
                    if (sourceExpr.astKind == ASTKind.IF_AVAILABLE_EXPR) {
                        " of the two lambda of this '@IfAvailable' expression mismatch"
                    } else {
                        " of the two branches of this 'if' expression mismatch"
                    }
                } else {
                    " of the two branches of this 'if' expression mismatch"
                }
                let builder = Diagnose(diag, ie, BasicDiagKind.sema_diag_report_error_message,
                    args: [BasicDiagArgument(diagMessage)])
                builder.AddNote(errMsg)
                builder.Emit()
            }
            if (Ty.IsTyCorrect(joinedTy)) {
                ie.SetTy(joinedTy)
                return joinedTy
            }
        }
    }
    return IfInvalid(ie)
}

private func ChkIfExprNoElse(typeManager: TypeManager, target: Ty, ie: IfExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let unitTy = TcUnitTy()
    var ok = true
    if (let Some(thenBody) <- ie.thenBody) {
        ok = Ty.IsTyCorrect(SynBlock(typeManager, thenBody, pos: SynPos.EXPR_ARG)) && ok
    } else {
        ok = false
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        ok = Ty.IsTyCorrect(SynExprShallow(typeManager, elseExpr)) && ok
    }
    let targetMatched = typeManager.IsSubtype(unitTy, target)
    if (ok && !targetMatched) {
        if (let Some(diagValue) <- diag) {
            DiagMismatchedTypesWithFoundTy(diagValue, ie, target, unitTy,
                note: "the type of an 'if' expression without an 'else' branch is always 'Unit'")
        }
    }
    if (ok && targetMatched) {
        ie.SetTy(unitTy)
        return true
    }
    let _ = IfInvalid(ie)
    return false
}

private func ChkIfExprTwoBranches(typeManager: TypeManager, target: Ty, ie: IfExpr,
    ctx!: Option<ASTContext> = None): Bool {
    var ok = true
    if (let Some(thenBody) <- ie.thenBody) {
        ok = ChkBlock(typeManager, target, thenBody) && ok
    } else {
        ok = false
    }
    if (let Some(elseExpr) <- ie.elseBody) {
        ok = ChkExprShallow(typeManager, target, elseExpr, ctx: ctx) && ok
    } else {
        ok = false
    }
    if (ok) {
        ie.SetTy(target)
        return true
    }
    let _ = IfInvalid(ie)
    return false
}

public func ChkIfExpr(typeManager: TypeManager, target: Ty, ie: IfExpr,
    ctx!: Option<ASTContext> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    var ok = true
    if (let Some(condExpr) <- ie.condExpr) {
        ok = TcCheckCondition(typeManager, condExpr) && ok
    } else {
        ok = false
    }
    if (IsIfExprWithoutElse(ie)) {
        ok = ChkIfExprNoElse(typeManager, target, ie, diag: diag) && ok
    } else {
        ok = ChkIfExprTwoBranches(typeManager, target, ie, ctx: ctx) && ok
    }
    if (!ok) {
        let _ = IfInvalid(ie)
    }
    return ok
}

extend TypeChecker {
}
