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

private func TypeCheckExtendIdentifierRange(decl: Decl): BasicRange {
    let beginPos = decl.identifier.Begin()
    if (!beginPos.IsZero()) {
        let endPos = decl.identifier.End()
        if (!endPos.IsZero()) {
            return MakeRange(beginPos, endPos)
        }
    }
    return TypeCheckExtendRange(decl)
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

private func TypeCheckExtendHasSameDecl(values: ArrayList<Decl>, candidate: Decl): Bool {
    for (value in values) {
        if (SameDecl(value, candidate)) {
            return true
        }
    }
    return false
}

private func TypeCheckExtendAddUniqueDecl(values: ArrayList<Decl>, candidate: Decl): Unit {
    if (!TypeCheckExtendHasSameDecl(values, candidate)) {
        values.add(candidate)
    }
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

private func TypeCheckExtendDeclKey(decl: Decl): String {
    return "${decl.fullPackageName}:${decl.identifier.Val()}:${decl.begin.line}:${decl.begin.column}"
}

private func TypeCheckExtendTyKey(ty: Ty): String {
    if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
        return TypeCheckExtendDeclKey(decl) + ty.PrintTypeArgs()
    }
    return ty.String()
}

private func TypeCheckExtendContainsKey(keys: ArrayList<String>, key: String): Bool {
    for (value in keys) {
        if (value == key) {
            return true
        }
    }
    return false
}

private func TypeCheckExtendRecordKey(keys: ArrayList<String>, key: String): Bool {
    if (TypeCheckExtendContainsKey(keys, key)) {
        return false
    }
    keys.add(key)
    return true
}

private func TypeCheckExtendHasInheritedInterface(tm: TypeManager, extendedTy: Ty, interfaceTy: Ty): Bool {
    if (let Some(extendedDecl) <- Ty.GetDeclPtrOfTy(Some(extendedTy))) {
        if (let Some(inheritableDecl) <- (extendedDecl as InheritableDecl)) {
            if (let Some(declTy) <- inheritableDecl.GetTy()) {
                let superTys = tm.GetAllSuperTys(declTy, withExtended: false)
                for (superTy in superTys.values) {
                    if (superTy.IsInterface() && SameTy(superTy, interfaceTy)) {
                        return true
                    }
                }
            }
        }
    }
    return false
}

private func TypeCheckExtendDiagDuplicateInterface(
    diag: BasicDiagnosticEngine,
    interfaceType: Type,
    interfaceTy: Ty,
    extendedTy: Ty
): Unit {
    if (interfaceType.TestAttr(Attribute.IMPORTED)) {
        return
    }
    let builder = diag.DiagnoseRefactor(
        BasicDiagKindRefactor.sema_extend_duplicate_interface,
        TypeCheckExtendRange(interfaceType),
        arguments: [interfaceTy.String(), extendedTy.String()])
    builder.Emit()
}

private func TypeCheckExtendDiagNonExtendableCoreInterface(
    diag: BasicDiagnosticEngine,
    interfaceType: Type,
    interfaceTy: Ty
): Unit {
    if (let Some(interfaceDecl) <- Ty.GetDeclPtrOfTy(Some(interfaceTy))) {
        let name = interfaceDecl.identifier.Val()
        if (interfaceDecl.fullPackageName == "std.core" && (name == "Any" || name == "CType")) {
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_interface_is_not_extendable,
                TypeCheckExtendRange(interfaceType),
                arguments: [name])
            builder.Emit()
        }
    }
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

private func TypeCheckExtendAddUniqueExtends(target: ArrayList<ExtendDecl>, source: ArrayList<ExtendDecl>): Unit {
    for (extendDecl in source) {
        if (!TypeCheckExtendContainsExtend(target, extendDecl)) {
            target.add(extendDecl)
        }
    }
}

private func TypeCheckExtendCollectRelatedExtends(tm: TypeManager, decl: InheritableDecl): ArrayList<ExtendDecl> {
    let out = ArrayList<ExtendDecl>()
    TypeCheckExtendAddUniqueExtends(out, tm.GetDeclExtends(decl))
    if (let Some(classDecl) <- (decl as ClassDecl)) {
        var current = classDecl.GetSuperClassDecl()
        while (let Some(superClass) <- current) {
            TypeCheckExtendAddUniqueExtends(out, tm.GetDeclExtends(superClass))
            current = superClass.GetSuperClassDecl()
        }
    }
    return out
}

public func TypeCheckExtendCheckOrphanRule(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    ctx: ASTContext,
    extendDecl: ExtendDecl
): Bool {
    if (let Some(pkg) <- ctx.curPackage) {
        if (pkg.TestAttr(Attribute.IMPORTED)) {
            return true
        }
    }
    if (let None <- extendDecl.extendedType) {
        return true
    }
    let extendedType = extendDecl.extendedType.getOrThrow()
    if (!Ty.IsTyCorrect(extendedType.GetTy())) {
        return true
    }
    let extendedTy = extendedType.GetTy().getOrThrow()
    let extendedTypeTarget = Ty.GetInheritableDeclPtrOfTy(Some(extendedTy))
    let otherPackageExtendInterfaceTy = TySet()
    if (let Some(target) <- extendedTypeTarget) {
        if (let Some(targetTy) <- target.GetTy()) {
            otherPackageExtendInterfaceTy.AddAll(tm.GetAllSuperTys(targetTy, withExtended: false))
        }
    }
    let extends = if (let Some(target) <- extendedTypeTarget) {
        TypeCheckExtendCollectRelatedExtends(tm, target)
    } else {
        tm.GetAllExtendsByTy(extendedTy)
    }
    for (relatedExtend in extends) {
        if (relatedExtend.fullPackageName == ctx.fullPackageName) {
            continue
        }
        var typeMapping = TypeSubst()
        if (let Some(relatedTy) <- relatedExtend.GetTy()) {
            typeMapping = InverseMapping(GenerateTypeMapping(extendDecl, relatedTy.typeArgs))
        }
        for (inheritedType in relatedExtend.inheritedTypes) {
            if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                let allSuperTys = tm.GetAllSuperTys(inheritedTy)
                for (superTy in allSuperTys.values) {
                    otherPackageExtendInterfaceTy.Add(tm.GetInstantiatedTy(superTy, typeMapping))
                }
            }
        }
    }
    var isImportedExtendedType = extendedTy.IsBuiltin()
    if (let Some(target) <- extendedTypeTarget) {
        if (target.fullPackageName != ctx.fullPackageName) {
            isImportedExtendedType = true
        }
    }
    let externalDecls = TySet()
    for (inheritedType in extendDecl.inheritedTypes) {
        if (let Some(inheritedTy) <- inheritedType.GetTy()) {
            let allSuperTys = tm.GetAllSuperTys(inheritedTy)
            for (superTy in allSuperTys.values) {
                if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(superTy))) {
                    if (decl.fullPackageName != ctx.fullPackageName &&
                        !otherPackageExtendInterfaceTy.Contains(superTy)) {
                        externalDecls.Add(superTy)
                    }
                }
            }
        }
    }
    if (isImportedExtendedType && !externalDecls.values.isEmpty()) {
        let extendedTypeName = if (let Some(target) <- extendedTypeTarget) {
            target.identifier.Val()
        } else {
            extendedTy.String()
        }
        let extendedKind = if (let Some(_) <- extendedTypeTarget) { "imported" } else { "primitive" }
        let builder = diag.DiagnoseRefactor(
            BasicDiagKindRefactor.sema_type_cannot_extend_imported_interface,
            TypeCheckExtendRange(extendedType),
            arguments: [extendedKind, extendedTypeName])
        builder.AddNote("used external interface: " + Ty.GetTypesToStr(externalDecls.values, " "))
        builder.Emit()
        return false
    }
    return true
}

private func TypeCheckExtendCheckDefImplWithoutOutsideGeneric(
    diag: BasicDiagnosticEngine,
    inheritedDecl: Decl,
    extendDecl: ExtendDecl
): Bool {
    if (let None <- (inheritedDecl as InterfaceDecl)) {
        return true
    }
    let interfaceDecl = (inheritedDecl as InterfaceDecl).getOrThrow()
    if (let None <- interfaceDecl.generic) {
        return true
    }
    let generic = interfaceDecl.generic.getOrThrow()
    if (generic.typeParameters.isEmpty()) {
        return true
    }
    let outerGenericParamTys = ArrayList<Ty>()
    for (typeParam in generic.typeParameters) {
        if (let Some(paramTy) <- typeParam.GetTy()) {
            outerGenericParamTys.add(paramTy)
        }
    }
    if (outerGenericParamTys.isEmpty()) {
        return true
    }
    var valid = true
    for (member in interfaceDecl.GetMemberDecls()) {
        if (!member.TestAttr(Attribute.DEFAULT) || !Ty.IsTyCorrect(member.GetTy())) {
            continue
        }
        let usedGenericTypeParamTys = member.GetTy().getOrThrow().GetGenericTyArgs()
        var usedOutsideGeneric = false
        for (outerTy in outerGenericParamTys) {
            if (TypeCheckExtendHasSameTy(usedGenericTypeParamTys, outerTy)) {
                usedOutsideGeneric = true
                break
            }
        }
        if (!usedOutsideGeneric) {
            let typeName = if (let Some(extendedTy) <- extendDecl.GetTy()) {
                "extend " + extendedTy.String()
            } else {
                "extend"
            }
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_extend_member_cannot_shadow,
                TypeCheckExtendIdentifierRange(member),
                arguments: [member.identifier.Val(), typeName])
            builder.Emit()
            valid = false
        }
    }
    return valid
}

public func TypeCheckExtendCheckDupDefImplByDiffTypArgs(
    diag: BasicDiagnosticEngine,
    extendDecls: ArrayList<ExtendDecl>,
    extendDecl: ExtendDecl
): Bool {
    let directlyImplementedInterfaces = ArrayList<Decl>()
    for (otherExtend in extendDecls) {
        if (SameDecl(otherExtend, extendDecl)) {
            continue
        }
        for (inheritedType in otherExtend.inheritedTypes) {
            if (let Some(inheritedDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
                TypeCheckExtendAddUniqueDecl(directlyImplementedInterfaces, inheritedDecl)
            }
        }
    }
    var valid = true
    for (inheritedType in extendDecl.inheritedTypes) {
        if (let Some(inheritedDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
            if (TypeCheckExtendHasSameDecl(directlyImplementedInterfaces, inheritedDecl)) {
                if (!TypeCheckExtendCheckDefImplWithoutOutsideGeneric(diag, inheritedDecl, extendDecl)) {
                    valid = false
                }
            }
        }
    }
    return valid
}

private func TypeCheckExtendMergeTypeSubstNoConflict(target: TypeSubst, source: TypeSubst): Bool {
    for (entry in source.entries) {
        if (let Some(existing) <- target.Get(entry.tyVar)) {
            if (!SameTy(existing, entry.ty)) {
                return false
            }
        } else {
            target.Put(entry.tyVar, entry.ty)
        }
    }
    return true
}

private func TypeCheckExtendCheckSpecializationExtendDupInstantiation(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    extendedDeclTy: Ty,
    compareExtend: ExtendDecl,
    beComparedDecl: InheritableDecl,
    instantMapping: TypeSubst,
    checkParent: Bool
): Bool {
    var valid = true
    for (compareSuperInterface in compareExtend.inheritedTypes) {
        if (let None <- compareSuperInterface.GetTy()) {
            continue
        }
        let compareTy = compareSuperInterface.GetTy().getOrThrow()
        if (compareTy.HasGeneric() || compareTy.typeArgs.isEmpty()) {
            continue
        }
        let allSuperTys = TySet()
        for (inheritedType in beComparedDecl.inheritedTypes) {
            if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                if (checkParent) {
                    allSuperTys.AddAll(tm.GetAllSuperTys(inheritedTy))
                } else {
                    allSuperTys.Add(inheritedTy)
                }
            }
        }
        for (beComparedSuperInterfaceTy in allSuperTys.values) {
            if (beComparedSuperInterfaceTy.kind != TypeKind.TYPE_INTERFACE ||
                !beComparedSuperInterfaceTy.HasGeneric()) {
                continue
            }
            let instantTy = tm.GetInstantiatedTy(beComparedSuperInterfaceTy, instantMapping)
            if (!SameTy(instantTy, compareTy)) {
                continue
            }
            let builder = diag.DiagnoseRefactor(
                BasicDiagKindRefactor.sema_extend_duplicate_interface,
                TypeCheckExtendRange(compareSuperInterface),
                arguments: [compareTy.String(), extendedDeclTy.String()])
            builder.AddNote(MakeRange(beComparedDecl.begin, beComparedDecl.end),
                "it may be an instantiated version of the following declaration")
            builder.Emit()
            valid = false
        }
    }
    return valid
}

public func TypeCheckExtendCheckSpecializationExtend(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    extendedDecl: InheritableDecl,
    extendDecl: ExtendDecl,
    otherExtendDecls: ArrayList<ExtendDecl>
): Bool {
    if (let None <- extendedDecl.GetTy()) {
        return true
    }
    let extendedDeclTy = extendedDecl.GetTy().getOrThrow()
    if (!extendedDeclTy.HasGeneric()) {
        return true
    }
    if (let None <- extendDecl.extendedType) {
        return true
    }
    let extendedType = extendDecl.extendedType.getOrThrow()
    if (!Ty.IsTyCorrect(extendedType.GetTy())) {
        return true
    }
    let orig2specMapping = GenerateTypeMapping(extendedDecl, extendedType.GetTy().getOrThrow().typeArgs)
    var valid = TypeCheckExtendCheckSpecializationExtendDupInstantiation(
        diag, tm, extendedDeclTy, extendDecl, extendedDecl, orig2specMapping, true)
    for (otherExtend in otherExtendDecls) {
        if (SameDecl(otherExtend, extendDecl)) {
            continue
        }
        if (let None <- otherExtend.GetTy()) {
            continue
        }
        if (!otherExtend.GetTy().getOrThrow().HasGeneric()) {
            continue
        }
        if (let None <- otherExtend.extendedType) {
            continue
        }
        let otherExtendedType = otherExtend.extendedType.getOrThrow()
        if (!Ty.IsTyCorrect(otherExtendedType.GetTy())) {
            continue
        }
        let orig2genericMapping = GenerateTypeMapping(extendedDecl, otherExtendedType.GetTy().getOrThrow().typeArgs)
        let instantMapping = TypeSubst()
        var needCheck = true
        for (typeArg in extendedDeclTy.typeArgs) {
            if (let Some(tyArgGen) <- (typeArg as GenericsTy)) {
                let mapping = GenerateTypeMappingByTy(orig2genericMapping.Get(tyArgGen), orig2specMapping.Get(tyArgGen))
                if (!TypeCheckExtendMergeTypeSubstNoConflict(instantMapping, mapping)) {
                    needCheck = false
                    break
                }
            }
        }
        if (needCheck) {
            if (!TypeCheckExtendCheckSpecializationExtendDupInstantiation(
                diag, tm, extendedDeclTy, extendDecl, otherExtend, instantMapping, false)) {
                valid = false
            }
        }
    }
    return valid
}

private func TypeCheckExtendFindCoreExtend(extends: ArrayList<ExtendDecl>): Option<ExtendDecl> {
    for (extendDecl in extends) {
        if (extendDecl.fullPackageName == "std.core") {
            return Some(extendDecl)
        }
    }
    return None
}

public func TypeCheckExtendCheckBuiltinPointerSpecializations(
    diag: BasicDiagnosticEngine,
    tm: TypeManager
): Bool {
    var valid = true
    for (entry in tm.builtinTyToExtendMap) {
        if (!entry.ty.IsPointer()) {
            continue
        }
        if (let Some(coreExtend) <- TypeCheckExtendFindCoreExtend(entry.extends)) {
            for (extendDecl in entry.extends) {
                if (SameDecl(coreExtend, extendDecl)) {
                    continue
                }
                if (!TypeCheckExtendCheckSpecializationExtend(diag, tm, coreExtend, extendDecl, entry.extends)) {
                    valid = false
                }
            }
        }
    }
    return valid
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
    TypeCheckExtendCheckDuplicateInterfaces(diag, tm, extends)
    TypeCheckExtendCheckBuiltinPointerSpecializations(diag, tm)
}

public func TypeCheckExtendCheckDuplicateInterfaces(
    diag: BasicDiagnosticEngine,
    tm: TypeManager,
    extends: ArrayList<ExtendDecl>
): Bool {
    var valid = true
    let seenExtendTyKeys = ArrayList<String>()
    let seenInterfaceKeys = ArrayList<String>()
    for (extendDecl in extends) {
        if (let None <- extendDecl.extendedType) {
            continue
        }
        let extendedType = extendDecl.extendedType.getOrThrow()
        if (!Ty.IsTyCorrect(extendedType.GetTy())) {
            continue
        }
        let extendedTy = extendedType.GetTy().getOrThrow()
        let extendedKey = TypeCheckExtendTyKey(extendedTy)
        var localSeen = ArrayList<String>()
        for (interfaceType in extendDecl.inheritedTypes) {
            if (!Ty.IsTyCorrect(interfaceType.GetTy())) {
                continue
            }
            let interfaceTy = interfaceType.GetTy().getOrThrow()
            if (!interfaceTy.IsInterface()) {
                continue
            }
            TypeCheckExtendDiagNonExtendableCoreInterface(diag, interfaceType, interfaceTy)
            let interfaceKey = TypeCheckExtendTyKey(interfaceTy)
            let pairKey = extendedKey + "<:" + interfaceKey
            var duplicate = TypeCheckExtendContainsKey(localSeen, interfaceKey)
            if (!duplicate) {
                duplicate = TypeCheckExtendHasInheritedInterface(tm, extendedTy, interfaceTy)
            }
            if (!duplicate && TypeCheckExtendContainsKey(seenInterfaceKeys, pairKey)) {
                duplicate = true
            }
            if (duplicate) {
                TypeCheckExtendDiagDuplicateInterface(diag, interfaceType, interfaceTy, extendedTy)
                valid = false
            }
            let _ = TypeCheckExtendRecordKey(localSeen, interfaceKey)
            if (TypeCheckExtendContainsKey(seenExtendTyKeys, extendedKey)) {
                let _ = TypeCheckExtendRecordKey(seenInterfaceKeys, pairKey)
            }
        }
        let _ = TypeCheckExtendRecordKey(seenExtendTyKeys, extendedKey)
        for (interfaceKey in localSeen) {
            let _ = TypeCheckExtendRecordKey(seenInterfaceKeys, extendedKey + "<:" + interfaceKey)
        }
    }
    return valid
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
    if (!TypeCheckExtendCheckOrphanRule(diag, tm, ctx, extendDecl)) {
        valid = false
    }
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
            if (let Some(funcDecl) <- (member as FuncDecl)) {
                if (!extendDecl.GetTy().getOrThrow().IsEnum() && TypeCheckExtendIsIndexAssignmentOperator(funcDecl)) {
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_immutable_type_extend_assignment_index_operator,
                        TypeCheckExtendIdentifierRange(funcDecl))
                    builder.Emit()
                    valid = false
                }
            }
            if (let Some(propDecl) <- (member as PropDecl)) {
                if (propDecl.isVar) {
                    let range = if (let Some(modifier) <- FindModifier(propDecl, TokenKind.MUT)) {
                        MakeRange(modifier.begin, modifier.end)
                    } else {
                        TypeCheckExtendIdentifierRange(propDecl)
                    }
                    let builder = diag.DiagnoseRefactor(
                        BasicDiagKindRefactor.sema_immutable_type_illegal_property,
                        range)
                    builder.Emit()
                    valid = false
                }
            }
        }
    }
    if (let Some(decl) <- extendedDecl) {
        if (let Some(inheritableDecl) <- (decl as InheritableDecl)) {
            let extends = tm.GetDeclExtends(inheritableDecl)
            if (!TypeCheckExtendCheckDupDefImplByDiffTypArgs(diag, extends, extendDecl)) {
                valid = false
            }
            if (!TypeCheckExtendCheckSpecializationExtend(diag, tm, inheritableDecl, extendDecl, extends)) {
                valid = false
            }
        }
    }
    return valid
}

private func TypeCheckExtendIsIndexAssignmentOperator(funcDecl: FuncDecl): Bool {
    if (funcDecl.op != TokenKind.LSQUARE) {
        return false
    }
    if (let Some(body) <- funcDecl.funcBody) {
        if (!body.paramLists.isEmpty()) {
            let params = body.paramLists[0].params
            return params.size > 1 && params[params.size - 1].isNamedParam
        }
    }
    if (let Some(rawTy) <- funcDecl.GetTy()) {
        if (let Some(funcTy) <- (rawTy as FuncTy)) {
            return funcTy.paramTys.size > 1 && funcTy.retTy.IsUnit()
        }
    }
    return false
}

public func SelfhostPortStatus_TypeCheckExtend(): Bool {
    return true
}
