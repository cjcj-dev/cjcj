package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::ast.AnnotationKind as AstAnnotationKind
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::option.OptimizationLevel
import cangjie_compiler::option.OutputMode
import cangjie_compiler::option.enumIndex

private var currentOptLevel: OptimizationLevel = OptimizationLevel.O0
private var currentOutputMode: OutputMode = OutputMode.EXECUTABLE

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
    currentOptLevel = opts.optimizationLevel
    currentOutputMode = opts.outputMode
}

private func IsCPointerFrozenMember(decl: Decl): Bool {
    if (decl.astKind != ASTKind.FUNC_DECL || !decl.HasAnno(AstAnnotationKind.FROZEN)) {
        return false
    }
    if (let Some(outer) <- decl.outerDecl) {
        if (let Some(extendDecl) <- (outer as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (let Some(extendedTy) <- extendedType.GetTy()) {
                    return extendedTy.IsPointer()
                }
            }
        }
    }
    return false
}

public func RequireInstantiation(decl: Decl): Bool {
    if (currentOutputMode == OutputMode.CHIR || decl.IsCommonMatchedWithSpecific()) {
        return false
    }
    if (IsCPointerFrozenMember(decl)) {
        return true
    }
    if (decl.astKind == ASTKind.INTERFACE_DECL) {
        return false
    }
    if (decl.IsNominalDecl()) {
        if (enumIndex(currentOptLevel) >= enumIndex(OptimizationLevel.O2) && !decl.TestAttr(Attribute.IMPORTED)) {
            return true
        }
        if (decl.TestAttr(Attribute.GENERIC)) {
            for (member in decl.GetMemberDecls()) {
                if (RequireInstantiation(member)) {
                    return true
                }
            }
        }
        return false
    }
    if (IsVirtualMember(decl)) {
        return false
    }
    if (decl.IsConst()) {
        return true
    }
    if (decl.TestAttr(Attribute.CONTAINS_MOCK_CREATION_CALL) && decl.HasAnno(AstAnnotationKind.FROZEN)) {
        return true
    }
    if (enumIndex(currentOptLevel) < enumIndex(OptimizationLevel.O2)) {
        return false
    }
    if (!IsInDeclWithAttribute(decl, Attribute.IMPORTED)) {
        return true
    }
    return decl.HasAnno(AstAnnotationKind.FROZEN)
}

private func collectDeclPair(source: Node, target: Node, pairs: ArrayList<InstantiationPair>): Unit {
    if (let Some(sourceDecl) <- (source as Decl)) {
        if (let Some(targetDecl) <- (target as Decl)) {
            targetDecl.genericDecl = sourceDecl
            pairs.add(InstantiationPair(sourceDecl, targetDecl))
        }
    }
}

private func InstantiationVisitFunc(source: Node, target: Node, visitor: (Node, Node) -> Unit,
    pairs: ArrayList<InstantiationPair>): Unit {
    collectDeclPair(source, target, pairs)
    visitor(source, target)
}

private func enableCompilerAddOnDecls(root: Node): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(decl) <- (node as Decl)) {
            decl.EnableAttr(Attribute.COMPILER_ADD)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func resetOuterDeclForClonedMembers(root: Node): Unit {
    if (let Some(rootDecl) <- (root as Decl)) {
        for (member in rootDecl.GetMemberDecls()) {
            member.outerDecl = rootDecl
        }
        return
    }
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(decl) <- (node as Decl)) {
            for (member in decl.GetMemberDecls()) {
                member.outerDecl = decl
            }
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func pruneClassBody(body: ClassBody): Unit {
    var idx: Int64 = 0
    while (idx < body.decls.size) {
        let decl = body.decls[idx]
        if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL ||
            (decl.astKind != ASTKind.VAR_DECL && !RequireInstantiation(decl)) || IsStaticVar(decl) ||
            IsStaticInitializer(decl)) {
            body.decls.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func pruneStructBody(body: StructBody): Unit {
    var idx: Int64 = 0
    while (idx < body.decls.size) {
        let decl = body.decls[idx]
        if (decl.astKind == ASTKind.PRIMARY_CTOR_DECL ||
            (decl.astKind != ASTKind.VAR_DECL && !RequireInstantiation(decl)) || IsStaticVar(decl) ||
            IsStaticInitializer(decl)) {
            body.decls.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func pruneInterfaceBody(body: InterfaceBody): Unit {
    var idx: Int64 = 0
    while (idx < body.decls.size) {
        let decl = body.decls[idx]
        if (decl.astKind == ASTKind.PROP_DECL || (decl.astKind == ASTKind.FUNC_DECL && !RequireInstantiation(decl))) {
            body.decls.remove(at: idx)
        } else {
            idx++
        }
    }
}

private func PruneNonInstantiatedMembers(root: Node): Unit {
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(body) <- (node as ClassBody)) {
            pruneClassBody(body)
        } else if (let Some(body) <- (node as StructBody)) {
            pruneStructBody(body)
        } else if (let Some(body) <- (node as InterfaceBody)) {
            pruneInterfaceBody(body)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

private func FinalizeInstantiatedTree(root: Node): Unit {
    enableCompilerAddOnDecls(root)
    resetOuterDeclForClonedMembers(root)
    PruneNonInstantiatedMembers(root)
}

private func collectReachableDecls(root: Node): ArrayList<Decl> {
    let decls = ArrayList<Decl>()
    let walker = Walker(root, visitPre: { node: Node =>
        if (let Some(decl) <- (node as Decl)) {
            decls.add(decl)
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return decls
}

private func isReachableDecl(decls: ArrayList<Decl>, decl: Decl): Bool {
    for (candidate in decls) {
        if (SameDecl(candidate, decl)) {
            return true
        }
    }
    return false
}

private func RegisterReachableDeclPairs(root: Node, pairs: ArrayList<InstantiationPair>): Unit {
    let reachableDecls = collectReachableDecls(root)
    for (pair in pairs) {
        if (isReachableDecl(reachableDecls, pair.instantiatedDecl)) {
            registerInstantiation(pair.genericDecl, pair.instantiatedDecl)
        }
    }
}

private func clonedGenericDecl(generic: Generic, visitor: (Node, Node) -> Unit): Generic {
    let pairs = ArrayList<InstantiationPair>()
    if (let Some(cloned) <- (ASTCloner.Clone(generic, { source: Node, target: Node =>
        InstantiationVisitFunc(source, target, visitor, pairs)
    }) as Generic)) {
        FinalizeInstantiatedTree(cloned)
        RegisterReachableDeclPairs(cloned, pairs)
        return cloned
    }
    return Generic()
}

private func clonedNode(node: Node, visitor: (Node, Node) -> Unit): Node {
    let pairs = ArrayList<InstantiationPair>()
    let cloned = ASTCloner.Clone(node, { source: Node, target: Node =>
        InstantiationVisitFunc(source, target, visitor, pairs)
    })
    FinalizeInstantiatedTree(cloned)
    RegisterReachableDeclPairs(cloned, pairs)
    return cloned
}

public func GetOptLevel(): OptimizationLevel {
    return currentOptLevel
}

public func IsOpenDecl(decl: Decl): Bool {
    if (!decl.IsClassLikeDecl()) {
        return false
    }
    if (decl.TestAttr(Attribute.OPEN_TO_MOCK)) {
        return false
    }
    if (decl.TestAnyAttr(Attribute.ABSTRACT, Attribute.OPEN)) {
        return true
    }
    return decl.astKind == ASTKind.INTERFACE_DECL
}

public func DefaultVisitFunc(source: Node, target: Node): Unit {
    let _ = source
    let _ = target
}

public func InstantiateMacroInvocation(invocation: MacroInvocation): MacroInvocation {
    return CloneMacroInvocation(invocation)
}

public func InstantiateGeneric(generic: Generic, visitor: (Node, Node) -> Unit): Generic {
    return clonedGenericDecl(generic, visitor)
}

public class PartialInstantiation {
    public init() {}

    public static func Instantiate(node: Node): Node {
        return Instantiate(node, DefaultVisitFunc)
    }

    public static func Instantiate(node: Node, visitFunc: (Node, Node) -> Unit): Node {
        return clonedNode(node, visitFunc)
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
