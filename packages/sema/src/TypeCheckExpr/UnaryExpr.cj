package cangjie_compiler::sema.TypeCheckExpr

import cangjie_compiler::ast.*
import cangjie_compiler::sema.TypeCompatibility
import cangjie_compiler::sema.TypeManager

private func UnaryCandidateReturnKind(op: TokenKind, operandKind: TypeKind): TypeKind {
    if (op == TokenKind.SUB) {
        if (operandKind == TypeKind.TYPE_INT8 || operandKind == TypeKind.TYPE_INT16 ||
            operandKind == TypeKind.TYPE_INT32 || operandKind == TypeKind.TYPE_INT64 ||
            operandKind == TypeKind.TYPE_INT_NATIVE || operandKind == TypeKind.TYPE_UINT8 ||
            operandKind == TypeKind.TYPE_UINT16 || operandKind == TypeKind.TYPE_UINT32 ||
            operandKind == TypeKind.TYPE_UINT64 || operandKind == TypeKind.TYPE_UINT_NATIVE ||
            operandKind == TypeKind.TYPE_IDEAL_INT || operandKind == TypeKind.TYPE_FLOAT16 ||
            operandKind == TypeKind.TYPE_FLOAT32 || operandKind == TypeKind.TYPE_FLOAT64 ||
            operandKind == TypeKind.TYPE_IDEAL_FLOAT) {
            return operandKind
        }
    }
    if (op == TokenKind.NOT) {
        if (operandKind == TypeKind.TYPE_BOOLEAN || operandKind == TypeKind.TYPE_INT8 ||
            operandKind == TypeKind.TYPE_INT16 || operandKind == TypeKind.TYPE_INT32 ||
            operandKind == TypeKind.TYPE_INT64 || operandKind == TypeKind.TYPE_INT_NATIVE ||
            operandKind == TypeKind.TYPE_UINT8 || operandKind == TypeKind.TYPE_UINT16 ||
            operandKind == TypeKind.TYPE_UINT32 || operandKind == TypeKind.TYPE_UINT64 ||
            operandKind == TypeKind.TYPE_UINT_NATIVE || operandKind == TypeKind.TYPE_IDEAL_INT) {
            return operandKind
        }
    }
    return TypeKind.TYPE_INVALID
}

private func IsBuiltinUnaryOperator(op: TokenKind): Bool {
    return op == TokenKind.SUB || op == TokenKind.NOT
}

private func GetNonParenExpr(expr: Expr): Expr {
    var current = expr
    var keepGoing = true
    while (keepGoing) {
        if (let Some(parenExpr) <- (current as ParenExpr)) {
            if (let Some(innerExpr) <- parenExpr.expr) {
                current = innerExpr
            } else {
                keepGoing = false
            }
        } else {
            keepGoing = false
        }
    }
    return current
}

public func GetLeafUnaryExpr(ue: UnaryExpr): UnaryExpr {
    var leaf = ue
    var keepGoing = true
    while (keepGoing) {
        if (let Some(innerExpr) <- leaf.expr) {
            let bareExpr = GetNonParenExpr(innerExpr)
            if (let Some(nextLeaf) <- (bareExpr as UnaryExpr)) {
                if (let Some(_) <- nextLeaf.desugarExpr) {
                    keepGoing = false
                } else {
                    leaf = nextLeaf
                }
            } else {
                keepGoing = false
            }
        } else {
            keepGoing = false
        }
    }
    return leaf
}

public func IsBuiltinUnaryExpr(op: TokenKind, ty: Ty): Bool {
    return UnaryCandidateReturnKind(op, ty.kind) != TypeKind.TYPE_INVALID
}

public func SynBuiltinUnaryExpr(typeManager: TypeManager, ue: UnaryExpr): Ty {
    if (!IsBuiltinUnaryOperator(ue.op)) {
        ue.SetTy(TypeManager.GetInvalidTy())
        return TypeManager.GetInvalidTy()
    }
    if (let Some(innerExpr) <- ue.expr) {
        if (let Some(innerTy) <- innerExpr.GetTy()) {
            if (!Ty.IsTyCorrect(innerTy)) {
                ue.SetTy(TypeManager.GetInvalidTy())
                return TypeManager.GetInvalidTy()
            }
            let retKind = UnaryCandidateReturnKind(ue.op, innerTy.kind)
            if (retKind != TypeKind.TYPE_INVALID) {
                let retTy = TypeManager.GetPrimitiveTy(retKind)
                ue.SetTy(retTy)
                return retTy
            }
            if (innerTy.IsGeneric()) {
                ue.SetTy(innerTy)
                return innerTy
            }
            let numericCandidate = TypeManager.GetPrimitiveTy(if (innerTy.IsFloating()) {
                TypeKind.TYPE_FLOAT64
            } else if (innerTy.IsBoolean()) {
                TypeKind.TYPE_BOOLEAN
            } else {
                TypeKind.TYPE_INT64
            })
            if (typeManager.IsSubtype(innerTy, numericCandidate)) {
                ue.SetTy(innerTy)
                return innerTy
            }
        }
    }
    ue.SetTy(TypeManager.GetInvalidTy())
    return TypeManager.GetInvalidTy()
}

public func SynUnaryExpr(typeManager: TypeManager, ue: UnaryExpr): Ty {
    if (let Some(desugar) <- ue.desugarExpr) {
        if (let Some(desugarTy) <- desugar.GetTy()) {
            ue.SetTy(desugarTy)
            return desugarTy
        }
    }
    let builtinTy = SynBuiltinUnaryExpr(typeManager, ue)
    if (Ty.IsTyCorrect(builtinTy)) {
        if (let Some(innerExpr) <- ue.expr) {
            if (let Some(innerTy) <- innerExpr.GetTy()) {
                if (innerTy.IsIdeal()) {
                    let replacedTy = typeManager.ReplaceIdealTy(innerTy)
                    innerExpr.SetTy(replacedTy)
                    ue.SetTy(replacedTy)
                    return replacedTy
                }
            }
        }
        return builtinTy
    }
    ue.SetTy(TypeManager.GetInvalidTy())
    return TypeManager.GetInvalidTy()
}

public func ChkUnaryExpr(typeManager: TypeManager, target: Ty, ue: UnaryExpr): Bool {
    let retTy = SynUnaryExpr(typeManager, ue)
    if (!Ty.IsTyCorrect(retTy) || !Ty.IsTyCorrect(target)) {
        ue.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    if (typeManager.CheckTypeCompatibility(target, retTy) == TypeCompatibility.INCOMPATIBLE) {
        ue.SetTy(TypeManager.GetInvalidTy())
        return false
    }
    return true
}
