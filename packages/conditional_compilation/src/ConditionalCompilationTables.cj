package cjcj::conditional_compilation

import cjcj::ast.*

let TARGET_CONDITION: Array<String> = [
    BACKEND_STR,
    ARCH_STR,
    OS_STR,
    CJC_VERSION_STR,
    DEBUG_STR,
    TEST_STR,
    ENV_STR
]

let CONDITION_OP: Array<(String, Array<TokenKind>)> = [
    (BACKEND_STR, [TokenKind.EQUAL, TokenKind.NOTEQ]),
    (ARCH_STR, [TokenKind.EQUAL, TokenKind.NOTEQ]),
    (OS_STR, [TokenKind.EQUAL, TokenKind.NOTEQ]),
    (CJC_VERSION_STR, [
        TokenKind.EQUAL,
        TokenKind.NOTEQ,
        TokenKind.GT,
        TokenKind.LT,
        TokenKind.GE,
        TokenKind.LE
    ]),
    (DEBUG_STR, []),
    (TEST_STR, []),
    (ENV_STR, [TokenKind.EQUAL, TokenKind.NOTEQ])
]

let CONDITION_VALUES: Array<(String, Array<String>)> = [
    (BACKEND_STR, ["cjnative"]),
    (ARCH_STR, ["x86_64", "aarch64", "arm"]),
    (OS_STR, ["Windows", "Linux", "macOS", "iOS"]),
    (ENV_STR, ["", "gnu", "ohos", "simulator", "android"])
]

func IsTargetCondition(name: String): Bool {
    return TARGET_CONDITION.contains(name)
}

func IsLogicBinaryExpr(op: TokenKind): Bool {
    return match (op) {
        case TokenKind.AND | TokenKind.OR => true
        case _ => false
    }
}

func IsJudgeBinaryExpr(op: TokenKind): Bool {
    return match (op) {
        case TokenKind.NOTEQ | TokenKind.EQUAL => true
        case _ => false
    }
}

func IsRangeBinaryExpr(op: TokenKind): Bool {
    return match (op) {
        case TokenKind.LT | TokenKind.GT | TokenKind.LE | TokenKind.GE => true
        case _ => false
    }
}

func ConditionSupportsOp(conditionStr: String, op: TokenKind): Bool {
    for ((condition, ops) in CONDITION_OP) {
        if (condition == conditionStr) {
            return ops.contains(op)
        }
    }
    return true
}

func ConditionSupportsValue(conditionStr: String, right: String): Bool {
    let values = ConditionValues(conditionStr)
    if (values.isEmpty()) {
        return true
    }
    return values.contains(right)
}

func SupportedValuesText(conditionStr: String): String {
    let values = ConditionValues(conditionStr)
    var out = ""
    var idx: Int64 = 0
    while (idx < values.size) {
        if (idx > 0) {
            out += " "
        }
        out += values[idx]
        idx++
    }
    return out
}

private func ConditionValues(conditionStr: String): Array<String> {
    for ((condition, values) in CONDITION_VALUES) {
        if (condition == conditionStr) {
            return values
        }
    }
    return []
}
