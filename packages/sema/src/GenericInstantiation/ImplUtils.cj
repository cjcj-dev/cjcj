package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

public func GetDeclTy(decl: Decl): Option<Ty> {
    if (decl.astKind == ASTKind.EXTEND_DECL) {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                return extendedType.GetTy()
            }
        }
    }
    return decl.GetTy()
}

public func GetOuterStructDecl(decl: Decl): Option<Decl> {
    var outerDecl = decl.outerDecl
    while (let Some(currentDecl) <- outerDecl) {
        if (currentDecl.IsNominalDecl()) {
            return currentDecl
        }
        outerDecl = currentDecl.outerDecl
    }
    return None
}

public func IsGenericInGenericStruct(decl: Decl): Bool {
    if (let Some(outerDecl) <- GetOuterStructDecl(decl)) {
        if (let Some(_) <- outerDecl.generic) {
            if (outerDecl.IsNominalDecl()) {
                if (let Some(_) <- decl.GetGeneric()) {
                    return true
                }
            }
        }
    }
    return false
}

public func GetRealIndexingMembers(decls: ArrayList<Decl>, inGenericDecl!: Bool = true): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (member in decls) {
        if (inGenericDecl && member.astKind == ASTKind.PRIMARY_CTOR_DECL) {
            continue
        }
        if (TestManager.IsDeclGeneratedForTest(member)) {
            continue
        }
        out.add(member)
    }
    return out
}

public func WorkForMembers(decl: Decl, worker: (Decl) -> Unit): Unit {
    if (let Some(propDecl) <- (decl as PropDecl)) {
        for (getter in propDecl.getters) {
            worker(getter)
        }
        for (setter in propDecl.setters) {
            worker(setter)
        }
        return
    }
    worker(decl)
}

public func NeedSwitchContext(decl: Decl): Bool {
    if (decl.IsNominalDecl()) {
        return true
    }
    if (let Some(outerDecl) <- GetOuterStructDecl(decl)) {
        if (outerDecl.IsNominalDecl()) {
            if (let Some(_) <- decl.GetGeneric()) {
                return true
            }
            if (decl.TestAttr(Attribute.IMPORTED)) {
                return true
            }
        }
    }
    return false
}
