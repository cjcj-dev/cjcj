package cangjie_compiler::ast

public func IsDeclNode(node: Node): Bool {
    return node.IsDecl()
}

public func IsExprNode(node: Node): Bool {
    return node.IsExpr()
}

public func IsTypeNode(node: Node): Bool {
    return ASTKindIndex(node.astKind) >= ASTKindIndex(ASTKind.TYPE) &&
        ASTKindIndex(node.astKind) <= ASTKindIndex(ASTKind.INVALID_TYPE)
}

public func IsPatternNode(node: Node): Bool {
    return ASTKindIndex(node.astKind) >= ASTKindIndex(ASTKind.PATTERN) &&
        ASTKindIndex(node.astKind) <= ASTKindIndex(ASTKind.INVALID_PATTERN)
}

public func IsClassLikeTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_CLASS || ty.kind == TypeKind.TYPE_INTERFACE
}

public func IsPrimitiveTy(ty: Ty): Bool {
    return ty.IsPrimitive()
}

public func IsClassThisTy(ty: Ty): Bool {
    if (ty.kind != TypeKind.TYPE_CLASS) {
        return false
    }
    if (let Some(_) <- (ty as ClassThisTy)) {
        return true
    }
    return false
}

public func IsRefEnumTy(ty: Ty): Bool {
    if (ty.kind != TypeKind.TYPE_ENUM) {
        return false
    }
    if (let Some(_) <- (ty as RefEnumTy)) {
        return true
    }
    return false
}
