package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParseQuoteExpr(): QuoteExpr {
        let ret = QuoteExpr()
        let token = Expect(TokenKind.QUOTE, "expected 'quote'")
        ret.begin = token.Begin()
        if (Skip(TokenKind.LPAREN)) {
            var depth: Int64 = 1
            while (!Seeing(TokenKind.END) && depth > 0) {
                let current = Peek()
                Next()
                if (current.kind == TokenKind.LPAREN) { depth++ }
                if (current.kind == TokenKind.RPAREN) {
                    depth--
                    if (depth == 0) { break }
                }
                ret.tokens.add(current)
            }
        } else if (Skip(TokenKind.LCURL)) {
            var depth: Int64 = 1
            while (!Seeing(TokenKind.END) && depth > 0) {
                let current = Peek()
                Next()
                if (current.kind == TokenKind.LCURL) { depth++ }
                if (current.kind == TokenKind.RCURL) {
                    depth--
                    if (depth == 0) { break }
                }
                ret.tokens.add(current)
            }
        }
        ret.end = lastToken.End()
        return ret
    }
}
