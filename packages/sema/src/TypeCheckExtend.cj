package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagKindRefactor as BasicDiagKindRefactor
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::basic.Range as BasicRange

private func TypeCheckExtendRange(node: Node): BasicRange {
    var rangeEnd = node.end
    if (node.begin.fileID != node.end.fileID) {
        rangeEnd = node.begin + 1
    }
    return MakeRange(node.begin, rangeEnd)
}

private func TypeCheckExtendAccessRank(level: AccessLevel): Int64 {
    return match (level) {
        case AccessLevel.PRIVATE => 0
        case AccessLevel.INTERNAL => 1
        case AccessLevel.PROTECTED => 2
        case AccessLevel.PUBLIC => 3
    }
}

private func TypeCheckExtendMinAccess(left: AccessLevel, right: AccessLevel): AccessLevel {
    if (TypeCheckExtendAccessRank(left) < TypeCheckExtendAccessRank(right)) {
        return left
    }
    return right
}

private func TypeCheckExtendMaxAccess(left: AccessLevel, right: AccessLevel): AccessLevel {
    if (TypeCheckExtendAccessRank(left) > TypeCheckExtendAccessRank(right)) {
        return left
    }
    return right
}

private func TypeCheckExtendHasSameTy(values: ArrayList<Ty>, candidate: Ty): Bool {
    for (value in values) {
        if (SameTy(value, candidate)) {
            return true
        }
    }
    return false
}

private func TypeCheckExtendAddUniqueTy(values: ArrayList<Ty>, candidate: Ty): Unit {
    if (!TypeCheckExtendHasSameTy(values, candidate)) {
        values.add(candidate)
    }
}

private func TypeCheckExtendAddUniqueDecl(values: ArrayList<Decl>, candidate: Decl): Unit {
    for (value in values) {
        if (SameDecl(value, candidate)) {
            return
        }
    }
    values.add(candidate)
}

private func TypeCheckExtendFindBuiltinEntry(tm: TypeManager, ty: Ty): Option<TyExtendsEntry> {
    for (entry in tm.builtinTyToExtendMap) {
        if (SameTy(entry.ty, ty)) {
            return Some(entry)
        }
    }
    return None
}

private func TypeCheckExtendFindDeclEntry(tm: TypeManager, decl: InheritableDecl): Option<DeclExtendsEntry> {
    for (entry in tm.declToExtendMap) {
        if (SameDecl(entry.decl, decl)) {
            return Some(entry)
        }
    }
    return None
}

private func TypeCheckExtendIsExtendedASTKind(typeNode: Type): Bool {
    return typeNode.astKind == ASTKind.REF_TYPE || typeNode.astKind == ASTKind.QUALIFIED_TYPE ||
        typeNode.astKind == ASTKind.PRIMITIVE_TYPE || typeNode.astKind == ASTKind.OPTION_TYPE
}

public func TypeCheckExtendCheckExtendGenerics(
    diag: BasicDiagnosticEngine,
    extendDecl: ExtendDecl
): Bool {
    if (let None <- extendDecl.generic) {
        return true
    }
    if (let None <- extendDecl.extendedType) {
        return true
    }
    let extendedType = extendDecl.extendedType.getOrThrow()
    if (!Ty.IsTyCorrect(extendedType.GetTy()) || !extendedType.GetTy().getOrThrow().IsExtendable()) {
        return true
    }
    let isMovedCommon = !extendDecl.TestAttr(Attribute.IMPORTED) && extendDecl.TestAttr(Attribute.FROM_COMMON_PART) &&
        extendDecl.TestAttr(Attribute.COMMON)
    if (isMovedCommon) {
        return true
    }
    let used = extendedType.GetTy().getOrThrow().GetGenericTyArgs()
    let unused = ArrayList<String>()
    for (param in extendDecl.generic.getOrThrow().typeParameters) {
        if (let Some(paramTy) <- param.GetTy()) {
            var found = false
            for (usedTy in used) {
                if (SameTy(usedTy, paramTy)) {
                    found = true
                    break
                }
            }
            if (!found) {
                unused.add(param.identifier.Val())
            }
        }
    }
    if (unused.isEmpty()) {
        return true
    }
    var typeStr = " '" + JoinStrings(unused, "', '") + "'"
    if (unused.size > 1) {
        typeStr = "s" + typeStr
    }
    let builder = diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_extend_generic_must_be_used,
        TypeCheckExtendRange(extendedType),
        arguments: [typeStr])
    builder.Emit()
    return false
}

public func TypeCheckExtendCheckExtendedTypeValidity(
    diag: BasicDiagnosticEngine,
    extendedType: Type
): Bool {
    if (!Ty.IsTyCorrect(extendedType.GetTy())) {
        return true
    }
    let ty = extendedType.GetTy().getOrThrow()
    if (ty.IsExtendable()) {
        return true
    }
    let builder = diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_illegal_extended_type,
        TypeCheckExtendRange(extendedType),
        arguments: [ty.String()])
    builder.Emit()
    return false
}

public func TypeCheckExtendPreCheckExtend(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    extendDecl: ExtendDecl
): Bool {
    var valid = true
    if (let Some(extendedType) <- extendDecl.extendedType) {
        if (let Some(extendedTy) <- extendedType.GetTy()) {
            if (let Some(decl) <- Ty.GetDeclOfTy(Some(extendedTy))) {
                if (decl.TestAttr(Attribute.C)) {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_c_type_cannot_extend_interface,
                        TypeCheckExtendRange(extendedType),
                        arguments: [decl.identifier.Val()])
                    builder.Emit()
                    valid = false
                }
            }
            extendDecl.SetTy(extendedTy)
        }
        if (!TypeCheckExtendCheckExtendedTypeValidity(diag, extendedType)) {
            valid = false
        }
    }
    var idx: Int64 = 0
    while (idx < extendDecl.inheritedTypes.size) {
        let inheritedType = extendDecl.inheritedTypes[idx]
        if (!Ty.IsTyCorrect(inheritedType.GetTy()) || inheritedType.TyKind() != TypeKind.TYPE_INTERFACE) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_extend_not_interface,
                TypeCheckExtendRange(inheritedType))
            builder.Emit()
            ctx.DeleteInvertedIndexes(inheritedType)
            extendDecl.inheritedTypes.remove(at: idx)
            valid = false
        } else {
            idx++
        }
    }
    TypeCheckExtendSetExternalAttr(ctx, extendDecl)
    if (!TypeCheckExtendCheckExtendGenerics(diag, extendDecl)) {
        valid = false
    }
    let _ = tm
    return valid
}

public func TypeCheckExtendUpdateExtendMap(tm: TypeManager, extends: ArrayList<ExtendDecl>): Unit {
    for (extendDecl in extends) {
        var hasExtendedType = false
        if (let Some(_) <- extendDecl.extendedType) {
            hasExtendedType = true
        }
        var hasSpecificImplementation = false
        if (let Some(_) <- extendDecl.specificImplementation) {
            hasSpecificImplementation = true
        }
        if (extendDecl.isInMacroCall || !hasExtendedType || hasSpecificImplementation) {
            continue
        }
        let extendedType = extendDecl.extendedType.getOrThrow()
        if (!Ty.IsTyCorrect(extendedType.GetTy())) {
            continue
        }
        var extendTy = extendedType.GetTy().getOrThrow()
        if (!extendTy.IsExtendable() || !TypeCheckExtendIsExtendedASTKind(extendedType)) {
            continue
        }
        for (interfaceType in extendDecl.inheritedTypes) {
            if (Ty.IsTyCorrect(interfaceType.GetTy()) && interfaceType.GetTy().getOrThrow().IsClassLike()) {
                if (let Some(classLikeTy) <- (interfaceType.GetTy().getOrThrow() as ClassLikeTy)) {
                    TypeCheckExtendAddUniqueTy(classLikeTy.directSubtypes, extendTy)
                }
            }
        }
        if (extendTy.IsBuiltin()) {
            extendTy = tm.GetTyForExtendMap(extendTy)
            if (let Some(entry) <- TypeCheckExtendFindBuiltinEntry(tm, extendTy)) {
                if (!TypeCheckExtendContainsExtend(entry.extends, extendDecl)) {
                    entry.extends.add(extendDecl)
                }
            } else {
                let entry = TyExtendsEntry(extendTy)
                entry.extends.add(extendDecl)
                tm.builtinTyToExtendMap.add(entry)
            }
            continue
        }
        if (let Some(extendDeclPtr) <- Ty.GetDeclPtrOfTy(Some(extendTy))) {
            if (let Some(inheritableDecl) <- (extendDeclPtr as InheritableDecl)) {
                if (let Some(entry) <- TypeCheckExtendFindDeclEntry(tm, inheritableDecl)) {
                    if (!TypeCheckExtendContainsExtend(entry.extends, extendDecl)) {
                        entry.extends.add(extendDecl)
                    }
                } else {
                    let entry = DeclExtendsEntry(inheritableDecl)
                    entry.extends.add(extendDecl)
                    tm.declToExtendMap.add(entry)
                }
                for (interfaceType in extendDecl.inheritedTypes) {
                    if (let Some(interfaceDeclPtr) <- Ty.GetDeclPtrOfTy(interfaceType.GetTy())) {
                        if (let Some(interfaceDecl) <- (interfaceDeclPtr as InterfaceDecl)) {
                            TypeCheckExtendAddUniqueDecl(interfaceDecl.subDecls, inheritableDecl)
                        }
                    }
                }
            }
        }
    }
}

private func TypeCheckExtendContainsExtend(values: ArrayList<ExtendDecl>, candidate: ExtendDecl): Bool {
    for (value in values) {
        if (SameDecl(value, candidate)) {
            return true
        }
    }
    return false
}

public func TypeCheckExtendBuildMap(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    extends: ArrayList<ExtendDecl>
): Unit {
    for (extendDecl in extends) {
        TypeCheckExtendPreCheckExtend(diag, tm, ctx, extendDecl)
    }
    TypeCheckExtendUpdateExtendMap(tm, extends)
}

public func TypeCheckExtendSetExternalAttr(ctx: ASTContext, extendDecl: ExtendDecl): Unit {
    if (let None <- extendDecl.extendedType) {
        return
    }
    let extendedType = extendDecl.extendedType.getOrThrow()
    var extendedTypeTarget = Ty.GetDeclPtrOfTy(extendedType.GetTy())
    if (let None <- extendedTypeTarget) {
        extendedTypeTarget = GetRealTarget(extendedType.GetTarget())
    }
    var hasExtendedTypeTarget = false
    var importedExtendedTarget = false
    if (let Some(target) <- extendedTypeTarget) {
        hasExtendedTypeTarget = true
        importedExtendedTarget = target.TestAttr(Attribute.IMPORTED)
    }
    if ((!hasExtendedTypeTarget || importedExtendedTarget) && extendDecl.inheritedTypes.isEmpty()) {
        return
    }
    var accessLevel = AccessLevel.PUBLIC
    if (let Some(target) <- extendedTypeTarget) {
        accessLevel = GetAccessLevel(target)
    }
    if (let Some(generic) <- extendDecl.generic) {
        for (constraint in generic.genericConstraints) {
            for (upperBound in constraint.upperBounds) {
                if (let Some(decl) <- GetRealTarget(upperBound.GetTarget())) {
                    accessLevel = TypeCheckExtendMinAccess(accessLevel, GetAccessLevel(decl))
                }
            }
        }
    }
    var differentPackage = ctx.fullPackageName != "std.core"
    if (let Some(target) <- extendedTypeTarget) {
        differentPackage = target.fullPackageName != ctx.fullPackageName
    }
    if (differentPackage) {
        var interfaceAccessLevel = AccessLevel.PRIVATE
        for (interfaceType in extendDecl.inheritedTypes) {
            if (let Some(decl) <- interfaceType.GetTarget()) {
                interfaceAccessLevel = TypeCheckExtendMaxAccess(interfaceAccessLevel, GetAccessLevel(decl))
            } else {
                return
            }
        }
        accessLevel = TypeCheckExtendMinAccess(accessLevel, interfaceAccessLevel)
    }
    extendDecl.EnableAttr(GetAttrByAccessLevel(accessLevel))
}

public func TypeCheckExtendCheckImmutExtendInheritMutSuper(
    diag: BasicDiagnosticEngine,
    inheritedType: Type,
    extendDecl: ExtendDecl
): Bool {
    if (!Ty.IsTyCorrect(extendDecl.GetTy()) || !extendDecl.GetTy().getOrThrow().IsImmutableType()) {
        return true
    }
    if (let None <- inheritedType.GetTarget()) {
        return true
    }
    let target = inheritedType.GetTarget().getOrThrow()
    if (target.astKind != ASTKind.INTERFACE_DECL || target.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
        return true
    }
    if (let None <- (target as InterfaceDecl)) {
        return true
    }
    let interfaceDecl = (target as InterfaceDecl).getOrThrow()
    for (member in interfaceDecl.GetMemberDecls()) {
        if (member.astKind == ASTKind.PROP_DECL && member.TestAttr(Attribute.MUT)) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_interface_is_not_extendable,
                TypeCheckExtendRange(extendDecl),
                arguments: [interfaceDecl.identifier.Val()])
            builder.AddNote("interface '" + interfaceDecl.identifier.Val() +
                "' contains mutable member '" + member.identifier.Val() + "'")
            builder.Emit()
            return false
        }
    }
    for (parentType in interfaceDecl.inheritedTypes) {
        if (!TypeCheckExtendCheckImmutExtendInheritMutSuper(diag, parentType, extendDecl)) {
            return false
        }
    }
    return true
}

public func TypeCheckExtendCheckDecl(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    extendDecl: ExtendDecl
): Bool {
    if (extendDecl.TestAttr(Attribute.IS_CHECK_VISITED)) {
        return true
    }
    extendDecl.EnableAttr(Attribute.IS_CHECK_VISITED)
    var valid = TypeCheckExtendPreCheckExtend(diag, tm, ctx, extendDecl)
    var extendedDecl: Option<Decl> = None
    if (let Some(extendedType) <- extendDecl.extendedType) {
        extendedDecl = extendedType.GetTarget()
    }
    for (inheritedType in extendDecl.inheritedTypes) {
        if (let Some(decl) <- extendedDecl) {
            if (!TypeCheckClassLikeCheckSealedInheritance(diag, decl, inheritedType)) {
                valid = false
            }
            if (!TypeCheckClassLikeCheckThreadContextInheritance(diag, decl, inheritedType)) {
                valid = false
            }
        }
        if (!TypeCheckExtendCheckImmutExtendInheritMutSuper(diag, inheritedType, extendDecl)) {
            valid = false
        }
    }
    for (member in extendDecl.members) {
        if (Ty.IsTyCorrect(extendDecl.GetTy()) && extendDecl.GetTy().getOrThrow().IsImmutableType()) {
            if (let Some(propDecl) <- (member as PropDecl)) {
                if (propDecl.isVar) {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_immutable_type_illegal_property,
                        TypeCheckExtendRange(propDecl))
                    builder.Emit()
                    valid = false
                }
            }
        }
    }
    return valid
}

public func SelfhostPortStatus_TypeCheckExtend(): Bool {
    return true
}
