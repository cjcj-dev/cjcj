package cangjie_compiler::sema

import cangjie_compiler::ast.*

public func IsBuiltinOperatorToken(kind: TokenKind): Bool {
    return kind == TokenKind.ADD || kind == TokenKind.SUB || kind == TokenKind.MUL || kind == TokenKind.DIV ||
        kind == TokenKind.MOD || kind == TokenKind.EQUAL || kind == TokenKind.NOTEQ || kind == TokenKind.LT ||
        kind == TokenKind.GT || kind == TokenKind.LE || kind == TokenKind.GE
}

public func BuiltinOperatorResultTy(tm: TypeManager, op: TokenKind, lhs: Ty, rhs: Ty): Ty {
    if (op == TokenKind.EQUAL || op == TokenKind.NOTEQ || op == TokenKind.LT || op == TokenKind.GT ||
        op == TokenKind.LE || op == TokenKind.GE) {
        return TypeManager.GetBoolTy()
    }
    if (tm.IsSubtype(lhs, rhs)) {
        return rhs
    }
    return lhs
}
