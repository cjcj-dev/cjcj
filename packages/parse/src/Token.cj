package cangjie_compiler::parse

public import cangjie_compiler::lex.{
    GetContextualKeyword, GetEscapeTokenKinds, INVALID_PRECEDENCE, IsContextualKeyword, IsExperimental, Len,
    NUM_TOKENS, StringPart, StringPartKind, StringPartKindIndex, Token, TokenKind, TokenKindIndex, TokenKindLiteral,
    TokenKindValue, TokenPrecedence, TokenVecMap
}

public func ConvertToken(token: Token): String {
    if (!token.Value().isEmpty()) {
        return token.Value()
    }
    return TokenKindName(token.kind)
}

public func TokenKindName(kind: TokenKind): String {
    return match (kind) {
        case TokenKind.IDENTIFIER => "identifier"
        case TokenKind.PACKAGE_IDENTIFIER => "package identifier"
        case TokenKind.INTEGER_LITERAL => "integer literal"
        case TokenKind.FLOAT_LITERAL => "floating literal"
        case TokenKind.STRING_LITERAL => "string literal"
        case TokenKind.RUNE_LITERAL => "rune literal"
        case TokenKind.BOOL_LITERAL => "boolean literal"
        case TokenKind.NL => "newline"
        case TokenKind.END => "end of file"
        case TokenKind.ILLEGAL => "illegal token"
        case _ =>
            let literal = TokenKindLiteral(kind)
            if (!literal.isEmpty()) {
                return literal
            }
            return TokenKindValue(kind)
    }
}
