package cangjie_compiler::conditional_compilation

import cangjie_compiler::ast.*

private func AppendCacheField(key: StringBuilder, field: String): Unit {
    key.append(field)
    key.append(String.fromUtf8([0u8]))
}

private func AppendEnumCacheField(key: StringBuilder, value: Int64): Unit {
    key.append(value.toString())
    key.append(String.fromUtf8([0u8]))
}

private func AppendEnumCacheField(key: StringBuilder, value: ASTKind): Unit {
    AppendEnumCacheField(key, ASTKindIndex(value))
}

private func AppendEnumCacheField(key: StringBuilder, value: TokenKind): Unit {
    AppendEnumCacheField(key, TokenKindIndex(value))
}

private func AppendEnumCacheField(key: StringBuilder, value: LitConstKind): Unit {
    AppendEnumCacheField(key, LitConstKindIndex(value))
}

func MakeJudgeConditionCacheKey(condition: String, op: TokenKind, right: String): String {
    let key = StringBuilder()
    key.append(condition)
    key.append(String.fromUtf8([0u8]))
    key.append(String.fromUtf8([UInt8(TokenKindIndex(op))]))
    key.append(String.fromUtf8([0u8]))
    key.append(right)
    return key.toString()
}

func MakeConditionExprCacheKey(condition: Expr): Option<String> {
    if (condition.astKind != ASTKind.BINARY_EXPR && condition.astKind != ASTKind.UNARY_EXPR &&
        condition.astKind != ASTKind.REF_EXPR && condition.astKind != ASTKind.PAREN_EXPR) {
        return None
    }
    let key = StringBuilder()
    if (!AppendConditionExprCacheKey(condition, key)) {
        return None
    }
    return key.toString()
}

private func AppendConditionExprCacheKey(condition: Expr, key: StringBuilder): Bool {
    AppendEnumCacheField(key, condition.astKind)
    if (condition.astKind == ASTKind.BINARY_EXPR) {
        if (let Some(be) <- (condition as BinaryExpr)) {
            if (let Some(left) <- be.leftExpr) {
                if (let Some(right) <- be.rightExpr) {
                    AppendEnumCacheField(key, be.op)
                    return AppendConditionExprCacheKey(left, key) && AppendConditionExprCacheKey(right, key)
                }
            }
        }
        return false
    }
    if (condition.astKind == ASTKind.UNARY_EXPR) {
        if (let Some(ue) <- (condition as UnaryExpr)) {
            if (let Some(expr) <- ue.expr) {
                AppendEnumCacheField(key, ue.op)
                return AppendConditionExprCacheKey(expr, key)
            }
        }
        return false
    }
    if (condition.astKind == ASTKind.REF_EXPR) {
        if (let Some(re) <- (condition as RefExpr)) {
            AppendCacheField(key, re.ref.identifier.Val())
            return true
        }
        return false
    }
    if (condition.astKind == ASTKind.PAREN_EXPR) {
        if (let Some(pe) <- (condition as ParenExpr)) {
            if (let Some(expr) <- pe.expr) {
                return AppendConditionExprCacheKey(expr, key)
            }
        }
        return false
    }
    if (condition.astKind == ASTKind.LIT_CONST_EXPR) {
        if (let Some(lit) <- (condition as LitConstExpr)) {
            AppendEnumCacheField(key, lit.kind)
            key.append(if (let Some(_) <- lit.siExpr) { "1" } else { "0" })
            key.append(String.fromUtf8([0u8]))
            AppendCacheField(key, lit.stringValue)
            return true
        }
        return false
    }
    return false
}
