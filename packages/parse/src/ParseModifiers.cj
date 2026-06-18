package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func SeeingModifier(): Bool {
        return ModifierKindFromToken(Peek().kind).isSome()
    }

    public func ParseModifiers(modifiers: ArrayList<Modifier>): Unit {
        while (true) {
            let token = Peek()
            if (let Some(kind) <- ModifierKindFromToken(token.kind)) {
                Next()
                let modifier = Modifier(token.kind, token.Begin())
                for (existing in modifiers) {
                    if (existing.modifier == token.kind) {
                        diag.DiagnoseRefactor(DiagKindRefactor.DUPLICATED_MODIFIER, token.Begin(), "duplicated modifier '${token.Value()}'")
                    }
                }
                modifiers.add(modifier)
                let _ = kind
                continue
            }
            break
        }
    }
}

public func ModifierKindFromToken(kind: TokenKind): Option<ModifierKind> {
    if (kind == TokenKind.PUBLIC) { return ModifierKind.PUBLIC }
    if (kind == TokenKind.PROTECTED) { return ModifierKind.PROTECTED }
    if (kind == TokenKind.INTERNAL) { return ModifierKind.INTERNAL }
    if (kind == TokenKind.PRIVATE) { return ModifierKind.PRIVATE }
    if (kind == TokenKind.STATIC) { return ModifierKind.STATIC }
    if (kind == TokenKind.ABSTRACT) { return ModifierKind.ABSTRACT }
    if (kind == TokenKind.OPEN) { return ModifierKind.OPEN }
    if (kind == TokenKind.SEALED) { return ModifierKind.SEALED }
    if (kind == TokenKind.OVERRIDE) { return ModifierKind.OVERRIDE }
    if (kind == TokenKind.REDEF) { return ModifierKind.REDEF }
    if (kind == TokenKind.FOREIGN) { return ModifierKind.FOREIGN }
    if (kind == TokenKind.INOUT) { return ModifierKind.INOUT }
    if (kind == TokenKind.MUT) { return ModifierKind.MUT }
    if (kind == TokenKind.UNSAFE) { return ModifierKind.UNSAFE }
    if (kind == TokenKind.OPERATOR) { return ModifierKind.OPERATOR }
    if (kind == TokenKind.CONST) { return ModifierKind.CONST }
    if (kind == TokenKind.COMMON) { return ModifierKind.COMMON }
    if (kind == TokenKind.SPECIFIC) { return ModifierKind.SPECIFIC }
    return None
}
