package cangjie_compiler::ast

public func IsDeclKind(kind: ASTKind): Bool {
    return ASTKindIndex(kind) >= ASTKindIndex(ASTKind.DECL) &&
        ASTKindIndex(kind) <= ASTKindIndex(ASTKind.INVALID_DECL)
}

public func IsExprKind(kind: ASTKind): Bool {
    return ASTKindIndex(kind) >= ASTKindIndex(ASTKind.EXPR) &&
        ASTKindIndex(kind) <= ASTKindIndex(ASTKind.INVALID_EXPR)
}

public func IsTypeKind(kind: ASTKind): Bool {
    return ASTKindIndex(kind) >= ASTKindIndex(ASTKind.TYPE) &&
        ASTKindIndex(kind) <= ASTKindIndex(ASTKind.INVALID_TYPE)
}

public func IsPatternKind(kind: ASTKind): Bool {
    return ASTKindIndex(kind) >= ASTKindIndex(ASTKind.PATTERN) &&
        ASTKindIndex(kind) <= ASTKindIndex(ASTKind.INVALID_PATTERN)
}

public func IsNodeKind(node: Node, kind: ASTKind): Bool {
    return node.astKind == kind
}
