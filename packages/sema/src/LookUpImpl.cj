package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::modules.GetPackageRelation as ModulesGetPackageRelation
import cangjie_compiler::modules.PackageRelation as ModulesPackageRelation
import cangjie_compiler::modules.SplitQualifiedName as ModulesSplitQualifiedName

private let LOOKUP_CORE_PACKAGE_NAME: String = "std.core"
private let LOOKUP_AST_PACKAGE_NAME: String = "std.ast"

public class LookupInfo {
    public var baseTy: Option<Ty> = None
    public var file: Option<File> = None
    public var lookupInherit: Bool = true
    public var lookupExtend: Bool = true
    public var isSetter: Bool = false

    public init(baseTy!: Option<Ty> = None, file!: Option<File> = None, lookupInherit!: Bool = true,
        lookupExtend!: Bool = true, isSetter!: Bool = false) {
        this.baseTy = baseTy
        this.file = file
        this.lookupInherit = lookupInherit
        this.lookupExtend = lookupExtend
        this.isSetter = isSetter
    }

    public func Clone(): LookupInfo {
        return LookupInfo(baseTy: baseTy, file: file, lookupInherit: lookupInherit,
            lookupExtend: lookupExtend, isSetter: isSetter)
    }
}

private class LookupBoolBox {
    public var value: Bool

    public init(value: Bool) {
        this.value = value
    }
}

private func addDeclUnique(values: ArrayList<Decl>, decl: Decl): Unit {
    for (value in values) {
        if (sameImportedAwareDecl(value, decl)) {
            return
        }
    }
    values.add(decl)
}

private func sameImportedAwareDecl(left: Decl, right: Decl): Bool {
    if (left.TestAttr(Attribute.IMPORTED) && right.TestAttr(Attribute.IMPORTED)) {
        if (!left.rawMangleName.isEmpty() || !right.rawMangleName.isEmpty()) {
            return left.rawMangleName == right.rawMangleName
        }
        if (!left.mangledName.isEmpty() || !right.mangledName.isEmpty()) {
            return left.mangledName == right.mangledName
        }
    }
    return SameDecl(left, right)
}

private func importedAwareDeclKey(decl: Decl): String {
    if (decl.TestAttr(Attribute.IMPORTED)) {
        if (!decl.rawMangleName.isEmpty()) {
            return "raw|" + decl.rawMangleName
        }
        if (!decl.mangledName.isEmpty()) {
            return "mangled|" + decl.mangledName
        }
    }
    return "decl|" + ASTKindName(decl.astKind) + "|" + decl.fullPackageName + "|" + decl.identifier.Val() + "|" +
        decl.begin.fileID.toString() + ":" + decl.begin.line.toString() + ":" + decl.begin.column.toString() + "|" +
        decl.end.fileID.toString() + ":" + decl.end.line.toString() + ":" + decl.end.column.toString()
}

private func addDeclUnique(values: ArrayList<Decl>, keys: HashSet<String>, decl: Decl): Unit {
    let key = importedAwareDeclKey(decl)
    if (keys.contains(key)) {
        return
    }
    values.add(decl)
    keys.add(key)
}

private func insertDeclByPosition(values: ArrayList<Decl>, decl: Decl): Unit {
    var idx: Int64 = 0
    while (idx < values.size) {
        if (decl.begin < values[idx].begin ||
            (decl.begin == values[idx].begin && ASTKindIndex(decl.astKind) < ASTKindIndex(values[idx].astKind))) {
            values.add(decl, at: idx)
            return
        }
        idx++
    }
    values.add(decl)
}

private func sortedDecls(decls: ArrayList<Decl>): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (decl in decls) {
        insertDeclByPosition(out, decl)
    }
    return out
}

private func isAllFuncDecl(decls: ArrayList<Decl>): Bool {
    if (decls.isEmpty()) {
        return false
    }
    for (decl in decls) {
        if (!decl.IsFunc()) {
            return false
        }
    }
    return true
}

private func ignoredMember(decl: Decl): Bool {
    if (decl.TestAttr(Attribute.TOOL_ADD)) {
        return false
    }
    return decl.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.MAIN_ENTRY) ||
        decl.astKind == ASTKind.PRIMARY_CTOR_DECL
}

private func isDefinedAfter(target: Decl, ref: Node): Bool {
    return ref.begin < target.begin
}

private func sameNodeShape(left: Node, right: Node): Bool {
    return left.astKind == right.astKind && left.begin == right.begin && left.end == right.end
}

private func containsNode(root: Node, needle: Node): Bool {
    let found = LookupBoolBox(false)
    let walker = Walker(root, visitPre: { node: Node =>
        if (sameNodeShape(node, needle)) {
            found.value = true
            return VisitAction.STOP_NOW
        }
        VisitAction.WALK_CHILDREN
    })
    let _ = walker.Walk()
    return found.value
}

private func isNodeInVarDecl(ctx: ASTContext, node: Node, vd: VarDecl): Bool {
    let outer = ctx.GetOuterVarDeclAbstract(vd)
    return containsNode(outer, node)
}

private func isNodeInDestructed(node: Node, vd: VarDecl): Bool {
    if (let Some(pattern) <- vd.parentPattern) {
        if (let Some(ctxExpr) <- pattern.ctxExpr) {
            return containsNode(ctxExpr, node)
        }
    }
    return false
}

private func isNodeInTypeAliasDecl(node: Node, tad: TypeAliasDecl): Bool {
    if (let Some(typeNode) <- tad.typeNode) {
        return containsNode(typeNode, node)
    }
    return false
}

private func isTargetVisibleToNode(target: Decl, node: Node): Bool {
    if (!target.TestAttr(Attribute.PRIVATE)) {
        return true
    }
    if (let Some(leftFile) <- target.curFile) {
        if (let Some(rightFile) <- node.curFile) {
            return leftFile.fileHash == rightFile.fileHash && leftFile.filePath == rightFile.filePath
        }
        return false
    }
    return true
}

private func propAccessibleForAccess(propDecl: PropDecl, isSetter: Bool): Bool {
    if (isSetter) {
        return !propDecl.isVar || !propDecl.setters.isEmpty()
    }
    return !propDecl.getters.isEmpty()
}

private func extendAccessibleForLookup(info: LookupInfo, extendDecl: ExtendDecl): Bool {
    if (let Some(file) <- info.file) {
        if (let Some(pkg) <- file.curPackage) {
            if (extendDecl.fullPackageName == pkg.fullPackageName) {
                return true
            }
            let relation = ModulesGetPackageRelation(pkg.fullPackageName, extendDecl.fullPackageName)
            return nodeVisibleInRelation(extendDecl, relation)
        }
    }
    return true
}

private func nodeVisibleInRelation(node: Node, relation: ModulesPackageRelation): Bool {
    return node.TestAttr(Attribute.PUBLIC) || relation == ModulesPackageRelation.SAME_PACKAGE ||
        (node.TestAttr(Attribute.PROTECTED) && relation != ModulesPackageRelation.NONE) ||
        (node.TestAttr(Attribute.INTERNAL) &&
            (relation == ModulesPackageRelation.CHILD || relation == ModulesPackageRelation.SAME_PACKAGE))
}

private func accessLevelRank(level: AccessLevel): Int64 {
    return match (level) {
        case AccessLevel.PRIVATE => 0
        case AccessLevel.INTERNAL => 1
        case AccessLevel.PROTECTED => 2
        case AccessLevel.PUBLIC => 3
    }
}

private func importAllowsAccess(importSpec: ImportSpec, decl: Decl): Bool {
    return accessLevelRank(GetAccessLevel(importSpec)) <= accessLevelRank(GetAccessLevel(decl))
}

private func addMemberIfValidForLookup(results: ArrayList<Decl>, typeManager: TypeManager, baseTy: Option<Ty>,
    isSetter: Bool, decl: Decl): Unit {
    if (let Some(propDecl) <- (decl as PropDecl)) {
        if (!propAccessibleForAccess(propDecl, isSetter)) {
            return
        }
    }
    if (decl.astKind != ASTKind.FUNC_DECL) {
        addDeclUnique(results, decl)
        return
    }
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        var idx: Int64 = 0
        while (idx < results.size) {
            if (let Some(existingFunc) <- (results[idx] as FuncDecl)) {
                if (typeManager.PairIsOverrideOrImpl(existingFunc, funcDecl, baseTy: baseTy)) {
                    if (existingFunc.TestAttr(Attribute.ABSTRACT) && !funcDecl.TestAttr(Attribute.ABSTRACT)) {
                        results.remove(at: idx)
                        addDeclUnique(results, decl)
                    }
                    return
                }
            }
            idx++
        }
    }
    addDeclUnique(results, decl)
}

private func resolveOverrideOrShadow(results: ArrayList<Decl>, typeManager: TypeManager, decl: Decl,
    parentTy: Option<Ty>): Unit {
    if (decl.astKind == ASTKind.PROP_DECL && !decl.TestAttr(Attribute.ABSTRACT)) {
        var propIdx: Int64 = 0
        while (propIdx < results.size) {
            if (results[propIdx].TestAttr(Attribute.ABSTRACT)) {
                results.remove(at: propIdx)
            } else {
                propIdx++
            }
        }
    }
    var idx: Int64 = 0
    while (idx < results.size) {
        let current = results[idx]
        if (current.astKind != ASTKind.FUNC_DECL && current.astKind != ASTKind.PROP_DECL) {
            idx++
            continue
        }
        var currentOuter: Option<Ty> = None
        if (let Some(outer) <- current.outerDecl) {
            currentOuter = outer.GetTy()
        }
        let currentOverrides = typeManager.PairIsOverrideOrImpl(current, decl, baseTy: currentOuter, parentTy: parentTy)
        let declOverrides = typeManager.PairIsOverrideOrImpl(decl, current, baseTy: parentTy, parentTy: currentOuter)
        if (!currentOverrides && !declOverrides) {
            idx++
            continue
        }
        if (let Some(parent) <- parentTy) {
            if (let Some(currentTy) <- currentOuter) {
                if (typeManager.IsSubtype(parent, currentTy)) {
                    results.remove(at: idx)
                    addDeclUnique(results, decl)
                    return
                }
            }
        }
        if (current.TestAttr(Attribute.ABSTRACT) && !decl.TestAttr(Attribute.ABSTRACT)) {
            results.remove(at: idx)
            addDeclUnique(results, decl)
            return
        }
        return
    }
    addDeclUnique(results, decl)
}

private func fieldLookupExtend(typeManager: TypeManager, ty: Ty, fieldName: String, results: ArrayList<Decl>,
    info: LookupInfo): Unit {
    let extendDecls = ArrayList<Decl>()
    for (extendDecl in typeManager.GetAllExtendsByTy(ty)) {
        extendDecls.add(extendDecl)
    }
    let orderedExtends = sortedDecls(extendDecls)
    for (decl in orderedExtends) {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (!extendAccessibleForLookup(info, extendDecl)) {
                continue
            }
            for (member in extendDecl.members) {
                if (member.identifier == fieldName && !ignoredMember(member)) {
                    addDeclUnique(results, member)
                }
            }
        }
    }
    for (decl in orderedExtends) {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (!extendAccessibleForLookup(info, extendDecl)) {
                continue
            }
            for (inheritedType in extendDecl.inheritedTypes) {
                if (let Some(interfaceDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
                    if (interfaceDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                        continue
                    }
                    if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                        let mapping = GenerateTypeMappingByTy(extendDecl.GetTy(), Some(ty))
                        let instantiatedTy = typeManager.GetInstantiatedTy(inheritedTy, mapping)
                        if (let Some(interfaceTy) <- (instantiatedTy as InterfaceTy)) {
                            fieldLookupInterfaceTy(typeManager, interfaceTy, fieldName, results, info)
                        }
                    }
                }
            }
        }
    }
}

private func fieldLookupClass(typeManager: TypeManager, cd: ClassDecl, fieldName: String, results: ArrayList<Decl>,
    info: LookupInfo): Unit {
    if (let Some(body) <- cd.body) {
        for (member in body.decls) {
            if (member.identifier == fieldName && !ignoredMember(member)) {
                var foundTy = info.baseTy
                if (!member.IsClassLikeDecl() && member.TestAttr(Attribute.STATIC)) {
                    if (let Some(baseTy) <- foundTy) {
                        if (let Some(genericTy) <- Ty.GetGenericTyOfInsTy(baseTy)) {
                            foundTy = Some(genericTy)
                        }
                    }
                }
                addMemberIfValidForLookup(results, typeManager, foundTy, info.isSetter, member)
            }
        }
    }
    if (!info.lookupInherit) {
        return
    }
    for (inheritedType in cd.inheritedTypes) {
        if (let Some(superDecl) <- Ty.GetDeclPtrOfTy(inheritedType.GetTy())) {
            if (superDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                continue
            }
            if (let Some(superClass) <- (superDecl as ClassDecl)) {
                let superInfo = info.Clone()
                superInfo.lookupExtend = true
                fieldLookupClass(typeManager, superClass, fieldName, results, superInfo)
            } else if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                if (let Some(interfaceTy) <- (inheritedTy as InterfaceTy)) {
                    fieldLookupInterfaceTy(typeManager, interfaceTy, fieldName, results, LookupInfo(baseTy: info.baseTy))
                }
            }
        }
    }
    if (info.lookupExtend) {
        if (let Some(ty) <- cd.GetTy()) {
            fieldLookupExtend(typeManager, ty, fieldName, results, info)
        }
    }
}

private func fieldLookupInterfaceTy(typeManager: TypeManager, idTy: InterfaceTy, fieldName: String,
    results: ArrayList<Decl>, info: LookupInfo): Unit {
    if (let Some(id) <- idTy.declPtr) {
        if (let Some(body) <- id.body) {
            for (member in body.decls) {
                if (member.identifier != fieldName || ignoredMember(member)) {
                    continue
                }
                if (member.IsFuncOrProp()) {
                    resolveOverrideOrShadow(results, typeManager, member, idTy)
                } else {
                    addDeclUnique(results, member)
                }
            }
        }
        if (!info.lookupInherit) {
            return
        }
        for (inheritedType in id.inheritedTypes) {
            if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                if (let Some(interfaceTy) <- (inheritedTy as InterfaceTy)) {
                    if (let Some(interfaceDecl) <- interfaceTy.declPtr) {
                        if (!interfaceDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                            let promotedTys = Promotion(typeManager).Promote(idTy, inheritedTy)
                            let parentInfo = LookupInfo(baseTy: info.baseTy)
                            if (promotedTys.values.isEmpty()) {
                                fieldLookupInterfaceTy(typeManager, interfaceTy, fieldName, results, parentInfo)
                            } else {
                                for (promotedTy in promotedTys.values) {
                                    if (let Some(promotedInterfaceTy) <- (promotedTy as InterfaceTy)) {
                                        fieldLookupInterfaceTy(typeManager, promotedInterfaceTy, fieldName, results,
                                            parentInfo)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private func fieldLookupEnum(typeManager: TypeManager, ed: EnumDecl, fieldName: String, info: LookupInfo): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    for (ctor in ed.constructors) {
        if (ctor.identifier == fieldName && !ignoredMember(ctor)) {
            addDeclUnique(results, ctor)
        }
    }
    for (member in ed.members) {
        if (member.identifier == fieldName && !ignoredMember(member)) {
            addDeclUnique(results, member)
        }
    }
    for (inheritedType in ed.inheritedTypes) {
        if (let Some(inheritedTy) <- inheritedType.GetTy()) {
            if (let Some(interfaceTy) <- (inheritedTy as InterfaceTy)) {
                if (let Some(interfaceDecl) <- interfaceTy.declPtr) {
                    if (!interfaceDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                        fieldLookupInterfaceTy(typeManager, interfaceTy, fieldName, results, info)
                    }
                }
            }
        }
    }
    if (info.lookupExtend) {
        if (let Some(ty) <- ed.GetTy()) {
            fieldLookupExtend(typeManager, ty, fieldName, results, info)
        }
    }
    return results
}

private func fieldLookupStruct(typeManager: TypeManager, sd: StructDecl, fieldName: String,
    info: LookupInfo): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    if (let Some(body) <- sd.body) {
        for (member in body.decls) {
            if (member.identifier == fieldName && !ignoredMember(member)) {
                addDeclUnique(results, member)
            }
        }
    }
    for (inheritedType in sd.inheritedTypes) {
        if (let Some(inheritedTy) <- inheritedType.GetTy()) {
            if (let Some(interfaceTy) <- (inheritedTy as InterfaceTy)) {
                if (let Some(interfaceDecl) <- interfaceTy.declPtr) {
                    if (!interfaceDecl.TestAttr(Attribute.IN_REFERENCE_CYCLE)) {
                        fieldLookupInterfaceTy(typeManager, interfaceTy, fieldName, results, info)
                    }
                }
            }
        }
    }
    if (info.lookupExtend) {
        if (let Some(ty) <- sd.GetTy()) {
            fieldLookupExtend(typeManager, ty, fieldName, results, info)
        }
    }
    return results
}

private func fieldLookupPackage(pd: PackageDecl, fieldName: String): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    if (!pd.TestAttr(Attribute.IMPORTED)) {
        return results
    }
    for (file in pd.srcPackage.files) {
        for (decl in file.decls) {
            if (decl.identifier == fieldName && !decl.TestAttr(Attribute.MAIN_ENTRY)) {
                addDeclUnique(results, decl)
            }
        }
    }
    return results
}

private func lookupPackageMembers(pkg: Package, name: String): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    for (file in pkg.files) {
        for (decl in file.decls) {
            if (decl.identifier == name) {
                addDeclUnique(results, decl)
            }
        }
    }
    for (decl in pkg.genericInstantiatedDecls) {
        if (decl.identifier == name) {
            addDeclUnique(results, decl)
        }
    }
    for (decl in pkg.srcImportedNonGenericDecls) {
        if (decl.identifier == name) {
            addDeclUnique(results, decl)
        }
    }
    for (decl in pkg.inlineFuncDecls) {
        if (decl.identifier == name) {
            addDeclUnique(results, decl)
        }
    }
    return results
}

private func lookupPackageMember(pkg: Package, name: String): Option<Decl> {
    let members = lookupPackageMembers(pkg, name)
    if (!members.isEmpty()) {
        return Some(members[0])
    }
    return None
}

private func lookupKnownPackage(ctx: ASTContext, fullPackageName: String): Option<Package> {
    if (let Some(pkg) <- ctx.curPackage) {
        if (pkg.fullPackageName == fullPackageName) {
            return Some(pkg)
        }
    }
    for (packageDecl in ctx.packageDecls) {
        if (packageDecl.fullPackageName == fullPackageName ||
            packageDecl.srcPackage.fullPackageName == fullPackageName) {
            return Some(packageDecl.srcPackage)
        }
    }
    return None
}

private func lookupKnownPackageDecl(ctx: ASTContext, fullPackageName: String): Option<PackageDecl> {
    for (packageDecl in ctx.packageDecls) {
        if (packageDecl.fullPackageName == fullPackageName ||
            packageDecl.srcPackage.fullPackageName == fullPackageName) {
            return Some(packageDecl)
        }
    }
    return None
}

private func stdLibFieldLookup(ctx: ASTContext, node: Node, fieldName: String): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    var packageName: Option<String> = None
    if (node.TestAttr(Attribute.IN_CORE)) {
        packageName = Some(LOOKUP_CORE_PACKAGE_NAME)
    } else if (node.TestAttr(Attribute.IN_MACRO)) {
        packageName = Some(LOOKUP_AST_PACKAGE_NAME)
    }
    if (let Some(fullPackageName) <- packageName) {
        if (let Some(pkg) <- lookupKnownPackage(ctx, fullPackageName)) {
            if (let Some(target) <- lookupPackageMember(pkg, fieldName)) {
                results.add(target)
            }
        }
        if (results.isEmpty()) {
            if (let Some(packageMap) <- ctx.resolvedPackageMemberDeclsMap.get(fullPackageName)) {
                if (let Some(decls) <- packageMap.get(fieldName)) {
                    for (decl in decls) {
                        addDeclUnique(results, decl)
                    }
                }
            }
        }
    }
    return results
}

private func lastPackageName(fullPackageName: String): String {
    let parts = ModulesSplitQualifiedName(fullPackageName, splitDc: true)
    if (parts.isEmpty()) {
        return fullPackageName
    }
    return parts[parts.size - 1]
}

private func importedPackageMemberVisible(sourcePkgName: String, targetPkgName: String, importSpec: ImportSpec,
    decl: Decl): Bool {
    let relation = ModulesGetPackageRelation(sourcePkgName, targetPkgName)
    return importAllowsAccess(importSpec, decl) && nodeVisibleInRelation(decl, relation)
}

private func collectImportedDeclsFromSpec(ctx: ASTContext, sourcePkgName: String, importSpec: ImportSpec,
    name: String, results: ArrayList<Decl>): Unit {
    if (importSpec.IsImportMulti()) {
        return
    }
    if (importSpec.IsImportAll()) {
        let fullPackageName = importSpec.content.GetImportedPackageName()
        if (let Some(pkg) <- lookupKnownPackage(ctx, fullPackageName)) {
            for (decl in lookupPackageMembers(pkg, name)) {
                if (importedPackageMemberVisible(sourcePkgName, fullPackageName, importSpec, decl)) {
                    addDeclUnique(results, decl)
                }
            }
        }
        return
    }
    let importedPackageName = importSpec.content.GetImportedPackageName()
    if (let Some(packageDecl) <- lookupKnownPackageDecl(ctx, importedPackageName)) {
        let importedName = if (importSpec.IsImportAlias()) {
            importSpec.content.aliasName.Val()
        } else {
            lastPackageName(importedPackageName)
        }
        if (name == importedName) {
            addDeclUnique(results, packageDecl)
        }
        return
    }
    let memberPackageName = importSpec.content.GetPrefixPath()
    if (memberPackageName.isEmpty()) {
        return
    }
    let importedMemberName = if (importSpec.IsImportAlias()) {
        importSpec.content.aliasName.Val()
    } else {
        importSpec.content.identifier.Val()
    }
    if (name != importedMemberName) {
        return
    }
    if (let Some(pkg) <- lookupKnownPackage(ctx, memberPackageName)) {
        for (decl in lookupPackageMembers(pkg, importSpec.content.identifier.Val())) {
            if (importedPackageMemberVisible(sourcePkgName, memberPackageName, importSpec, decl)) {
                addDeclUnique(results, decl)
            }
        }
    }
}

private func lookupSourcePackageName(ctx: ASTContext, node: Node): String {
    if (!ctx.fullPackageName.isEmpty()) {
        return ctx.fullPackageName
    }
    if (let Some(file) <- node.curFile) {
        if (let Some(pkg) <- file.curPackage) {
            return pkg.fullPackageName
        }
    }
    return ""
}

private func collectImportedDeclsByName(ctx: ASTContext, node: Node, name: String): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    let sourcePkgName = lookupSourcePackageName(ctx, node)
    if (let Some(pkg) <- ctx.curPackage) {
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsReExport()) {
                    collectImportedDeclsFromSpec(ctx, sourcePkgName, importSpec, name, results)
                }
            }
        }
    }
    if (let Some(file) <- node.curFile) {
        for (importSpec in file.imports) {
            if (!importSpec.IsReExport()) {
                collectImportedDeclsFromSpec(ctx, sourcePkgName, importSpec, name, results)
            }
        }
    }
    return results
}

private func collectResolvedImportedDeclsByName(ctx: ASTContext, node: Node, name: String): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    let keys = HashSet<String>()
    if (let Some(file) <- node.curFile) {
        if (let Some(fileMap) <- ctx.resolvedImportedDeclsMap.get(file.fileHash)) {
            if (let Some(decls) <- fileMap.get(name)) {
                for (decl in decls) {
                    addDeclUnique(results, keys, decl)
                }
            }
        }
    }
    return results
}

public func FieldLookup(typeManager: TypeManager, decl: Option<Decl>, fieldName: String,
    info!: LookupInfo = LookupInfo()): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    if (let Some(target) <- decl) {
        let actual = if (let Some(specific) <- target.specificImplementation) { specific } else { target }
        if (let Some(classDecl) <- (actual as ClassDecl)) {
            fieldLookupClass(typeManager, classDecl, fieldName, results, info)
            return results
        }
        if (let Some(interfaceDecl) <- (actual as InterfaceDecl)) {
            if (let Some(interfaceDeclTy) <- interfaceDecl.GetTy()) {
                if (let Some(interfaceTy) <- (interfaceDeclTy as InterfaceTy)) {
                    fieldLookupInterfaceTy(typeManager, interfaceTy, fieldName, results, info)
                }
            }
            return results
        }
        if (let Some(enumDecl) <- (actual as EnumDecl)) {
            return fieldLookupEnum(typeManager, enumDecl, fieldName, info)
        }
        if (let Some(structDecl) <- (actual as StructDecl)) {
            return fieldLookupStruct(typeManager, structDecl, fieldName, info)
        }
        if (let Some(packageDecl) <- (actual as PackageDecl)) {
            return fieldLookupPackage(packageDecl, fieldName)
        }
    }
    return results
}

private func findRealResult(ctx: ASTContext, node: Node, isSetter: Bool, results: ArrayList<Decl>,
    resultDecls: ArrayList<Decl>, isInDeclBody: Bool): Bool {
    let wasAllFunction = !results.isEmpty() && isAllFuncDecl(results)
    if (!results.isEmpty() && !wasAllFunction) {
        return true
    }
    for (targetDecl in sortedDecls(resultDecls)) {
        let initFuncParam = targetDecl.begin == INVALID_POSITION && node.begin == INVALID_POSITION
        var initAssignLHS = node.begin == INVALID_POSITION && node.scopeLevel > targetDecl.scopeLevel
        if (let Some(varDecl) <- (targetDecl as VarDecl)) {
            initAssignLHS = initAssignLHS || varDecl.isResourceVar
        }
        let orderRelated = !initFuncParam && !initAssignLHS && !(targetDecl.scopeLevel == 0u32 || isInDeclBody)
        if ((orderRelated && isDefinedAfter(targetDecl, node)) || ignoredMember(targetDecl)) {
            continue
        }
        if (wasAllFunction && !targetDecl.IsFunc()) {
            return true
        }
        if (let Some(typeAlias) <- (targetDecl as TypeAliasDecl)) {
            if (isNodeInTypeAliasDecl(node, typeAlias)) {
                continue
            }
        }
        if (let Some(propDecl) <- (targetDecl as PropDecl)) {
            if (!propAccessibleForAccess(propDecl, isSetter)) {
                continue
            }
        }
        if (let Some(varDecl) <- (targetDecl as VarDecl)) {
            if (targetDecl.astKind != ASTKind.PROP_DECL &&
                (isNodeInVarDecl(ctx, node, varDecl) || isNodeInDestructed(node, varDecl))) {
                continue
            }
            addDeclUnique(results, varDecl)
            if (let Some(refExpr) <- (node as RefExpr)) {
                if (let Some(_) <- refExpr.callOrPattern) {
                    continue
                }
            }
            return true
        }
        addDeclUnique(results, targetDecl)
    }
    return false
}

private func processStructDeclBody(typeManager: TypeManager, ctx: ASTContext, name: String, scopeName: String,
    node: Node, results: ArrayList<Decl>): Unit {
    let parentScopeName = GetParentScopeName(scopeName)
    let parentScopeGateName = GetScopeGateName(parentScopeName)
    if (let Some(parentScopeGateSym) <- GetScopeGate(ctx, parentScopeGateName)) {
        if (let Some(parentNode) <- parentScopeGateSym.node) {
            if (let Some(currentDecl) <- (parentNode as Decl)) {
                let currentTy = currentDecl.GetTy()
                let info = LookupInfo(baseTy: currentTy, file: node.curFile,
                    lookupExtend: currentDecl.astKind == ASTKind.EXTEND_DECL)
                let fields = if (let Some(typeDecl) <- Ty.GetDeclPtrOfTy(currentTy)) {
                    FieldLookup(typeManager, Some(typeDecl), name, info: info)
                } else if (let Some(ty) <- currentTy) {
                    let extendResults = ArrayList<Decl>()
                    fieldLookupExtend(typeManager, ty, name, extendResults, info)
                    extendResults
                } else {
                    ArrayList<Decl>()
                }
                for (field in fields) {
                    if (let Some(varDecl) <- (field as VarDecl)) {
                        if (field.astKind != ASTKind.PROP_DECL && isNodeInVarDecl(ctx, node, varDecl)) {
                            continue
                        }
                    }
                    if (IsLegalAccess(node, field)) {
                        addDeclUnique(results, field)
                    }
                }
            }
        }
    }
}

private func lookupImpl(typeManager: TypeManager, ctx: ASTContext, name: String, startScopeName: String,
    node: Node, onlyLookUpTopLevel: Bool, isSetter: Bool, results: ArrayList<Decl>): Bool {
    var scopeName = startScopeName
    while (!scopeName.isEmpty()) {
        let targetDecls = ArrayList<Decl>()
        for (decl in ctx.GetDeclsByName(Names(name, scopeName))) {
            if ((onlyLookUpTopLevel || node.astKind == ASTKind.REF_TYPE) && !decl.IsTypeDecl()) {
                continue
            }
            if (isTargetVisibleToNode(decl, node)) {
                addDeclUnique(targetDecls, decl)
            }
        }
        let scopeGateName = GetScopeGateName(scopeName)
        let scopeGateSym = GetScopeGate(ctx, scopeGateName)
        var isInDeclBody = false
        if (let Some(sym) <- scopeGateSym) {
            if (let Some(symNode) <- sym.node) {
                isInDeclBody = symNode.IsNominalDeclBody() || symNode.TestAttr(Attribute.IN_EXTEND) ||
                    symNode.astKind == ASTKind.ENUM_DECL
            }
        }
        if (findRealResult(ctx, node, isSetter, results, targetDecls, isInDeclBody)) {
            return true
        }
        if (let Some(sym) <- scopeGateSym) {
            if (let Some(symNode) <- sym.node) {
                if (symNode.IsNominalDeclBody() && !onlyLookUpTopLevel) {
                    processStructDeclBody(typeManager, ctx, name, scopeName, node, results)
                }
            }
        }
        scopeName = GetParentScopeName(scopeName)
        if (!results.isEmpty()) {
            if (let Some(_) <- (results[0] as VarDecl)) {
                return true
            }
        }
    }
    return false
}

public func Lookup(typeManager: TypeManager, ctx: ASTContext, name: String, scopeName: String, node: Node,
    isSetter!: Bool = false): ArrayList<Decl> {
    return lookupCommon(typeManager, ctx, name, scopeName, node, false, isSetter)
}

public func LookupTopLevel(typeManager: TypeManager, ctx: ASTContext, name: String, scopeName: String, node: Node,
    isSetter!: Bool = false): ArrayList<Decl> {
    return lookupCommon(typeManager, ctx, name, scopeName, node, true, isSetter)
}

private func lookupCommon(typeManager: TypeManager, ctx: ASTContext, name: String, scopeName: String, node: Node,
    onlyLookUpTopLevel: Bool, isSetter: Bool): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    for (decl in stdLibFieldLookup(ctx, node, name)) {
        results.add(decl)
    }
    if (!results.isEmpty() || name == INVALID_IDENTIFIER || scopeName.isEmpty()) {
        return results
    }
    if (lookupImpl(typeManager, ctx, name, scopeName, node, onlyLookUpTopLevel, isSetter, results)) {
        return results
    }
    if (!results.isEmpty() && !isAllFuncDecl(results)) {
        return results
    }
    for (decl in collectResolvedImportedDeclsByName(ctx, node, name)) {
        addDeclUnique(results, decl)
    }
    if (!results.isEmpty()) {
        return results
    }
    for (decl in collectImportedDeclsByName(ctx, node, name)) {
        addDeclUnique(results, decl)
    }
    return results
}

public func ExtendFieldLookup(typeManager: TypeManager, file: File, ty: Option<Ty>,
    fieldName: String): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    if (let Some(value) <- ty) {
        if (Ty.IsTyCorrect(value)) {
            fieldLookupExtend(typeManager, value, fieldName, results, LookupInfo(baseTy: value, file: file))
        }
    }
    return results
}

public func SelfhostPortStatus_LookUpImpl(): Bool {
    return true
}
