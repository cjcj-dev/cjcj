package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.{DiagnosticEngine as BasicDiagnosticEngine, DiagArgument as BasicDiagArgument,
    DiagKind as BasicDiagKind, DiagKindRefactor as BasicDiagKindRefactor, MakeRange, Range as BasicRange,
    SubDiagnostic as BasicSubDiagnostic}

private func InterfaceConformanceDeclRange(decl: Decl): BasicRange {
    return MakeRange(decl.begin, decl.end)
}

private func InterfaceConformanceIdentifierRange(decl: Decl): BasicRange {
    if (!decl.identifier.Empty() && !decl.identifier.ZeroPos()) {
        return MakeRange(decl.identifier.Begin(), decl.identifier.End())
    }
    return InterfaceConformanceDeclRange(decl)
}

private func InterfaceConformanceVisibilityToString(decl: Decl): String {
    if (decl.TestAttr(Attribute.PUBLIC)) {
        return "public"
    }
    if (decl.TestAttr(Attribute.PROTECTED)) {
        return "protected"
    }
    if (decl.TestAttr(Attribute.PRIVATE)) {
        return "private"
    }
    return "internal"
}

private func InterfaceConformanceDeclKindText(decl: Decl): String {
    if (decl.astKind == ASTKind.PROP_DECL) {
        return "property"
    }
    if (decl.IsFunc()) {
        return "function"
    }
    return DeclKindToString(decl)
}

private func InterfaceConformanceFuncTy(ty: Option<Ty>): Option<FuncTy> {
    if (let Some(value) <- ty) {
        return value as FuncTy
    }
    return None
}

private func InterfaceConformanceSameSignature(typeManager: TypeManager, interfaceMember: Decl, implMember: Decl): Bool {
    if (interfaceMember.astKind != implMember.astKind) {
        return false
    }
    if (interfaceMember.astKind == ASTKind.PROP_DECL) {
        return SameTy(interfaceMember.GetTy(), implMember.GetTy())
    }
    if (!interfaceMember.IsFunc() || !implMember.IsFunc()) {
        return false
    }
    if (let Some(interfaceFuncTy) <- InterfaceConformanceFuncTy(interfaceMember.GetTy())) {
        if (let Some(implFuncTy) <- InterfaceConformanceFuncTy(implMember.GetTy())) {
            return typeManager.IsFuncParameterTypesIdentical(interfaceFuncTy, implFuncTy) &&
                typeManager.IsSubtype(implFuncTy.retTy, interfaceFuncTy.retTy, implicitBoxed: false)
        }
    }
    return false
}

private func InterfaceConformanceWeakVisibility(parent: Decl, child: Decl): Bool {
    return (parent.TestAttr(Attribute.PUBLIC) && !child.TestAttr(Attribute.PUBLIC)) ||
        (parent.TestAttr(Attribute.PROTECTED) && !child.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED)) ||
        (!parent.TestAnyAttr(Attribute.PUBLIC, Attribute.PROTECTED, Attribute.PRIVATE) && child.TestAttr(Attribute.PRIVATE))
}

private func InterfaceConformanceDiagnoseWeakVisibility(
    diag: BasicDiagnosticEngine,
    parent: Decl,
    child: Decl,
    diagNode: Decl
): Unit {
    let range = InterfaceConformanceIdentifierRange(diagNode)
    let childHint = "the visibility of the deriving '" + child.identifier.Val() + "' is '" +
        InterfaceConformanceVisibilityToString(child) + "'"
    let builder = diag.DiagnoseRefactor(BasicDiagKindRefactor.sema_weak_visibility, range)
    if (SameDecl(child, diagNode)) {
        builder.AddMainHintArguments([childHint])
    } else {
        builder.AddMainHintArguments(["'" + child.identifier.Val() + "' is inherited"])
        let childRange = InterfaceConformanceIdentifierRange(child)
        let childNote = BasicSubDiagnostic(childRange, "the deriving '" + child.identifier.Val() + "' is defined here")
        childNote.AddMainHint(childRange, childHint)
        builder.AddNote(childNote)
    }
    let parentRange = InterfaceConformanceIdentifierRange(parent)
    let parentNote = BasicSubDiagnostic(parentRange,
        "the visibility of the base '" + parent.identifier.Val() + "' is '" +
            InterfaceConformanceVisibilityToString(parent) + "'")
    if (let Some(parentOuter) <- parent.outerDecl) {
        if (parentOuter.astKind == ASTKind.INTERFACE_DECL) {
            parentNote.AddMainHint(parentRange, "the base '" + parent.identifier.Val() + "' is in 'interface'")
        }
    }
    builder.AddNote(parentNote)
    builder.Emit()
}

private func InterfaceConformanceSetImplAttr(member: Decl): Unit {
    member.EnableAttr(Attribute.INTERFACE_IMPL)
    if (let Some(propDecl) <- (member as PropDecl)) {
        for (getter in propDecl.getters) {
            getter.EnableAttr(Attribute.INTERFACE_IMPL)
        }
        for (setter in propDecl.setters) {
            setter.EnableAttr(Attribute.INTERFACE_IMPL)
        }
    }
}

private func InterfaceConformanceCollectInterfaceMembers(interfaceDecl: InterfaceDecl, out: ArrayList<Decl>): Unit {
    for (inheritedType in interfaceDecl.inheritedTypes) {
        if (let Some(inheritedDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
            if (let Some(superInterface) <- (inheritedDecl as InterfaceDecl)) {
                InterfaceConformanceCollectInterfaceMembers(superInterface, out)
            }
        }
    }
    for (member in interfaceDecl.GetMemberDecls()) {
        if (member.astKind == ASTKind.PROP_DECL || member.IsFunc()) {
            out.add(member)
        }
    }
}

private func InterfaceConformanceCollectInterfaces(decl: InheritableDecl, out: ArrayList<InterfaceDecl>): Unit {
    for (inheritedType in decl.inheritedTypes) {
        if (let Some(inheritedDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
            if (let Some(interfaceDecl) <- (inheritedDecl as InterfaceDecl)) {
                var exists = false
                for (value in out) {
                    if (SameDecl(value, interfaceDecl)) {
                        exists = true
                        break
                    }
                }
                if (!exists) {
                    out.add(interfaceDecl)
                }
                InterfaceConformanceCollectInterfaces(interfaceDecl, out)
            }
        }
    }
}

private func InterfaceConformanceFindMemberInDecl(
    typeManager: TypeManager,
    decl: InheritableDecl,
    interfaceMember: Decl
): Option<Decl> {
    for (member in decl.GetMemberDecls()) {
        if (member.identifier.Val() != interfaceMember.identifier.Val()) {
            continue
        }
        if (InterfaceConformanceSameSignature(typeManager, interfaceMember, member)) {
            return Some(member)
        }
    }
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        if (let Some(superClassDecl) <- classDecl.GetSuperClassDecl()) {
            return InterfaceConformanceFindMemberInDecl(typeManager, superClassDecl, interfaceMember)
        }
    }
    return None
}

private func InterfaceConformanceDiagnoseMissing(
    diag: BasicDiagnosticEngine,
    decl: InheritableDecl,
    interfaceMember: Decl
): Unit {
    if (decl.TestAttr(Attribute.ABSTRACT) || decl.astKind == ASTKind.INTERFACE_DECL) {
        return
    }
    if (!interfaceMember.TestAttr(Attribute.ABSTRACT) && !interfaceMember.TestAttr(Attribute.DEFAULT)) {
        return
    }
    if (interfaceMember.TestAttr(Attribute.DEFAULT)) {
        return
    }
    let builder = diag.Diagnose(
        decl.begin,
        decl.end,
        BasicDiagKind.sema_interface_member_must_be_implemented,
        args: [
            BasicDiagArgument(InterfaceConformanceDeclKindText(interfaceMember)),
            BasicDiagArgument(interfaceMember.identifier.Val()),
            BasicDiagArgument(decl.identifier.Val())
        ]
    )
    builder.Emit()
}

private func InterfaceConformanceCheckDecl(
    diag: BasicDiagnosticEngine,
    typeManager: TypeManager,
    decl: InheritableDecl
): Unit {
    if (decl.astKind == ASTKind.INTERFACE_DECL || decl.TestAnyAttr(Attribute.IMPORTED, Attribute.TOOL_ADD,
        Attribute.IS_BROKEN) || decl.TestAttr(Attribute.HAS_BROKEN)) {
        return
    }
    if (!Ty.IsTyCorrect(decl.GetTy())) {
        return
    }
    let interfaces = ArrayList<InterfaceDecl>()
    InterfaceConformanceCollectInterfaces(decl, interfaces)
    for (interfaceDecl in interfaces) {
        let members = ArrayList<Decl>()
        InterfaceConformanceCollectInterfaceMembers(interfaceDecl, members)
        for (interfaceMember in members) {
            if (!Ty.IsTyCorrect(interfaceMember.GetTy())) {
                continue
            }
            if (let Some(implMember) <- InterfaceConformanceFindMemberInDecl(typeManager, decl, interfaceMember)) {
                InterfaceConformanceSetImplAttr(implMember)
                if (InterfaceConformanceWeakVisibility(interfaceMember, implMember)) {
                    InterfaceConformanceDiagnoseWeakVisibility(diag, interfaceMember, implMember, implMember)
                }
            } else {
                InterfaceConformanceDiagnoseMissing(diag, decl, interfaceMember)
            }
        }
    }
}

public func CheckInterfaceConformanceForPackage(
    diag: BasicDiagnosticEngine,
    typeManager: TypeManager,
    pkg: Package
): Unit {
    if (pkg.TestAnyAttr(Attribute.IMPORTED, Attribute.TOOL_ADD)) {
        return
    }
    let walker = Walker(pkg, visitPre: { node: Node =>
        if (let Some(inheritable) <- (node as InheritableDecl)) {
            InterfaceConformanceCheckDecl(diag, typeManager, inheritable)
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
}

public func SelfhostPortStatus_InterfaceConformanceChecker(): Bool {
    return true
}
