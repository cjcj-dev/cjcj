package cangjie_compiler::ast

public func CreateRefType(name: String): RefType {
    let refType = RefType()
    refType.ref.identifier = SrcIdentifier(name)
    return refType
}

public func CreateRefExpr(name: String): RefExpr {
    let refExpr = RefExpr()
    refExpr.ref.identifier = SrcIdentifier(name)
    return refExpr
}

public func CreateLitConstExpr(kind: LitConstKind, value: String): LitConstExpr {
    return LitConstExpr(kind, value)
}

public func CreatePackage(name: String): Package {
    return Package(name)
}

public func CreateFile(path: String): File {
    let file = File()
    file.filePath = path
    file.fileName = path
    return file
}
