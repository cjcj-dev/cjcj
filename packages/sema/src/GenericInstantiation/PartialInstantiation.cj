package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions

private class InstantiationPair {
    public var genericDecl: Decl
    public var instantiatedDecl: Decl

    public init(genericDecl: Decl, instantiatedDecl: Decl) {
        this.genericDecl = genericDecl
        this.instantiatedDecl = instantiatedDecl
    }
}

private let ins2generic: ArrayList<InstantiationPair> = ArrayList<InstantiationPair>()
private let generic2ins: ArrayList<InstantiationPair> = ArrayList<InstantiationPair>()

private func findGeneralDecl(instantiatedDecl: Decl): Option<Decl> {
    if (let Some(genericDecl) <- instantiatedDecl.genericDecl) {
        return genericDecl
    }
    for (entry in ins2generic) {
        if (SameDecl(entry.instantiatedDecl, instantiatedDecl)) {
            return entry.genericDecl
        }
    }
    return None
}

private func hasInstantiation(genericDecl: Decl, instantiatedDecl: Decl): Bool {
    for (entry in generic2ins) {
        if (SameDecl(entry.genericDecl, genericDecl) && SameDecl(entry.instantiatedDecl, instantiatedDecl)) {
            return true
        }
    }
    return false
}

private func registerInstantiation(genericDecl: Decl, instantiatedDecl: Decl): Unit {
    if (hasInstantiation(genericDecl, instantiatedDecl)) {
        return
    }
    generic2ins.add(InstantiationPair(genericDecl, instantiatedDecl))
    ins2generic.add(InstantiationPair(genericDecl, instantiatedDecl))
    instantiatedDecl.genericDecl = genericDecl
}

public func SetOptLevel(opts: OptionGlobalOptions): Unit {
    let _ = opts
}

public func RequireInstantiation(decl: Decl): Bool {
    var current: Option<Decl> = Some(decl)
    while (let Some(curDecl) <- current) {
        if (curDecl.astKind == ASTKind.INTERFACE_DECL) {
            return true
        }
        if (curDecl.astKind == ASTKind.CLASS_DECL && curDecl.IsOpen()) {
            return true
        }
        current = curDecl.outerDecl
    }
    return false
}

public func DefaultVisitFunc(source: Node, target: Node): Unit {
    let _ = source
    let _ = target
}

public func InstantiateMacroInvocation(invocation: MacroInvocation): MacroInvocation {
    return CloneMacroInvocation(invocation)
}

public func InstantiateGeneric(generic: Generic, visitor: (Node, Node) -> Unit): Generic {
    if (let Some(cloned) <- (ASTCloner.Clone(generic) as Generic)) {
        visitor(generic, cloned)
        return cloned
    }
    return Generic()
}

public class PartialInstantiation {
    public init() {}

    public static func Instantiate(node: Node): Node {
        return Instantiate(node, DefaultVisitFunc)
    }

    public static func Instantiate(node: Node, visitFunc: (Node, Node) -> Unit): Node {
        let cloned = ASTCloner.Clone(node)
        visitFunc(node, cloned)
        if (let Some(srcDecl) <- (node as Decl)) {
            if (let Some(clonedDecl) <- (cloned as Decl)) {
                registerInstantiation(srcDecl, clonedDecl)
            }
        }
        return cloned
    }

    public static func GetGeneralDecl(clonedDecl: Decl): Decl {
        if (let Some(generalDecl) <- findGeneralDecl(clonedDecl)) {
            return generalDecl
        }
        return clonedDecl
    }

    public static func GetInstantiatedDecl(genericDecl: Decl): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        for (entry in generic2ins) {
            if (SameDecl(entry.genericDecl, genericDecl)) {
                out.add(entry.instantiatedDecl)
            }
        }
        return out
    }

    public static func RegisterInstantiation(genericDecl: Decl, instantiatedDecl: Decl): Unit {
        registerInstantiation(genericDecl, instantiatedDecl)
    }

    public static func ResetGlobalMap(): Unit {
        generic2ins.clear()
        ins2generic.clear()
    }
}
