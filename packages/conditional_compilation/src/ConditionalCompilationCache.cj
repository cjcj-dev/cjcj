package cangjie_compiler::conditional_compilation

import cangjie_compiler::ast.*

private func EncodedField(value: String): String {
    return value.size.toString() + ":" + value + ";"
}

func MakeJudgeConditionCacheKey(condition: String, op: TokenKind, right: String): String {
    return EncodedField(condition) + TokenKindIndex(op).toString() + ";" + EncodedField(right)
}

private func LitConstKindCacheIndex(kind: LitConstKind): Int64 {
    return match (kind) {
        case LitConstKind.INTEGER => 0
        case LitConstKind.RUNE_BYTE => 1
        case LitConstKind.FLOAT => 2
        case LitConstKind.RUNE => 3
        case LitConstKind.STRING => 4
        case LitConstKind.JSTRING => 5
        case LitConstKind.BOOL => 6
        case LitConstKind.UNIT => 7
        case LitConstKind.NONE => 8
    }
}

func MakeConditionExprCacheKey(condition: Expr): Option<String> {
    match (condition.astKind) {
        case ASTKind.BINARY_EXPR | ASTKind.UNARY_EXPR | ASTKind.REF_EXPR | ASTKind.PAREN_EXPR =>
            return AppendConditionExprCacheKey(condition)
        case _ => return None
    }
}

private func AppendConditionExprCacheKey(condition: Expr): Option<String> {
    var key = ASTKindIndex(condition.astKind).toString() + ";"
    if (condition.astKind == ASTKind.BINARY_EXPR) {
        if (let Some(be) <- (condition as BinaryExpr)) {
            if (let Some(left) <- be.leftExpr) {
                if (let Some(right) <- be.rightExpr) {
                    if (let Some(leftKey) <- AppendConditionExprCacheKey(left)) {
                        if (let Some(rightKey) <- AppendConditionExprCacheKey(right)) {
                            key += TokenKindIndex(be.op).toString() + ";" + leftKey + rightKey
                            return key
                        }
                    }
                }
            }
        }
        return None
    }
    if (condition.astKind == ASTKind.UNARY_EXPR) {
        if (let Some(ue) <- (condition as UnaryExpr)) {
            if (let Some(expr) <- ue.expr) {
                if (let Some(exprKey) <- AppendConditionExprCacheKey(expr)) {
                    key += TokenKindIndex(ue.op).toString() + ";" + exprKey
                    return key
                }
            }
        }
        return None
    }
    if (condition.astKind == ASTKind.REF_EXPR) {
        if (let Some(re) <- (condition as RefExpr)) {
            key += EncodedField(re.ref.identifier.Val())
            return key
        }
        return None
    }
    if (condition.astKind == ASTKind.PAREN_EXPR) {
        if (let Some(pe) <- (condition as ParenExpr)) {
            if (let Some(expr) <- pe.expr) {
                if (let Some(exprKey) <- AppendConditionExprCacheKey(expr)) {
                    key += exprKey
                    return key
                }
            }
        }
        return None
    }
    if (condition.astKind == ASTKind.LIT_CONST_EXPR) {
        if (let Some(lit) <- (condition as LitConstExpr)) {
            let hasSIExpr = if (let Some(_) <- lit.siExpr) { "1" } else { "0" }
            key += LitConstKindCacheIndex(lit.kind).toString() + ";" + hasSIExpr + ";" +
                EncodedField(lit.stringValue)
            return key
        }
        return None
    }
    return None
}
