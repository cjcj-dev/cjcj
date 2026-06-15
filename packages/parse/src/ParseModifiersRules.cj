package cangjie_compiler::parse

import std.collection.*

public class ConflictArray {
    public let data: ArrayList<TokenKind> = ArrayList<TokenKind>()
    public init() {}
    public init(items: Array<TokenKind>) {
        for (item in items) { data.add(item) }
    }
    public func size(): Int64 { return data.size }
}

public func HasScopeRules(defKind: DefKind, scopeKind: ScopeKind): Bool {
    return true
}

public func IsScopeRulesEmpty(defKind: DefKind, scopeKind: ScopeKind): Bool {
    return false
}

public func IsModifierAllowed(defKind: DefKind, scopeKind: ScopeKind, modifier: TokenKind): Bool {
    if (defKind == DefKind.PACKAGE) {
        return modifier == TokenKind.MACRO
    }
    if (modifier == TokenKind.PUBLIC || modifier == TokenKind.PRIVATE || modifier == TokenKind.INTERNAL || modifier == TokenKind.PROTECTED) {
        return true
    }
    if (scopeKind == ScopeKind.FUNC_BODY || scopeKind == ScopeKind.MAIN_BODY) {
        return modifier == TokenKind.CONST || modifier == TokenKind.MUT || modifier == TokenKind.UNSAFE
    }
    if (defKind == DefKind.VARIABLE) {
        return modifier == TokenKind.STATIC || modifier == TokenKind.CONST || modifier == TokenKind.UNSAFE ||
            modifier == TokenKind.PUBLIC || modifier == TokenKind.PRIVATE || modifier == TokenKind.INTERNAL ||
            modifier == TokenKind.PROTECTED
    }
    return true
}

public func GetConflictingModifiers(defKind: DefKind, scopeKind: ScopeKind, modifier: TokenKind): ConflictArray {
    if (modifier == TokenKind.PUBLIC || modifier == TokenKind.PRIVATE || modifier == TokenKind.INTERNAL || modifier == TokenKind.PROTECTED) {
        return ConflictArray([TokenKind.PUBLIC, TokenKind.PRIVATE, TokenKind.INTERNAL, TokenKind.PROTECTED])
    }
    if (modifier == TokenKind.OPEN || modifier == TokenKind.SEALED || modifier == TokenKind.ABSTRACT) {
        return ConflictArray([TokenKind.OPEN, TokenKind.SEALED, TokenKind.ABSTRACT])
    }
    if (modifier == TokenKind.COMMON || modifier == TokenKind.SPECIFIC) {
        return ConflictArray([TokenKind.COMMON, TokenKind.SPECIFIC])
    }
    return ConflictArray()
}

public func HasWarningRules(defKind: DefKind, scopeKind: ScopeKind): Bool {
    return true
}

public func GetWarningConflicts(defKind: DefKind, scopeKind: ScopeKind, modifier: TokenKind): ConflictArray {
    if (modifier == TokenKind.UNSAFE && (defKind == DefKind.CLASS || defKind == DefKind.STRUCT || defKind == DefKind.INTERFACE)) {
        return ConflictArray([TokenKind.UNSAFE])
    }
    return ConflictArray()
}

public func GetAttributeByModifier(tokenKind: TokenKind): Option<Attribute> {
    if (tokenKind == TokenKind.PUBLIC) { return Attribute.PUBLIC }
    if (tokenKind == TokenKind.PROTECTED) { return Attribute.PROTECTED }
    if (tokenKind == TokenKind.INTERNAL) { return Attribute.INTERNAL }
    if (tokenKind == TokenKind.PRIVATE) { return Attribute.PRIVATE }
    if (tokenKind == TokenKind.STATIC) { return Attribute.STATIC }
    if (tokenKind == TokenKind.ABSTRACT) { return Attribute.ABSTRACT }
    if (tokenKind == TokenKind.OPEN) { return Attribute.OPEN }
    if (tokenKind == TokenKind.SEALED) { return Attribute.SEALED }
    if (tokenKind == TokenKind.OVERRIDE) { return Attribute.OVERRIDE }
    if (tokenKind == TokenKind.REDEF) { return Attribute.REDEF }
    if (tokenKind == TokenKind.FOREIGN) { return Attribute.FOREIGN }
    if (tokenKind == TokenKind.INOUT) { return Attribute.INOUT }
    if (tokenKind == TokenKind.MUT) { return Attribute.MUT }
    if (tokenKind == TokenKind.UNSAFE) { return Attribute.UNSAFE }
    if (tokenKind == TokenKind.OPERATOR) { return Attribute.OPERATOR }
    if (tokenKind == TokenKind.CONST) { return Attribute.CONST }
    if (tokenKind == TokenKind.COMMON) { return Attribute.COMMON }
    if (tokenKind == TokenKind.SPECIFIC) { return Attribute.SPECIFIC }
    return None
}
