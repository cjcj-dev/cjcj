package cjcj::parse

import std.collection.*

extend ParserImpl {
    // Leave ordinary identifiers alone unless a declaration modifier follows.
    private func LocalModifier(): Option<TokenKind> {
        if (!compileOptions.IsLocalModeAnalysis() || !Seeing(TokenKind.IDENTIFIER)) { return None }
        let spelling = Peek().Value()
        if (spelling != "demode" && spelling != "exclave") { return None }
        let next = lexer.LookAheadSkipNL(1)
        if (next.isEmpty()) { return None }
        let k = next[0].kind
        if (!(k == TokenKind.VAR || k == TokenKind.LET || k == TokenKind.FUNC || k == TokenKind.INIT ||
            k == TokenKind.CONST || (TokenKindIndex(k) >= TokenKindIndex(TokenKind.STATIC) &&
            TokenKindIndex(k) <= TokenKindIndex(TokenKind.OPERATOR)))) { return None }
        return if (spelling == "demode") { TokenKind.DEMODE } else { TokenKind.EXCLAVE }
    }

    public func SeeingModifier(): Bool {
        return LocalModifier().isSome() || Seeing(TokenKind.STATIC, TokenKind.OPERATOR) || Seeing(TokenKind.CONST) ||
            Seeing(TokenKind.COMMON) || Seeing(TokenKind.SPECIFIC)
    }

    public func ParseModifiers(modifiers: ArrayList<Modifier>): Unit {
        while (SeeingModifier() && !SeeingKeywordAndOperater()) {
            let token = Peek()
            let modifier = Modifier(LocalModifier() ?? token.kind, token.Begin())
            modifier.curFile = currentFile
            for (existing in modifiers) {
                if (existing.modifier == modifier.modifier) {
                    DiagDuplicatedModifier(modifier, existing)
                }
            }
            modifiers.add(modifier)
            Next()
        }
    }
}
