package cjcj::sema.TypeCheckExpr

import cjcj::ast.*
import cjcj::basic.DiagKind as BasicDiagKind
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::sema.*

private func invalidTypeConvExpr(tce: TypeConvExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    tce.SetTy(invalidTy)
    return invalidTy
}

extend TypeChecker {
    private func SynNumTypeConvExpr(tce: TypeConvExpr): Ty {
        if ((let None <- tce.typeNode) || (let None <- tce.expr) ||
            (tce.typeNode.getOrThrow() as PrimitiveType).isNone()) {
            return invalidTypeConvExpr(tce)
        }
        let primitiveType = (tce.typeNode.getOrThrow() as PrimitiveType).getOrThrow()
        let targetTy = TypeManager.GetPrimitiveTy(primitiveType.kind)
        tce.SetTy(targetTy)
        let expr = tce.expr.getOrThrow()
        if (!Ty.IsTyCorrect(expr.GetTy()) || !Ty.IsTyCorrect(tce.GetTy())) {
            return invalidTypeConvExpr(tce)
        }
        let exprTy = expr.GetTy().getOrThrow()
        let isExprNothing = (targetTy.IsRune() || targetTy.IsNumeric()) && exprTy.IsNothing()
        let isRuneToUInt32 = targetTy.kind == TypeKind.TYPE_UINT32 && exprTy.kind == TypeKind.TYPE_RUNE
        let isIntegerToRune = targetTy.kind == TypeKind.TYPE_RUNE && exprTy.IsInteger()
        let isBetweenNumeric = targetTy.IsNumeric() && exprTy.IsNumeric()
        if (isExprNothing || isRuneToUInt32 || isIntegerToRune || isBetweenNumeric) {
            return targetTy
        }
        if (!CanSkipDiag(expr)) {
            if (let Some(diag) <- impl.diag) {
                Diagnose(diag, expr, BasicDiagKind.sema_numeric_convert_must_be_numeric).Emit()
            }
        }
        return invalidTypeConvExpr(tce)
    }

    func SynTypeConvExpr(ctx: ASTContext, tce: TypeConvExpr): Ty {
        if ((let None <- tce.expr) || (let None <- tce.typeNode)) {
            return invalidTypeConvExpr(tce)
        }
        let expr = tce.expr.getOrThrow()
        let _ = Synthesize(ctx, SynPos.EXPR_ARG, expr)
        let _ = ReplaceIdealTy(impl.typeManager, expr, diag: impl.diag)
        if (tce.typeNode.getOrThrow().astKind == ASTKind.PRIMITIVE_TYPE) {
            return SynNumTypeConvExpr(tce)
        }
        return invalidTypeConvExpr(tce)
    }

    func ChkTypeConvExpr(ctx: ASTContext, targetTy: Ty, tce: TypeConvExpr): Bool {
        if (Ty.IsTyCorrect(SynTypeConvExpr(ctx, tce)) &&
            impl.typeManager.IsSubtype(tce.GetTy().getOrThrow(), targetTy)) {
            return true
        }
        if (!CanSkipDiag(tce)) {
            if (let Some(diag) <- impl.diag) { DiagMismatchedTypes(diag, tce, targetTy) }
        }
        let _ = invalidTypeConvExpr(tce)
        return false
    }
}
