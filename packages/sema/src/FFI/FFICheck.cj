package cangjie_compiler::sema.FFI

import cangjie_compiler::ast.*

public func GetDefaultABI(): Attribute {
    return Attribute.C
}

public func HasAnnotationNamed(decl: Decl, name: String): Bool {
    for (anno in decl.annotations) {
        if (anno.identifier.Val() == name) {
            return true
        }
    }
    return false
}

public func SetForeignABIAttr(decl: Decl): Unit {
    if (!decl.TestAttr(Attribute.FOREIGN)) {
        return
    }
    var defaultABI = GetDefaultABI()
    if (HasAnnotationNamed(decl, "C")) {
        defaultABI = Attribute.C
    }
    decl.EnableAttr(defaultABI)
}

public func PreCheckAnnoForCFFI(decl: Decl): Unit {
    if (HasAnnotationNamed(decl, "C") || HasAnnotationNamed(decl, "CallingConv")) {
        decl.EnableAttr(Attribute.C)
    }
}

public func PreCheckAnnoForFFI(root: Node): Unit {
    if (root.TestAttr(Attribute.IMPORTED)) {
        return
    }
    let walker = Walker(root, visitPre: { curNode: Node =>
        if (curNode.IsDecl()) {
            if (let Some(decl) <- (curNode as Decl)) {
                SetForeignABIAttr(decl)
                PreCheckAnnoForCFFI(decl)
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public func IsNonStaticMemberReference(target: Decl): Bool {
    return !target.TestAttr(Attribute.STATIC) &&
        (target.TestAnyAttr(Attribute.IN_CLASSLIKE, Attribute.IN_STRUCT, Attribute.IN_ENUM) ||
        target.TestAttr(Attribute.IN_EXTEND))
}

public func IsInvalidRefTargetInCFunc(target: Decl): Bool {
    if (target.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.ENUM_CONSTRUCTOR)) {
        return false
    }
    return IsNonStaticMemberReference(target)
}
