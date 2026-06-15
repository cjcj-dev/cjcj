package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private func invalidTypeConvExpr(tce: TypeConvExpr): Ty {
    let invalidTy = TypeManager.GetInvalidTy()
    tce.SetTy(invalidTy)
    return invalidTy
}

private func validExprTy(typeManager: TypeManager, expr: Expr): Option<Ty> {
    if (let Some(exprTy) <- expr.GetTy()) {
        if (exprTy.HasInvalidTy()) {
            return None
        }
        if (exprTy.IsIdeal()) {
            let concreteTy = typeManager.ReplaceIdealTy(exprTy)
            expr.SetTy(concreteTy)
            return concreteTy
        }
        return exprTy
    }
    return None
}

public func SynNumTypeConvExpr(typeManager: TypeManager, tce: TypeConvExpr): Ty {
    if (let Some(typeNode) <- tce.typeNode) {
        if (let Some(primitiveType) <- (typeNode as PrimitiveType)) {
            let targetTy = TypeManager.GetPrimitiveTy(primitiveType.kind)
            tce.SetTy(targetTy)
            if (let Some(exprNode) <- tce.expr) {
                if (let Some(exprTy) <- validExprTy(typeManager, exprNode)) {
                    let isExprNothing = (targetTy.IsRune() || targetTy.IsNumeric()) && exprTy.IsNothing()
                    let isRuneToUInt32 = targetTy.kind == TypeKind.TYPE_UINT32 && exprTy.kind == TypeKind.TYPE_RUNE
                    let isIntegerToRune = targetTy.kind == TypeKind.TYPE_RUNE && exprTy.IsInteger()
                    let isBetweenNumeric = targetTy.IsNumeric() && exprTy.IsNumeric()
                    if (isExprNothing || isRuneToUInt32 || isIntegerToRune || isBetweenNumeric) {
                        return targetTy
                    }
                }
            }
        }
    }
    return invalidTypeConvExpr(tce)
}

public func SynTypeConvExpr(typeManager: TypeManager, tce: TypeConvExpr): Ty {
    if (let Some(typeNode) <- tce.typeNode) {
        if (let Some(_) <- tce.expr) {
            if (typeNode.astKind == ASTKind.PRIMITIVE_TYPE) {
                return SynNumTypeConvExpr(typeManager, tce)
            }
        }
    }
    return invalidTypeConvExpr(tce)
}

public func ChkTypeConvExpr(typeManager: TypeManager, targetTy: Ty, tce: TypeConvExpr): Bool {
    let convertedTy = SynTypeConvExpr(typeManager, tce)
    if (!convertedTy.HasInvalidTy() && typeManager.IsSubtype(convertedTy, targetTy)) {
        return true
    }
    let _ = invalidTypeConvExpr(tce)
    return false
}
