package cangjie_compiler::ast

public let TOPLEVEL_SCOPE_NAME: String = "_toplevel"
public let SCOPE_SEPARATOR: String = "::"

public func JoinScopeName(parent: String, child: String): String {
    if (parent.isEmpty() || parent == TOPLEVEL_SCOPE_NAME) {
        return child
    }
    if (child.isEmpty()) {
        return parent
    }
    return parent + SCOPE_SEPARATOR + child
}

public func MakeDeclScopeName(decl: Decl): String {
    let name = decl.identifier.GetRawText()
    if (name.isEmpty()) {
        return decl.scopeName
    }
    return JoinScopeName(decl.scopeName, name)
}

public func CopyNodeScopeInfo(target: Node, source: Node): Unit {
    target.scopeName = source.scopeName
    target.exportId = source.exportId
    target.scopeLevel = source.scopeLevel
    target.curFile = source.curFile
}
