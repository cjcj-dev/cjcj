package cjcj::sema

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::modules.GetPackageRelation as ModulesGetPackageRelation
import cjcj::modules.PackageRelation as ModulesPackageRelation
import cjcj::modules.SemaImportManager
import cjcj::modules.SplitQualifiedName as ModulesSplitQualifiedName

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

private class LookUpImpl {
    private let typeManager: TypeManager
    public let importManager: Option<SemaImportManager>
    private let resultsWithInstTyV = ArrayList<(Option<Decl>, Option<InterfaceTy>)>()

    public init(typeManager: TypeManager, importManager!: Option<SemaImportManager> = None) {
        this.typeManager = typeManager
        this.importManager = importManager
    }

    public func InsertResultsWithInstTy(idx: Int64, decl: Decl, interfaceTy: InterfaceTy): Unit {
        while (idx >= resultsWithInstTyV.size) {
            resultsWithInstTyV.add((None, None))
        }
        resultsWithInstTyV[idx] = (Some(decl), Some(interfaceTy))
    }

    public func SwapResultsWithInstTy(oldIdx: Int64, newIdx: Int64, decl: Decl,
        interfaceTy: InterfaceTy): Unit {
        resultsWithInstTyV.remove(at: oldIdx)
        InsertResultsWithInstTy(newIdx, decl, interfaceTy)
    }

    public func ResolveOverrideOrShadow(results: ArrayList<Decl>, decl: Decl, parentTy: InterfaceTy): Unit {
        if (decl.astKind == ASTKind.PROP_DECL) {
            if (!decl.TestAttr(Attribute.ABSTRACT)) {
                var propIdx: Int64 = 0
                while (propIdx < results.size) {
                    if (results[propIdx].TestAttr(Attribute.ABSTRACT)) {
                        results.remove(at: propIdx)
                    } else {
                        propIdx++
                    }
                }
            }
        }
        var idx: Int64 = 0
        while (idx < results.size) {
            let inResult = results[idx]
            if (inResult.astKind != ASTKind.FUNC_DECL && inResult.astKind != ASTKind.PROP_DECL) {
                idx++
                continue
            }
            var inResultOuter = inResult.outerDecl.getOrThrow().GetTy()
            if (resultsWithInstTyV.size > idx && resultsWithInstTyV[idx][1].isSome()) {
                inResultOuter = Some(resultsWithInstTyV[idx][1].getOrThrow())
            } else if (inResult.outerDecl.getOrThrow().astKind == ASTKind.EXTEND_DECL) {
                var isSubtype = false
                if (let Some(outerTy) <- inResultOuter) {
                    isSubtype = typeManager.IsSubtype(outerTy, parentTy)
                }
                if (!isSubtype) {
                    let extendTy = inResult.outerDecl.getOrThrow().GetTy()
                    if (let Some(extendedDecl) <- Ty.GetDeclPtrOfTy(extendTy)) {
                        let mappingExtendWithDecl = GenerateTypeMappingByTy(extendTy, extendedDecl.GetTy())
                        if (let Some(outerTy) <- inResultOuter) {
                            inResultOuter = Some(typeManager.GetInstantiatedTy(outerTy, mappingExtendWithDecl))
                        }
                    }
                }
            }

            if (!typeManager.PairIsOverrideOrImpl(inResult, decl, baseTy: inResultOuter,
                    parentTy: Some(parentTy)) &&
                !typeManager.PairIsOverrideOrImpl(decl, inResult, baseTy: Some(parentTy),
                    parentTy: inResultOuter)) {
                idx++
                continue
            }
            if ((inResultOuter.isSome() && typeManager.IsSubtype(parentTy, inResultOuter.getOrThrow())) ||
                (inResult.TestAttr(Attribute.ABSTRACT) && !decl.TestAttr(Attribute.ABSTRACT))) {
                results.remove(at: idx)
                SwapResultsWithInstTy(idx, results.size, decl, parentTy)
                results.add(decl)
            } else if ((inResultOuter.isSome() &&
                typeManager.IsSubtype(inResultOuter.getOrThrow(), parentTy)) ||
                (decl.TestAttr(Attribute.ABSTRACT) && !inResult.TestAttr(Attribute.ABSTRACT))) {
                // Keep the declaration already in results.
            } else {
                idx++
                continue
            }
            return
        }
        InsertResultsWithInstTy(results.size, decl, parentTy)
        results.add(decl)
    }

    public func FieldLookup(idTy: InterfaceTy, fieldName: String, results: ArrayList<Decl>, info: LookupInfo): Unit {
        let id = (GetSpecificDecl(idTy.declPtr.getOrThrow()) as InterfaceDecl).getOrThrow()
        if (let Some(body) <- id.body) {
            for (decl in body.decls) {
                if (decl.identifier != fieldName) {
                    continue
                }
                if (decl.IsFuncOrProp()) {
                    ResolveOverrideOrShadow(results, decl, idTy)
                } else {
                    InsertResultsWithInstTy(results.size, decl, idTy)
                    results.add(decl)
                }
            }
        } else {
            return
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
                            for (promotedTy in promotedTys.values) {
                                if (let Some(promotedInterfaceTy) <- (promotedTy as InterfaceTy)) {
                                    FieldLookup(promotedInterfaceTy, fieldName, results,
                                        LookupInfo(baseTy: info.baseTy))
                                }
                            }
                        }
                    }
                }
            }
        }
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
        if (value == decl) {
            return
        }
    }
    values.add(decl)
}

private func addDeclUnique(values: ArrayList<Decl>, keys: HashSet<Decl>, decl: Decl): Unit {
    if (keys.contains(decl)) {
        return
    }
    values.add(decl)
    keys.add(decl)
}

private func sortedDecls(decls: ArrayList<Decl>): ArrayList<Decl> {
    let out = ArrayList<Decl>()
    for (decl in decls) {
        out.add(decl)
    }
    if (out.size < 2) {
        return out
    }
    sort(out, by: { left: Decl, right: Decl =>
        if (left.begin < right.begin) {
            Ordering.LT
        } else if (right.begin < left.begin) {
            Ordering.GT
        } else {
            let leftKind = ASTKindIndex(left.astKind)
            let rightKind = ASTKindIndex(right.astKind)
            if (leftKind < rightKind) { Ordering.LT } else if (rightKind < leftKind) { Ordering.GT } else {
                Ordering.EQ
            }
        }
    }, stable: true)
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

private func containsNode(root: Node, needle: Node): Bool {
    let found = LookupBoolBox(false)
    let walker = Walker(root, visitPre: { node: Node =>
        if (node == needle) {
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

private func extendAccessibleForLookup(typeManager: TypeManager, info: LookupInfo, extendDecl: ExtendDecl): Bool {
    if (let Some(file) <- info.file) {
        if (let Some(pkg) <- file.curPackage) {
            if (extendDecl.fullPackageName == pkg.fullPackageName) {
                return true
            }
            let allUpperBoundsImported = extendAllUpperBoundsImported(typeManager, info, extendDecl)
            var hasAnyInterfacesImported = false
            var extendedTypeAccessible = false
            let extendedDecl = Ty.GetInheritableDeclPtrOfTy(extendDecl.GetTy())
            let inSamePackage = if (let Some(realExtendedDecl) <- extendedDecl) {
                extendDecl.fullPackageName == realExtendedDecl.fullPackageName
            } else {
                extendDecl.fullPackageName == "std.core"
            }
            if (!inSamePackage) {
                for (inheritedType in extendDecl.inheritedTypes) {
                    if (typeAccessibleForLookup(typeManager, info, inheritedType)) {
                        hasAnyInterfacesImported = true
                    }
                }
                if (let Some(extendedType) <- extendDecl.extendedType) {
                    extendedTypeAccessible = typeAccessibleForLookup(typeManager, info, extendedType)
                }
            } else {
                hasAnyInterfacesImported = true
                if (let Some(realExtendedDecl) <- extendedDecl) {
                    let relation = ModulesGetPackageRelation(pkg.fullPackageName, realExtendedDecl.fullPackageName)
                    extendedTypeAccessible = nodeVisibleInRelation(realExtendedDecl, relation)
                } else {
                    extendedTypeAccessible = true
                }
            }
            return extendDecl.IsExportedDecl() && allUpperBoundsImported && hasAnyInterfacesImported &&
                extendedTypeAccessible
        }
    }
    return true
}

private func typeAccessibleForLookup(typeManager: TypeManager, info: LookupInfo, typeNode: Type): Bool {
    if (let Some(ty) <- typeNode.GetTy()) {
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
            if (let Some(file) <- info.file) {
                return typeManager.IsDeclAccessible(file, decl)
            }
        }
    }
    return true
}

private func extendAllUpperBoundsImported(typeManager: TypeManager, info: LookupInfo, extendDecl: ExtendDecl): Bool {
    if (let None <- extendDecl.generic) {
        return true
    }
    for (constraint in extendDecl.generic.getOrThrow().genericConstraints) {
        for (upperBound in constraint.upperBounds) {
            if (!typeAccessibleForLookup(typeManager, info, upperBound)) {
                return false
            }
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

private func GetSpecificDecl(decl: Decl): Decl {
    return decl.specificImplementation ?? decl
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

private func FieldLookupExtend(lookUpImpl: LookUpImpl, typeManager: TypeManager, ty: Ty, fieldName: String,
    results: ArrayList<Decl>, info: LookupInfo): Unit {
    let extendDecls = ArrayList<Decl>()
    for (extendDecl in typeManager.GetAllExtendsByTy(ty)) {
        extendDecls.add(extendDecl)
    }
    let orderedExtends = sortedDecls(extendDecls)
    for (decl in orderedExtends) {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            let isAccessible = if (let Some(manager) <- lookUpImpl.importManager) {
                manager.IsExtendAccessible(info.file.getOrThrow(), extendDecl, None)
            } else {
                extendAccessibleForLookup(typeManager, info, extendDecl)
            }
            if (!isAccessible) {
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
            let isAccessible = if (let Some(manager) <- lookUpImpl.importManager) {
                manager.IsExtendAccessible(info.file.getOrThrow(), extendDecl, None)
            } else {
                extendAccessibleForLookup(typeManager, info, extendDecl)
            }
            if (!isAccessible) {
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
                            lookUpImpl.FieldLookup(interfaceTy, fieldName, results, info)
                        }
                    }
                }
            }
        }
    }
}

private func fieldLookupClass(lookUpImpl: LookUpImpl, typeManager: TypeManager, cd: ClassDecl, fieldName: String,
    results: ArrayList<Decl>, info: LookupInfo): Unit {
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
                fieldLookupClass(lookUpImpl, typeManager, superClass, fieldName, results, superInfo)
            } else if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                if (let Some(interfaceTy) <- (inheritedTy as InterfaceTy)) {
                    lookUpImpl.FieldLookup(interfaceTy, fieldName, results, LookupInfo(baseTy: info.baseTy))
                }
            }
        }
    }
    if (info.lookupExtend) {
        if (let Some(ty) <- cd.GetTy()) {
            FieldLookupExtend(lookUpImpl, typeManager, ty, fieldName, results, info)
        }
    }
}

private func fieldLookupEnum(lookUpImpl: LookUpImpl, typeManager: TypeManager, ed: EnumDecl, fieldName: String,
    info: LookupInfo): ArrayList<Decl> {
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
                        lookUpImpl.FieldLookup(interfaceTy, fieldName, results, info)
                    }
                }
            }
        }
    }
    if (info.lookupExtend) {
        if (let Some(ty) <- ed.GetTy()) {
            FieldLookupExtend(lookUpImpl, typeManager, ty, fieldName, results, info)
        }
    }
    return results
}

private func fieldLookupStruct(lookUpImpl: LookUpImpl, typeManager: TypeManager, sd: StructDecl, fieldName: String,
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
                        lookUpImpl.FieldLookup(interfaceTy, fieldName, results, info)
                    }
                }
            }
        }
    }
    if (info.lookupExtend) {
        if (let Some(ty) <- sd.GetTy()) {
            FieldLookupExtend(lookUpImpl, typeManager, ty, fieldName, results, info)
        }
    }
    return results
}

private func fieldLookupPackage(pd: PackageDecl, fieldName: String,
    importManager!: Option<SemaImportManager> = None): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    if (!pd.TestAttr(Attribute.IMPORTED)) {
        return results
    }
    if (let Some(manager) <- importManager) {
        for (decl in manager.GetPackageMembersByName(pd.srcPackage, fieldName)) {
            if (!decl.TestAttr(Attribute.MAIN_ENTRY)) {
                addDeclUnique(results, decl)
            }
        }
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

// Faithful to ImportManager::GetPackageMembersByName -> CjoManager::GetPackageMembers
// (src/Modules/CjoManager.cpp:231,242). The package member view is the re-export-aware
// declMap built in CjoManager::AddPackageDeclMap (which merges the package's transitive
// re-exports). In the selfhost that re-export-aware view for imported packages lives in
// ctx.resolvedPackageMemberDeclsMap; consult it first so that a member re-exported by `pkg`
// (e.g. lex.TokenKind re-exported through ast) is resolvable through an `import pkg.*`.
// Fall back to physically-owned decls for packages that have no resolved member map
// (e.g. the source package currently being compiled).
private func lookupPackageMembers(ctx: ASTContext, pkg: Package, name: String): ArrayList<Decl> {
    if (let Some(packageMap) <- ctx.resolvedPackageMemberDeclsMap.get(pkg.fullPackageName)) {
        if (let Some(decls) <- packageMap.get(name)) {
            let results = ArrayList<Decl>()
            for (decl in decls) {
                addDeclUnique(results, decl)
            }
            if (!results.isEmpty()) {
                return results
            }
        }
    }
    return lookupOwnedPackageMembers(pkg, name)
}

private func lookupOwnedPackageMembers(pkg: Package, name: String): ArrayList<Decl> {
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

private func lookupPackageMember(ctx: ASTContext, pkg: Package, name: String): Option<Decl> {
    let members = lookupPackageMembers(ctx, pkg, name)
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

private func stdLibFieldLookup(ctx: ASTContext, node: Node, fieldName: String,
    importManager!: Option<SemaImportManager> = None): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    if (let Some(manager) <- importManager) {
        var target: Option<Decl> = None
        if (node.TestAttr(Attribute.IN_CORE)) {
            target = manager.GetCoreDecl<Decl>(fieldName)
        } else if (node.TestAttr(Attribute.IN_MACRO)) {
            target = manager.GetAstDecl<Decl>(fieldName)
        }
        if (let Some(decl) <- target) {
            results.add(decl)
        }
        return results
    }
    var packageName: Option<String> = None
    if (node.TestAttr(Attribute.IN_CORE)) {
        packageName = Some(LOOKUP_CORE_PACKAGE_NAME)
    } else if (node.TestAttr(Attribute.IN_MACRO)) {
        packageName = Some(LOOKUP_AST_PACKAGE_NAME)
    }
    if (let Some(fullPackageName) <- packageName) {
        if (let Some(pkg) <- lookupKnownPackage(ctx, fullPackageName)) {
            if (let Some(target) <- lookupPackageMember(ctx, pkg, fieldName)) {
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
            for (decl in lookupPackageMembers(ctx, pkg, name)) {
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
        for (decl in lookupPackageMembers(ctx, pkg, importSpec.content.identifier.Val())) {
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
    let keys = HashSet<Decl>()
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
    info!: LookupInfo = LookupInfo(), importManager!: Option<SemaImportManager> = None): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    let lookUpImpl = LookUpImpl(typeManager, importManager: importManager)
    if (let Some(target) <- decl) {
        let actual = GetSpecificDecl(target)
        if (let Some(classDecl) <- (actual as ClassDecl)) {
            fieldLookupClass(lookUpImpl, typeManager, classDecl, fieldName, results, info)
            return results
        }
        if (let Some(interfaceDecl) <- (actual as InterfaceDecl)) {
            if (let Some(interfaceDeclTy) <- interfaceDecl.GetTy()) {
                if (let Some(interfaceTy) <- (interfaceDeclTy as InterfaceTy)) {
                    lookUpImpl.FieldLookup(interfaceTy, fieldName, results, info)
                }
            }
            return results
        }
        if (let Some(enumDecl) <- (actual as EnumDecl)) {
            return fieldLookupEnum(lookUpImpl, typeManager, enumDecl, fieldName, info)
        }
        if (let Some(structDecl) <- (actual as StructDecl)) {
            return fieldLookupStruct(lookUpImpl, typeManager, structDecl, fieldName, info)
        }
        if (let Some(packageDecl) <- (actual as PackageDecl)) {
            return fieldLookupPackage(packageDecl, fieldName, importManager: importManager)
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
    let resultKeys: Option<HashSet<Decl>> = if (results.size + resultDecls.size > 1) {
        let keys = HashSet<Decl>()
        for (result in results) {
            keys.add(result)
        }
        Some(keys)
    } else {
        None
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
            if (let Some(keys) <- resultKeys) {
                addDeclUnique(results, keys, varDecl)
            } else {
                results.add(varDecl)
            }
            if (let Some(refExpr) <- (node as RefExpr)) {
                if (let Some(_) <- refExpr.callOrPattern) {
                    continue
                }
            }
            return true
        }
        if (let Some(keys) <- resultKeys) {
            addDeclUnique(results, keys, targetDecl)
        } else {
            results.add(targetDecl)
        }
    }
    return false
}

private func processStructDeclBody(typeManager: TypeManager, ctx: ASTContext, name: String, scopeName: String,
    node: Node, results: ArrayList<Decl>, importManager!: Option<SemaImportManager> = None): Unit {
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
                    FieldLookupExtend(LookUpImpl(typeManager), typeManager, ty, name, extendResults, info)
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
                    if (IsTargetMemberVisibleToNode(typeManager, ctx, field, node,
                        importManager: importManager)) {
                        addDeclUnique(results, field)
                    }
                }
            }
        }
    }
}

private func lookupImpl(typeManager: TypeManager, ctx: ASTContext, name: String, startScopeName: String,
    node: Node, onlyLookUpTopLevel: Bool, isSetter: Bool, results: ArrayList<Decl>,
    importManager!: Option<SemaImportManager> = None): Bool {
    var scopeName = startScopeName
    while (!scopeName.isEmpty()) {
        let targetDecls = ArrayList<Decl>()
        let declsByName = ctx.GetDeclsByName(Names(name, scopeName))
        let targetDeclKeys: Option<HashSet<Decl>> =
            if (declsByName.size > 1) { Some(HashSet<Decl>()) } else { None }
        for (decl in declsByName) {
            if (isTargetVisibleToNode(decl, node)) {
                if (let Some(keys) <- targetDeclKeys) {
                    addDeclUnique(targetDecls, keys, decl)
                } else {
                    targetDecls.add(decl)
                }
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
                    processStructDeclBody(typeManager, ctx, name, scopeName, node, results,
                        importManager: importManager)
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
    isSetter!: Bool = false, importManager!: Option<SemaImportManager> = None): ArrayList<Decl> {
    return lookupCommon(typeManager, ctx, name, scopeName, node, false, isSetter, importManager: importManager)
}

public func LookupTopLevel(typeManager: TypeManager, ctx: ASTContext, name: String, scopeName: String, node: Node,
    isSetter!: Bool = false, importManager!: Option<SemaImportManager> = None): ArrayList<Decl> {
    return lookupCommon(typeManager, ctx, name, scopeName, node, true, isSetter, importManager: importManager)
}

private func lookupCommon(typeManager: TypeManager, ctx: ASTContext, name: String, scopeName: String, node: Node,
    onlyLookUpTopLevel: Bool, isSetter: Bool, importManager!: Option<SemaImportManager> = None): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    for (decl in stdLibFieldLookup(ctx, node, name, importManager: importManager)) {
        results.add(decl)
    }
    if (!results.isEmpty() || name == INVALID_IDENTIFIER || scopeName.isEmpty()) {
        return results
    }
    if (lookupImpl(typeManager, ctx, name, scopeName, node, onlyLookUpTopLevel, isSetter, results,
        importManager: importManager)) {
        return results
    }
    if (!results.isEmpty() && !isAllFuncDecl(results)) {
        return results
    }
    if (let Some(manager) <- importManager) {
        if (let Some(file) <- node.curFile) {
            for (decl in manager.GetImportedDeclsByName(file, name)) {
                addDeclUnique(results, decl)
            }
        }
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

public func ExtendFieldLookup(typeManager: TypeManager, file: File, ty: Option<Ty>, fieldName: String,
    importManager!: Option<SemaImportManager> = None): ArrayList<Decl> {
    let results = ArrayList<Decl>()
    if (let Some(value) <- ty) {
        if (Ty.IsTyCorrect(value)) {
            FieldLookupExtend(LookUpImpl(typeManager, importManager: importManager), typeManager, value,
                fieldName, results,
                LookupInfo(baseTy: value, file: file))
        }
    }
    return results
}
