package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*

private func IsLitConstExpr(expr: Option<Expr>): Bool {
    if (let Some(realExpr) <- expr) {
        if (let Some(_) <- (realExpr as LitConstExpr)) {
            return true
        }
    }
    return false
}
extend TypeChecker {
    private func SynRangeExprInferElemTy(re: RangeExpr, ctx: ASTContext): Ty {
        let startTy = if (let Some(start) <- re.startExpr) {
            Synthesize(ctx, SynPos.EXPR_ARG, start)
        } else { TypeManager.GetInvalidTy() }
        let useStartLit = !IsLitConstExpr(re.startExpr) || IsLitConstExpr(re.stopExpr)
        if (Ty.IsTyCorrect(startTy) && !startTy.IsNothing() && useStartLit) {
            return startTy
        }
        let stopTy = if (let Some(stop) <- re.stopExpr) {
            Synthesize(ctx, SynPos.EXPR_ARG, stop)
        } else { TypeManager.GetInvalidTy() }
        if (Ty.IsTyCorrect(stopTy) && !stopTy.IsNothing()) {
            return stopTy
        } else if (Ty.IsTyCorrect(startTy)) {
            return startTy
        }
        return TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
    }

    private func CheckRangeElements(ctx: ASTContext, elemTy: Ty, re: RangeExpr): Bool {
        var isWellTyped = if (let Some(start) <- re.startExpr) { Check(ctx, elemTy, start) } else { true }
        isWellTyped = (if (let Some(stop) <- re.stopExpr) { Check(ctx, elemTy, stop) } else { true }) && isWellTyped
        let inconsistent = !ctx.HasTargetTy(re) && re.startExpr.isSome() && re.stopExpr.isSome() && !isWellTyped
        if (inconsistent && !CanSkipDiag(re.startExpr.getOrThrow()) && !CanSkipDiag(re.stopExpr.getOrThrow())) {
            if (let Some(diag) <- impl.diag) {
                Diagnose(diag, re, BasicDiagKind.sema_inconsistency_range_elemType).Emit()
            }
        }
        let typeArgs = ArrayList<Ty>()
        typeArgs.add(elemTy)
        var rangeDecl: Option<Decl> = None
        if (let Some(decl) <- re.decl) {
            rangeDecl = Some<Decl>(decl)
        }
        if (isWellTyped && !impl.CheckGenericDeclInstantiation(rangeDecl, typeArgs, re)) {
            isWellTyped = false
        }
        if (let Some(stepExpr) <- re.stepExpr) {
            if (!Check(ctx, TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64), stepExpr)) {
                if (!CanSkipDiag(stepExpr)) {
                    if (let Some(diag2) <- impl.diag) {
                        Diagnose(diag2, re, BasicDiagKind.sema_range_step_not_int64).Emit()
                    }
                }
                isWellTyped = false
            } else if (stepExpr.isConst && stepExpr.constNumValue.asInt.Uint64() == 0u64) {
                if (let Some(diag3) <- impl.diag) {
                    Diagnose(diag3, stepExpr, BasicDiagKind.sema_step_non_zero_range).Emit()
                }
            }
        }
        return isWellTyped
    }

    func SynRangeExpr(ctx: ASTContext, re: RangeExpr): Ty {
        re.SetTy(TypeManager.GetInvalidTy())
        re.decl = if (let Some(manager) <- impl.importManager) {
            manager.GetCoreDecl<StructDecl>("Range")
        } else { GetCoreDecl(ctx, "Range") as StructDecl }
        if (re.decl.isNone()) {
            return re.GetTy().getOrThrow()
        }
        var elemTy = SynRangeExprInferElemTy(re, ctx)
        if (Ty.IsTyCorrect(elemTy) && elemTy.IsIdeal() && elemTy.IsInteger()) {
            elemTy = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        }
        if (!CheckRangeElements(ctx, elemTy, re)) {
            return re.GetTy().getOrThrow()
        }
        let rangeTy = impl.typeManager.GetStructTy(re.decl.getOrThrow(), [elemTy])
        re.SetTy(rangeTy)
        return rangeTy
    }

    func ChkRangeExpr(ctx: ASTContext, target: Ty, re: RangeExpr): Bool {
        re.SetTy(TypeManager.GetInvalidTy())
        re.decl = if (let Some(manager) <- impl.importManager) {
            manager.GetCoreDecl<StructDecl>("Range")
        } else { GetCoreDecl(ctx, "Range") as StructDecl }
        if (re.decl.isNone()) {
            if (let Some(diag) <- impl.diag) {
                Diagnose(diag, re, BasicDiagKind.sema_no_core_object).Emit()
            }
            return false
        }
        if (!Ty.IsTyCorrect(target)) {
            return false
        }
        let synAndCheckRangeTy = { =>
            re.SetTy(SynRangeExpr(ctx, re))
            let isWellTyped = impl.typeManager.IsSubtype(re.GetTy().getOrThrow(), target)
            if (!isWellTyped && Ty.IsTyCorrect(re.GetTy())) {
                if (let Some(diag2) <- impl.diag) { DiagMismatchedTypes(diag2, re, target) }
            }
            isWellTyped
        }
        let targetTy = UnboxOptionType(target)
        if (!Ty.IsTyCorrect(targetTy) || (!targetTy.IsStruct() && !targetTy.IsInterface())) {
            let _ = synAndCheckRangeTy()
            re.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        var rangeTy = targetTy
        if (targetTy.IsInterface()) {
            let candiTys = Promotion(impl.typeManager).Downgrade(
                re.decl.getOrThrow().GetTy().getOrThrow(), target)
            if (candiTys.IsEmpty()) {
                if (synAndCheckRangeTy()) { return true }
                if (let Some(diag3) <- impl.diag) { DiagUnableToInferExpr(diag3, re) }
                return false
            }
            rangeTy = candiTys.values[0]
        } else if (!targetTy.IsRange() || rangeTy.typeArgs.size != 1) {
            return synAndCheckRangeTy()
        }
        if (!CheckRangeElements(ctx, rangeTy.typeArgs[0], re)) { return false }
        re.SetTy(rangeTy)
        let isWellTyped2 = impl.typeManager.IsSubtype(re.GetTy().getOrThrow(), target)
        if (!isWellTyped2) {
            if (let Some(diag4) <- impl.diag) { DiagMismatchedTypes(diag4, re, target) }
        }
        return isWellTyped2
    }
}
