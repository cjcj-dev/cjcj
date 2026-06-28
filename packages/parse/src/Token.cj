package cangjie_compiler::parse

public import cangjie_compiler::lex.{
    GetContextualKeyword, GetEscapeTokenKinds, INVALID_PRECEDENCE, IsContextualKeyword, IsExperimental, Len,
    Lexer, NUM_TOKENS, StringPart, StringPartKind, StringPartKindIndex, Token, TokenKind, TokenKindIndex,
    TokenKindLiteral, TokenKindValue, TokenPrecedence, TokenVecMap
}

public func ConvertToken(token: Token): String {
    if (token.kind == TokenKind.END) {
        return "'<EOF>'"
    }
    if (token.kind == TokenKind.NL) {
        return "'<NL>'"
    }
    if (IsKeyWord(token)) {
        return "keyword '" + TokenKindLiteral(token.kind) + "'"
    }
    if (token.kind == TokenKind.INTEGER_LITERAL || token.kind == TokenKind.FLOAT_LITERAL) {
        return "literal '" + token.Value() + "'"
    }
    if (token.kind == TokenKind.BOOL_LITERAL || token.kind == TokenKind.IDENTIFIER ||
        token.kind == TokenKind.PACKAGE_IDENTIFIER) {
        return "'" + token.Value() + "'"
    }
    return "'" + TokenKindLiteral(token.kind) + "'"
}

func IsKeyWord(token: Token): Bool {
    let kindIndex = TokenKindIndex(token.kind)
    let int8Index = TokenKindIndex(TokenKind.INT8)
    let identifierIndex = TokenKindIndex(TokenKind.IDENTIFIER)
    return ((kindIndex >= int8Index && kindIndex < identifierIndex) && token.kind != TokenKind.DOLLAR &&
        token.kind != TokenKind.UPPERBOUND) || token.kind == TokenKind.AS || token.kind == TokenKind.IS
}
