package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func SeeingModifier(): Bool {
        return Seeing(TokenKind.STATIC, TokenKind.OPERATOR) || Seeing(TokenKind.CONST) ||
            Seeing(TokenKind.COMMON) || Seeing(TokenKind.SPECIFIC)
    }

    public func ParseModifiers(modifiers: ArrayList<Modifier>): Unit {
        while (SeeingModifier() && !SeeingKeywordAndOperater()) {
            let token = Peek()
            let modifier = Modifier(token.kind, token.Begin())
            modifier.curFile = currentFile
            for (existing in modifiers) {
                if (existing.modifier == token.kind) {
                    DiagDuplicatedModifier(modifier, existing)
                }
            }
            modifiers.add(modifier)
            Next()
        }
    }
}
