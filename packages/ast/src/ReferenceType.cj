package cangjie_compiler::ast

public func IsReferenceType(ty: Ty): Bool {
    var isRefOption = false
    if (ty.IsCoreOptionType()) {
        if (let Some(enumTy) <- (ty as EnumTy)) {
            if (!enumTy.typeArgs.isEmpty()) {
                let elemTy = enumTy.typeArgs[0]
                isRefOption = IsReferenceType(elemTy) && !elemTy.IsCoreOptionType()
            }
        }
    }
    return ty.IsClassLike() || ty.IsArray() || isRefOption
}

public func IsReferenceNode(node: Node): Bool {
    return node.astKind == ASTKind.REF_EXPR || node.astKind == ASTKind.MEMBER_ACCESS ||
        node.astKind == ASTKind.REF_TYPE || node.astKind == ASTKind.QUALIFIED_TYPE
}

public func GetReferenceIdentifier(node: Node): String {
    if (let Some(refExpr) <- (node as RefExpr)) {
        return refExpr.ref.identifier.GetRawText()
    }
    if (let Some(member) <- (node as MemberAccess)) {
        return member.field.GetRawText()
    }
    if (let Some(refType) <- (node as RefType)) {
        return refType.ref.identifier.GetRawText()
    }
    if (let Some(qualified) <- (node as QualifiedType)) {
        return qualified.field.GetRawText()
    }
    return ""
}
