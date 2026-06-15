package cangjie_compiler::ast

public func IsDeclNode(node: Node): Bool {
    return node.IsDecl()
}

public func IsInheritableDeclNode(node: Node): Bool {
    return ASTKindIndex(node.astKind) >= ASTKindIndex(ASTKind.CLASS_LIKE_DECL) &&
        ASTKindIndex(node.astKind) <= ASTKindIndex(ASTKind.STRUCT_DECL)
}

public func IsVarDeclNode(node: Node): Bool {
    return ASTKindIndex(node.astKind) >= ASTKindIndex(ASTKind.VAR_DECL) &&
        ASTKindIndex(node.astKind) <= ASTKindIndex(ASTKind.FUNC_PARAM)
}

public func IsFuncParamNode(node: Node): Bool {
    return node.astKind == ASTKind.FUNC_PARAM || node.astKind == ASTKind.MACRO_EXPAND_PARAM
}

public func IsVarDeclAbstractNode(node: Node): Bool {
    return IsVarDeclNode(node) || node.astKind == ASTKind.VAR_WITH_PATTERN_DECL
}

public func IsClassLikeDeclNode(node: Node): Bool {
    return ASTKindIndex(node.astKind) >= ASTKindIndex(ASTKind.CLASS_LIKE_DECL) &&
        ASTKindIndex(node.astKind) <= ASTKindIndex(ASTKind.INTERFACE_DECL)
}

public func IsExprNode(node: Node): Bool {
    return node.IsExpr()
}

public func IsOverloadableExprNode(node: Node): Bool {
    return ASTKindIndex(node.astKind) >= ASTKindIndex(ASTKind.ASSIGN_EXPR) &&
        ASTKindIndex(node.astKind) <= ASTKindIndex(ASTKind.SUBSCRIPT_EXPR)
}

public func IsNameReferenceExprNode(node: Node): Bool {
    return node.astKind == ASTKind.MEMBER_ACCESS || node.astKind == ASTKind.REF_EXPR
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

public func IsArrayTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_ARRAY
}

public func IsVArrayTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_VARRAY
}

public func IsPointerTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_POINTER
}

public func IsCStringTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_CSTRING
}

public func IsTupleTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_TUPLE
}

public func IsFuncTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_FUNC
}

public func IsUnionTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_UNION
}

public func IsIntersectionTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_INTERSECTION
}

public func IsInterfaceTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_INTERFACE
}

public func IsClassTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_CLASS
}

public func IsEnumTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_ENUM
}

public func IsStructTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_STRUCT
}

public func IsTypeAliasTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE
}

public func IsGenericsTy(ty: Ty): Bool {
    return ty.kind == TypeKind.TYPE_GENERICS
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
