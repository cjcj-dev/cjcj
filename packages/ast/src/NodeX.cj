package cangjie_compiler::ast

public func GetNodeDisplayName(node: Node): String {
    let text = node.ToString()
    if (!text.isEmpty()) {
        return text
    }
    if (let Some(decl) <- (node as Decl)) {
        return decl.identifier.GetRawText()
    }
    return ASTKindName(node.astKind)
}

public func IsNodeBroken(node: Node): Bool {
    return node.TestAnyAttr(Attribute.IS_BROKEN, Attribute.HAS_BROKEN)
}

public func MarkNodeBroken(node: Node): Unit {
    node.EnableAttr(Attribute.IS_BROKEN)
}
