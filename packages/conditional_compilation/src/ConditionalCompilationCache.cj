package cjcj::conditional_compilation

import cjcj::ast.*

func MakeJudgeConditionCacheKey(condition: String, op: TokenKind, right: String): String {
    let key = StringBuilder()
    key.append(condition)
    key.append(String.fromUtf8([0u8]))
    key.append(String.fromUtf8([UInt8(TokenKindIndex(op))]))
    key.append(String.fromUtf8([0u8]))
    key.append(right)
    return key.toString()
}
