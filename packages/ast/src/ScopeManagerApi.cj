package cjcj::ast

public let TOPLEVEL_SCOPE_NAME: String = "a"
public let SCOPE_SEPARATOR: String = "0"
public let SCOPE_NAME_SPLIT: String = "0"
public let CHILD_SCOPE_SEPARATOR: String = "_"

public func GetScopeNameWithoutTail(scopeName: String): String {
    let found = lastIndexOf(scopeName, CHILD_SCOPE_SEPARATOR)
    if (found >= 0) {
        return scopeName[0..found]
    }
    return scopeName
}

public func GetParentScopeName(scopeName: String): String {
    if (scopeName == "A") {
        return ""
    }
    if (scopeName == TOPLEVEL_SCOPE_NAME) {
        return "A"
    }
    let found = lastIndexOf(scopeName, SCOPE_NAME_SPLIT)
    if (found < 0) {
        return TOPLEVEL_SCOPE_NAME
    }
    return scopeName[0..found]
}

public func GetChildScopeName(scopeName: String): String {
    let found = lastIndexOf(scopeName, CHILD_SCOPE_SEPARATOR)
    if (found < 0) {
        return scopeName
    }
    let first = indexOf(scopeName, CHILD_SCOPE_SEPARATOR)
    return scopeName[0..first] + SCOPE_NAME_SPLIT + scopeName[(first + CHILD_SCOPE_SEPARATOR.size)..]
}

public func GetScopeGate(ctx: ASTContext, scopeName: String): Option<Symbol> {
    return ctx.invertedIndex.scopeGateMap.get(scopeName)
}

public func GetScopeGateName(scopeNameOrGateName: String): String {
    var currentScope = scopeNameOrGateName
    let childFound = lastIndexOf(scopeNameOrGateName, CHILD_SCOPE_SEPARATOR)
    if (childFound >= 0) {
        currentScope = scopeNameOrGateName[0..childFound]
    }
    let scopeFound = lastIndexOf(currentScope, SCOPE_NAME_SPLIT)
    if (scopeFound >= 0) {
        return currentScope[0..scopeFound] + CHILD_SCOPE_SEPARATOR +
            currentScope[(scopeFound + SCOPE_NAME_SPLIT.size)..]
    }
    return ""
}

private func lastIndexOf(value: String, needle: String): Int64 {
    if (needle.isEmpty() || value.size < needle.size) {
        return -1
    }
    var idx = value.size - needle.size
    while (idx >= 0) {
        if (value[idx..(idx + needle.size)] == needle) {
            return idx
        }
        idx--
    }
    return -1
}

private func indexOf(value: String, needle: String): Int64 {
    if (needle.isEmpty() || value.size < needle.size) {
        return -1
    }
    var idx: Int64 = 0
    while (idx <= value.size - needle.size) {
        if (value[idx..(idx + needle.size)] == needle) {
            return idx
        }
        idx++
    }
    return -1
}

public func CopyNodeScopeInfo(target: Node, source: Node): Unit {
    target.scopeName = source.scopeName
    target.scopeLevel = source.scopeLevel
    target.curFile = source.curFile
}
