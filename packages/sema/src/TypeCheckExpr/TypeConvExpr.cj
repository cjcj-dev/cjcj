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

public func SynNumTypeConvExpr(tce: TypeConvExpr,
    diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(typeNode) <- tce.typeNode) {
        if (let Some(primitiveType) <- (typeNode as PrimitiveType)) {
            let targetTy = TypeManager.GetPrimitiveTy(primitiveType.kind)
            tce.SetTy(targetTy)
            if (let Some(exprNode) <- tce.expr) {
                if (Ty.IsTyCorrect(exprNode.GetTy()) && Ty.IsTyCorrect(tce.GetTy())) {
                    let exprTy = exprNode.GetTy().getOrThrow()
                    let isExprNothing = (targetTy.IsRune() || targetTy.IsNumeric()) && exprTy.IsNothing()
                    let isRuneToUInt32 = targetTy.kind == TypeKind.TYPE_UINT32 && exprTy.kind == TypeKind.TYPE_RUNE
                    let isIntegerToRune = targetTy.kind == TypeKind.TYPE_RUNE && exprTy.IsInteger()
                    let isBetweenNumeric = targetTy.IsNumeric() && exprTy.IsNumeric()
                    if (isExprNothing || isRuneToUInt32 || isIntegerToRune || isBetweenNumeric) {
                        return targetTy
                    }
                    if (!CanSkipDiag(exprNode)) {
                        if (let Some(diagValue) <- diag) {
                            let builder = diagValue.Diagnose(
                                exprNode.begin, exprNode.end, BasicDiagKind.sema_numeric_convert_must_be_numeric)
                            builder.Emit()
                        }
                    }
                }
            }
        }
    }
    return invalidTypeConvExpr(tce)
}

public func SynTypeConvExpr(typeManager: TypeManager, tce: TypeConvExpr,
    synthesizer!: Option<(Expr) -> Ty> = None, diag!: Option<BasicDiagnosticEngine> = None): Ty {
    if (let Some(typeNode) <- tce.typeNode) {
        if (let Some(exprNode) <- tce.expr) {
            if (let Some(syn) <- synthesizer) {
                let _ = syn(exprNode)
            } else if (exprNode.GetTy().isNone() || Ty.IsInitialTy(exprNode.GetTy())) {
                let _ = SynExprShallow(typeManager, exprNode, diag: diag)
            }
            let _ = ReplaceIdealTy(typeManager, exprNode, diag: diag)
            if (typeNode.astKind == ASTKind.PRIMITIVE_TYPE) {
                return SynNumTypeConvExpr(tce, diag: diag)
            }
        }
    }
    return invalidTypeConvExpr(tce)
}

public func ChkTypeConvExpr(typeManager: TypeManager, targetTy: Ty, tce: TypeConvExpr,
    synthesizer!: Option<(Expr) -> Ty> = None, diag!: Option<BasicDiagnosticEngine> = None): Bool {
    let convertedTy = SynTypeConvExpr(typeManager, tce, synthesizer: synthesizer, diag: diag)
    if (!convertedTy.HasInvalidTy() && typeManager.IsSubtype(convertedTy, targetTy)) {
        return true
    }
    if (!CanSkipDiag(tce)) {
        if (let Some(diagValue) <- diag) {
            DiagMismatchedTypes(diagValue, tce, targetTy)
        }
    }
    let _ = invalidTypeConvExpr(tce)
    return false
}
