package cjcj::sema.TypeCheckExpr

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagArgument as BasicDiagArgument
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagKindRefactor as BasicDiagKindRefactor
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*
import cjcj::sema.Desugar.*
import cjcj::utils.CJC_ASSERT

public func ChkSubscriptExpr(typeManager: TypeManager, ctx: ASTContext, target: Option<Ty>,
    se: SubscriptExpr, synthesizer: (SynPos, Expr) -> Ty, checker: (Ty, Expr) -> Bool,
    diag: BasicDiagnosticEngine): Bool {
    if (let Some(desugarExpr) <- se.desugarExpr) {
        if (let Some(targetTy) <- target) {
            return typeManager.IsSubtype(desugarExpr.GetTy().getOrThrow(), targetTy)
        }
        return false
    }
    se.SetTy(TypeManager.GetInvalidTy())
    if (se.baseExpr.isNone() || se.indexExprs.isEmpty()) {
        return false
    }
    let baseExpr = se.baseExpr.getOrThrow()
    SetIsNotAlone(baseExpr)
    var baseTy = synthesizer(SynPos.EXPR_ARG, baseExpr)
    let indexTys = ArrayList<Ty>()
    for (indexExpr in se.indexExprs) {
        indexTys.add(synthesizer(SynPos.EXPR_ARG, indexExpr))
    }
    if (!Ty.IsTyCorrect(baseTy) || !Ty.AreTysCorrect(indexTys)) {
        return false
    }
    if (let Some(tupleTy) <- (baseTy as TupleTy)) {
        if (se.indexExprs.size == 1) {
            se.isTupleAccess = true
            return ChkTupleAccess(typeManager, ctx, target, se, tupleTy, checker, diag)
        }
    }
    if (let Some(varrayTy) <- (baseTy as VArrayTy)) {
        return ChkVArrayAccess(typeManager, ctx, target, se, varrayTy, checker, diag)
    }
    try (ds = DiagSuppressor(diag)) {
        DesugarOperatorOverloadExpr(ctx, se)
        let desugarExpr = se.desugarExpr.getOrThrow()
        let isWellTyped = if (let Some(targetTy) <- target) {
            checker(targetTy, desugarExpr)
        } else {
            Ty.IsTyCorrect(synthesizer(SynPos.EXPR_ARG, desugarExpr))
        }
        if (isWellTyped) {
            ds.ReportDiag()
            se.SetTy(desugarExpr.GetTy().getOrThrow())
            CJC_ASSERT((desugarExpr as CallExpr).isSome())
            let desugaredCall = (desugarExpr as CallExpr).getOrThrow()
            CJC_ASSERT(desugaredCall.resolvedFunction.isSome())
            let resolvedFunction: Decl = desugaredCall.resolvedFunction.getOrThrow()
            ReplaceTarget(se, Some(resolvedFunction))
            return true
        }
        let synTy = synthesizer(SynPos.EXPR_ARG, desugarExpr)
        let retTyMismatch = target.isSome() && Ty.IsTyCorrect(target.getOrThrow()) && Ty.IsTyCorrect(synTy)
        RecoverToSubscriptExpr(se)
        baseTy = typeManager.ReplaceIdealTy(baseTy)
        let recoveredBase = se.baseExpr.getOrThrow()
        recoveredBase.SetTy(recoveredBase.GetTy() ?? baseTy)
        for (idx in 0..se.indexExprs.size) {
            indexTys[idx] = typeManager.ReplaceIdealTy(indexTys[idx])
            let indexExpr = se.indexExprs[idx]
            indexExpr.SetTy(if (Ty.IsTyCorrect(indexExpr.GetTy())) {
                indexExpr.GetTy().getOrThrow()
            } else {
                indexTys[idx]
            })
        }
        if (!ds.HasError() && se.ShouldDiagnose(allowCompilerAdd: true)) {
            ds.ReportDiag()
            if (retTyMismatch) {
                DiagMismatchedTypesWithFoundTy(diag, se, target.getOrThrow(), synTy)
            } else {
                DiagInvalidSubscriptExpr(diag, se, baseTy, indexTys)
            }
        }
        ds.ReportDiag()
    }
    return false
}

private func ChkTupleAccess(typeManager: TypeManager, ctx: ASTContext, target: Option<Ty>,
    se: SubscriptExpr, tupleTy: TupleTy, checker: (Ty, Expr) -> Bool,
    diag: BasicDiagnosticEngine): Bool {
    if (se.baseExpr.isNone() || se.indexExprs.size != 1) {
        return false
    }
    let indexExpr = se.indexExprs[0]
    if ((indexExpr as LitConstExpr).isNone()) {
        let builder = Diagnose(diag, indexExpr, BasicDiagKind.sema_builtin_invalid_index,
            args: [BasicDiagArgument("tuple")])
        builder.Emit()
        return false
    }
    if (!checker(TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64), indexExpr)) {
        let builder = Diagnose(diag, indexExpr, BasicDiagKind.sema_builtin_invalid_index,
            args: [BasicDiagArgument("tuple")])
        builder.Emit()
        return false
    }
    let literalIndex = (indexExpr as LitConstExpr).getOrThrow()
    let index = literalIndex.constNumValue.asInt.Uint64()
    if (index >= UInt64(tupleTy.typeArgs.size)) {
        if (se.ShouldDiagnose(allowCompilerAdd: true)) {
            let builder = Diagnose(diag, indexExpr, BasicDiagKind.sema_builtin_index_in_bound,
                args: [BasicDiagArgument("tuple")])
            builder.Emit()
        }
        return false
    }
    let indexValue = Int64(index)
    if (let None <- target) {
        se.SetTy(tupleTy.typeArgs[indexValue])
        return true
    }
    let targetTy = target.getOrThrow()
    if (let Some(tupleLit) <- (se.baseExpr.getOrThrow() as TupleLit)) {
        CJC_ASSERT(indexValue < tupleLit.children.size)
        if (!checker(targetTy, tupleLit.children[indexValue])) {
            tupleLit.SetTy(TypeManager.GetInvalidTy())
            return false
        }
        let elementTys = ArrayList<Ty>()
        for (element in tupleLit.children) {
            if (ReplaceIdealTy(typeManager, element)) {
                elementTys.add(element.GetTy().getOrThrow())
            } else {
                elementTys.add(TypeManager.GetInvalidTy())
            }
        }
        tupleLit.SetTy(typeManager.GetTupleTy(elementTys.toArray()))
        se.SetTy(elementTys[indexValue])
    } else {
        if (!typeManager.IsSubtype(tupleTy.typeArgs[indexValue], targetTy)) {
            DiagMismatchedTypesWithFoundTy(diag, se, targetTy, tupleTy.typeArgs[indexValue])
            return false
        }
        se.SetTy(tupleTy.typeArgs[indexValue])
    }
    return true
}

private func ChkVArrayAccess(typeManager: TypeManager, ctx: ASTContext, target: Option<Ty>,
    se: SubscriptExpr, varrayTy: VArrayTy, checker: (Ty, Expr) -> Bool,
    diag: BasicDiagnosticEngine): Bool {
    if (se.indexExprs.size != 1) {
        let builder = DiagnoseRefactor(diag, BasicDiagKindRefactor.sema_varray_subscript_num, se)
        builder.Emit()
        return false
    }
    try (ds = DiagSuppressor(diag)) {
        let int64Ty = TypeManager.GetPrimitiveTy(TypeKind.TYPE_INT64)
        let indexExpr = se.indexExprs[0]
        if (!checker(int64Ty, indexExpr)) {
            if (!ds.HasError()) {
                DiagMismatchedTypesWithFoundTy(diag, indexExpr, int64Ty, indexExpr.GetTy().getOrThrow())
            }
            ds.ReportDiag()
            return false
        }
        ds.ReportDiag()
    }
    CJC_ASSERT(!varrayTy.typeArgs.isEmpty())
    if (let None <- target) {
        se.SetTy(varrayTy.typeArgs[0])
        return true
    }
    let targetTy = target.getOrThrow()
    if (!typeManager.IsSubtype(varrayTy.typeArgs[0], targetTy)) {
        DiagMismatchedTypesWithFoundTy(diag, se, targetTy, varrayTy.typeArgs[0])
        return false
    }
    se.SetTy(varrayTy.typeArgs[0])
    return true
}

public func SynSubscriptExpr(typeManager: TypeManager, ctx: ASTContext, se: SubscriptExpr,
    synthesizer: (SynPos, Expr) -> Ty, checker: (Ty, Expr) -> Bool,
    diag: BasicDiagnosticEngine): Ty {
    let _ = ChkSubscriptExpr(typeManager, ctx, None, se, synthesizer, checker, diag)
    return se.GetTy().getOrThrow()
}

extend TypeChecker {
}
