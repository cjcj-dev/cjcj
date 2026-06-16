package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*

private class GenericInstantiationRecord {
    public var genericDecl: Decl
    public var instantiatedDecl: Decl
    public var subst: TypeSubst

    public init(genericDecl: Decl, instantiatedDecl: Decl, subst: TypeSubst) {
        this.genericDecl = genericDecl
        this.instantiatedDecl = instantiatedDecl
        this.subst = subst
    }
}

private func containsDecl(values: ArrayList<Decl>, decl: Decl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func containsExtendDecl(values: ArrayList<ExtendDecl>, decl: ExtendDecl): Bool {
    for (value in values) {
        if (SameDecl(value, decl)) {
            return true
        }
    }
    return false
}

private func sameSubst(lhs: TypeSubst, rhs: TypeSubst): Bool {
    if (lhs.entries.size != rhs.entries.size) {
        return false
    }
    for (entry in lhs.entries) {
        if (let Some(value) <- rhs.Get(entry.tyVar)) {
            if (!SameTy(entry.ty, value)) {
                return false
            }
        } else {
            return false
        }
    }
    return true
}

private func copyTypeArgs(ty: Option<Ty>): ArrayList<Ty> {
    let out = ArrayList<Ty>()
    if (let Some(value) <- ty) {
        for (arg in value.typeArgs) {
            out.add(arg)
        }
    }
    return out
}

private func getGenericParamTys(decl: Decl): ArrayList<GenericsTy> {
    let out = ArrayList<GenericsTy>()
    if (let Some(generic) <- decl.GetGeneric()) {
        for (param in generic.typeParameters) {
            if (let Some(paramTy) <- param.GetTy()) {
                if (let Some(genericTy) <- (paramTy as GenericsTy)) {
                    out.add(genericTy)
                }
            }
        }
    }
    return out
}

private func typeMappingFromArgs(genericParams: ArrayList<GenericsTy>, typeArgs: ArrayList<Ty>): TypeSubst {
    let out = TypeSubst()
    if (genericParams.size != typeArgs.size) {
        return out
    }
    for (idx in 0..genericParams.size) {
        out.Put(genericParams[idx], typeArgs[idx])
    }
    return out
}

private func buildTypeMappingFromDecl(genericDecl: Decl, instantiatedDecl: Decl): TypeSubst {
    let byTy = GenerateTypeMappingByTy(GetDeclTy(genericDecl), GetDeclTy(instantiatedDecl))
    if (!byTy.IsEmpty()) {
        return byTy
    }
    let genericParams = getGenericParamTys(genericDecl)
    let instantiatedArgs = GetDeclTypeParams(instantiatedDecl)
    if (!instantiatedArgs.isEmpty()) {
        return typeMappingFromArgs(genericParams, instantiatedArgs)
    }
    return typeMappingFromArgs(genericParams, copyTypeArgs(instantiatedDecl.GetTy()))
}

private func markNoReflectInfo(decl: Decl): Unit {
    decl.EnableAttr(Attribute.NO_REFLECT_INFO)
    for (member in decl.GetMemberDecls()) {
        member.EnableAttr(Attribute.NO_REFLECT_INFO)
        if (let Some(propDecl) <- (member as PropDecl)) {
            for (getter in propDecl.getters) {
                getter.EnableAttr(Attribute.NO_REFLECT_INFO)
            }
            for (setter in propDecl.setters) {
                setter.EnableAttr(Attribute.NO_REFLECT_INFO)
            }
        }
    }
}

private func applyPackageAttrs(decl: Decl, pkg: Package): Unit {
    decl.fullPackageName = pkg.fullPackageName
    decl.moduleName = pkg.fullPackageName
    decl.toBeCompiled = true
    decl.DisableAttr(Attribute.IMPORTED)
}

private func updateClonedNode(genericNode: Node, clonedNode: Node, typeManager: TypeManager, typeMapping: TypeSubst,
    pkg: Package): Unit {
    if (let Some(sourceTy) <- genericNode.GetTy()) {
        clonedNode.SetTy(typeManager.GetInstantiatedTy(sourceTy, typeMapping))
    }
    if (let Some(refExpr) <- (clonedNode as NameReferenceExpr)) {
        if (let Some(parentTy) <- refExpr.matchedParentTy) {
            refExpr.matchedParentTy = typeManager.GetInstantiatedTy(parentTy, typeMapping)
        }
        var idx: Int64 = 0
        while (idx < refExpr.instTys.size) {
            refExpr.instTys[idx] = typeManager.GetInstantiatedTy(refExpr.instTys[idx], typeMapping)
            idx++
        }
    }
    if (let Some(clonedDecl) <- (clonedNode as Decl)) {
        applyPackageAttrs(clonedDecl, pkg)
    }
}

private func appendGenericInstantiation(pkg: Package, decl: Decl): Unit {
    if (!containsDecl(pkg.genericInstantiatedDecls, decl)) {
        pkg.genericInstantiatedDecls.add(decl)
    }
}

private func addDeclExtendUnique(typeManager: TypeManager, decl: InheritableDecl, extendDecl: ExtendDecl): Unit {
    for (entry in typeManager.declToExtendMap) {
        if (SameDecl(entry.decl, decl)) {
            if (!containsExtendDecl(entry.extends, extendDecl)) {
                entry.extends.add(extendDecl)
            }
            return
        }
    }
    let entry = DeclExtendsEntry(decl)
    entry.extends.add(extendDecl)
    typeManager.declToExtendMap.add(entry)
}

private func updateInstantiatedExtendMap(typeManager: TypeManager, pkg: Package): Unit {
    for (decl in pkg.genericInstantiatedDecls) {
        if (let Some(extendDecl) <- (decl as ExtendDecl)) {
            if (let Some(extendTy) <- decl.GetTy()) {
                if (extendTy.IsBuiltin()) {
                    typeManager.UpdateBuiltInTyExtendDecl(extendTy, extendDecl)
                } else if (let Some(extendedDecl) <- Ty.GetInheritableDeclPtrOfTy(extendTy)) {
                    addDeclExtendUnique(typeManager, extendedDecl, extendDecl)
                }
            }
        }
    }
}

private func updateInstantiatedDeclsLinkage(pkg: Package): Unit {
    for (decl in pkg.genericInstantiatedDecls) {
        let walker = Walker(decl, visitPre: { node: Node =>
            if (let Some(funcDecl) <- (node as FuncDecl)) {
                funcDecl.linkage = Linkage.INTERNAL
            }
            VisitAction.WALK_CHILDREN
        })
        let _ = walker.Walk()
    }
}

private func ignoredInstantiationKind(decl: Decl): Bool {
    return decl.astKind == ASTKind.TYPE_ALIAS_DECL || decl.astKind == ASTKind.BUILTIN_DECL ||
        decl.astKind == ASTKind.GENERIC_PARAM_DECL || decl.astKind == ASTKind.PACKAGE_DECL
}

private func addTyUnique(values: ArrayList<Ty>, ty: Ty): Bool {
    for (value in values) {
        if (SameTy(value, ty)) {
            return false
        }
    }
    values.add(ty)
    return true
}

public class GenericInstantiationManagerImpl {
    private var ci: CompilerInstance
    private var context: GenericInstantiationContext
    private let instantiations: ArrayList<GenericInstantiationRecord> = ArrayList<GenericInstantiationRecord>()

    public init(ci: CompilerInstance) {
        this.ci = ci
        context = GenericInstantiationContext(ci.typeManager)
        SetOptLevel(ci.globalOptions)
    }

    public func GenericInstantiatePackage(pkg: Package, resetGlobalState!: Bool = true): Unit {
        if (resetGlobalState) {
            ResetGenericInstantiationStage()
        }
        InstantiatedExtendRecorder(ci.typeManager).Record(pkg)
        for (file in pkg.files) {
            for (decl in file.decls) {
                collectIdentityInstantiation(decl)
            }
        }
        for (decl in pkg.genericInstantiatedDecls) {
            collectExistingInstantiation(decl)
        }
        InstantiateReferencedGenerics(pkg)
        updateInstantiatedExtendMap(ci.typeManager, pkg)
        updateInstantiatedDeclsLinkage(pkg)
    }

    public func GetInstantiatedDeclWithGenericInfo(genericInfo: GenericInfo, pkg: Package): Option<Decl> {
        if (let Some(cached) <- FindInCache(genericInfo, pkg)) {
            return cached
        }
        if (let Some(genericDecl) <- genericInfo.decl) {
            if (genericInfo.gTyToTyMap.IsEmpty()) {
                collectIdentityInstantiation(genericDecl)
                return genericDecl
            }
            let instantiatedDecl = InstantiateGenericDecl(genericDecl, genericInfo.gTyToTyMap, pkg)
            addInstantiationRecord(genericDecl, instantiatedDecl, genericInfo.gTyToTyMap)
            if (!SameDecl(genericDecl, instantiatedDecl)) {
                appendGenericInstantiation(pkg, instantiatedDecl)
                InstantiatedExtendRecorder(ci.typeManager).Record(instantiatedDecl)
                InstantiateReferencedGenericsInNode(instantiatedDecl, pkg)
                updateInstantiatedExtendMap(ci.typeManager, pkg)
                updateInstantiatedDeclsLinkage(pkg)
            }
            return instantiatedDecl
        }
        return None
    }

    public func GetInstantiatedDecls(genericDecl: Decl): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        for (entry in instantiations) {
            if (SameDecl(entry.genericDecl, genericDecl)) {
                out.add(entry.instantiatedDecl)
            }
        }
        return out
    }

    public func ResetGenericInstantiationStage(): Unit {
        instantiations.clear()
        context.Clear()
        PartialInstantiation.ResetGlobalMap()
    }

    public func GetAllGenericToInsDecls(): ArrayList<(Decl, ArrayList<Decl>)> {
        let out = ArrayList<(Decl, ArrayList<Decl>)>()
        for (entry in instantiations) {
            var found = false
            var idx: Int64 = 0
            while (idx < out.size) {
                let (decl, values) = out[idx]
                if (SameDecl(decl, entry.genericDecl)) {
                    values.add(entry.instantiatedDecl)
                    found = true
                    break
                }
                idx++
            }
            if (!found) {
                let values = ArrayList<Decl>()
                values.add(entry.instantiatedDecl)
                out.add((entry.genericDecl, values))
            }
        }
        return out
    }

    public func ConstructGenericInfo(decl: Decl, instTys: ArrayList<Ty>): GenericInfo {
        return context.ConstructGenericInfo(decl, instTys)
    }

    public func FindInCache(info: GenericInfo): Option<Decl> {
        return FindInCache(info, None)
    }

    private func FindInCache(info: GenericInfo, pkg: Package): Option<Decl> {
        return FindInCache(info, Some(pkg))
    }

    private func FindInCache(info: GenericInfo, pkg: Option<Package>): Option<Decl> {
        if (let Some(genericDecl) <- info.decl) {
            for (entry in instantiations) {
                if (SameDecl(entry.genericDecl, genericDecl) && sameSubst(entry.subst, info.gTyToTyMap)) {
                    if (let Some(currentPkg) <- pkg) {
                        if (entry.instantiatedDecl.fullPackageName == currentPkg.fullPackageName) {
                            return entry.instantiatedDecl
                        }
                    } else {
                        return entry.instantiatedDecl
                    }
                }
            }
        }
        return None
    }

    public func InstantiateGenericDecl(decl: Decl, typeMapping: TypeSubst, pkg: Package): Decl {
        if (typeMapping.IsEmpty()) {
            collectIdentityInstantiation(decl)
            return decl
        }
        let cloned = PartialInstantiation.Instantiate(decl, { source: Node, target: Node =>
            updateClonedNode(source, target, ci.typeManager, typeMapping, pkg)
        })
        if (let Some(clonedDecl) <- (cloned as Decl)) {
            clonedDecl.EnableAttr(Attribute.GENERIC_INSTANTIATED)
            clonedDecl.EnableAttr(Attribute.NO_REFLECT_INFO)
            clonedDecl.DisableAttr(Attribute.GENERIC)
            clonedDecl.DisableAttr(Attribute.IMPORTED)
            clonedDecl.genericDecl = decl
            markNoReflectInfo(clonedDecl)
            PartialInstantiation.RegisterInstantiation(decl, clonedDecl)
            return clonedDecl
        }
        return decl
    }

    private func addInstantiationRecord(genericDecl: Decl, instantiatedDecl: Decl, subst: TypeSubst): Unit {
        if (!hasInstantiation(genericDecl, instantiatedDecl, subst)) {
            instantiations.add(GenericInstantiationRecord(genericDecl, instantiatedDecl, subst.Clone()))
        }
    }

    private func collectIdentityInstantiation(decl: Decl): Unit {
        if (let Some(_) <- decl.GetGeneric()) {
            addInstantiationRecord(decl, decl, TypeSubst())
            PartialInstantiation.RegisterInstantiation(decl, decl)
        }
        for (member in decl.GetMemberDecls()) {
            collectIdentityInstantiation(member)
        }
    }

    private func collectExistingInstantiation(decl: Decl): Unit {
        if (let Some(genericDecl) <- decl.genericDecl) {
            addInstantiationRecord(genericDecl, decl, buildTypeMappingFromDecl(genericDecl, decl))
            PartialInstantiation.RegisterInstantiation(genericDecl, decl)
        } else {
            collectIdentityInstantiation(decl)
        }
        for (member in decl.GetMemberDecls()) {
            collectExistingInstantiation(member)
        }
    }

    private func InstantiateReferencedGenerics(pkg: Package): Unit {
        for (file in pkg.files) {
            InstantiateReferencedGenericsInNode(file, pkg)
        }
        for (decl in pkg.srcImportedNonGenericDecls) {
            InstantiateReferencedGenericsInNode(decl, pkg)
        }
    }

    private func InstantiateReferencedGenericsInNode(root: Node, pkg: Package): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            CheckNodeInstantiation(node, pkg)
        })
        let _ = walker.Walk()
    }

    private func CheckNodeInstantiation(node: Node, pkg: Package): VisitAction {
        if (ShouldSkipInstantiationNode(node)) {
            return VisitAction.SKIP_CHILDREN
        }
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                InstantiateReferencedGenericsInNode(desugar, pkg)
                return VisitAction.SKIP_CHILDREN
            }
        }
        InstantiateGenericTysForNode(node, pkg)
        if (let Some(refExpr) <- (node as RefExpr)) {
            GenericRefExprInstantiate(refExpr, pkg)
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            GenericMemberAccessInstantiate(memberAccess, pkg)
        } else if (let Some(typeNode) <- (node as Type)) {
            GenericTypeInstantiate(typeNode, pkg)
        } else if (let Some(arrayExpr) <- (node as ArrayExpr)) {
            GenericArrayExprInstantiate(arrayExpr, pkg)
        } else if (let Some(arrayLit) <- (node as ArrayLit)) {
            GenericArrayLitInstantiate(arrayLit, pkg)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func ShouldSkipInstantiationNode(node: Node): Bool {
        if (node.astKind == ASTKind.GENERIC_PARAM_DECL || node.astKind == ASTKind.GENERIC_CONSTRAINT ||
            node.astKind == ASTKind.PRIMARY_CTOR_DECL || node.astKind == ASTKind.MODIFIER) {
            return true
        }
        if (let Some(decl) <- (node as Decl)) {
            if (decl.TestAttr(Attribute.GENERIC) && !decl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                return true
            }
        }
        return false
    }

    private func InstantiateGenericTysForNode(node: Node, pkg: Package): Unit {
        if (let Some(ty) <- node.GetTy()) {
            if (Ty.IsTyCorrect(ty) && !ty.HasIntersectionTy()) {
                let visited = ArrayList<Ty>()
                InstantiateGenericTy(ty, pkg, visited)
            }
        }
    }

    private func InstantiateGenericTy(ty: Ty, pkg: Package, visited: ArrayList<Ty>): Unit {
        if (!Ty.IsTyCorrect(ty) || ty.HasGeneric() || !addTyUnique(visited, ty)) {
            return
        }
        for (arg in ty.typeArgs) {
            InstantiateGenericTy(arg, pkg, visited)
        }
        if (let Some(target) <- Ty.GetDeclPtrOfTy(ty)) {
            InstantiateGenericDeclWithInstTys(target, copyTypeArgs(Some(ty)), pkg)
        }
        for (extendDecl in ci.typeManager.GetTyUsedExtends(ty)) {
            if (let Some(extendTy) <- GetDeclTy(extendDecl)) {
                if (!extendTy.HasGeneric() && ci.typeManager.CheckExtendWithConstraint(ty, Some(extendDecl))) {
                    InstantiateGenericDeclWithInstTys(extendDecl, copyTypeArgs(Some(extendTy)), pkg)
                }
            }
        }
    }

    private func GenericRefExprInstantiate(refExpr: RefExpr, pkg: Package): Unit {
        if (let Some(target) <- refExpr.GetTarget()) {
            if (target.astKind == ASTKind.GENERIC_PARAM_DECL || target.astKind == ASTKind.PACKAGE_DECL) {
                return
            }
            var targetDecl = target
            let instTys = ArrayList<Ty>()
            for (ty in refExpr.instTys) {
                instTys.add(ty)
            }
            if (refExpr.isThis || refExpr.isSuper) {
                instTys.clear()
                if (let Some(thisTy) <- refExpr.GetTy()) {
                    for (arg in thisTy.typeArgs) {
                        instTys.add(arg)
                    }
                }
            }
            if (IsClassOrEnumConstructor(targetDecl)) {
                if (let Some(outer) <- targetDecl.outerDecl) {
                    targetDecl = outer
                    instTys.clear()
                    if (let Some(refTy) <- refExpr.GetTy()) {
                        let baseTy = if (let Some(funcTy) <- (refTy as FuncTy)) { funcTy.retTy } else { refTy }
                        for (arg in baseTy.typeArgs) {
                            instTys.add(arg)
                        }
                    }
                }
            }
            InstantiateGenericDeclWithInstTys(targetDecl, instTys, pkg)
        }
    }

    private func GenericMemberAccessInstantiate(memberAccess: MemberAccess, pkg: Package): Unit {
        if (let Some(target) <- memberAccess.GetTarget()) {
            if (target.astKind == ASTKind.PACKAGE_DECL) {
                return
            }
            var targetDecl = target
            let instTys = ArrayList<Ty>()
            for (ty in memberAccess.instTys) {
                instTys.add(ty)
            }
            if (IsClassOrEnumConstructor(targetDecl)) {
                if (let Some(outer) <- targetDecl.outerDecl) {
                    targetDecl = outer
                    instTys.clear()
                    if (let Some(memberTy) <- memberAccess.GetTy()) {
                        let baseTy = if (let Some(funcTy) <- (memberTy as FuncTy)) { funcTy.retTy } else { memberTy }
                        for (arg in baseTy.typeArgs) {
                            instTys.add(arg)
                        }
                    }
                }
            } else if (let Some(outer) <- targetDecl.outerDecl) {
                if (outer.IsNominalDecl() && outer.TestAttr(Attribute.GENERIC)) {
                    if (let Some(baseExpr) <- memberAccess.baseExpr) {
                        if (let Some(baseTy) <- baseExpr.GetTy()) {
                            let promotedTys = Promotion(ci.typeManager).Promote(baseTy, GetDeclTy(outer) ?? baseTy)
                            if (!promotedTys.IsEmpty()) {
                                InstantiateGenericDeclWithInstTys(outer, copyTypeArgs(Some(promotedTys.values[0])), pkg)
                            }
                        }
                    }
                }
            }
            InstantiateGenericDeclWithInstTys(targetDecl, instTys, pkg)
        }
    }

    private func GenericTypeInstantiate(typeNode: Type, pkg: Package): Unit {
        if (!Ty.IsTyCorrect(typeNode.GetTy())) {
            return
        }
        if (let Some(ty) <- typeNode.GetTy()) {
            if (ty.HasGeneric() || ty.HasIntersectionTy()) {
                return
            }
            if (let Some(target) <- Ty.GetDeclPtrOfTy(ty)) {
                InstantiateGenericDeclWithInstTys(target, copyTypeArgs(Some(ty)), pkg)
            }
        }
    }

    private func GenericArrayExprInstantiate(arrayExpr: ArrayExpr, pkg: Package): Unit {
        if (let Some(initFunc) <- arrayExpr.initFunc) {
            if (let Some(arrayTy) <- arrayExpr.GetTy()) {
                InstantiateGenericDeclWithInstTys(initFunc, copyTypeArgs(Some(arrayTy)), pkg)
            }
        }
    }

    private func GenericArrayLitInstantiate(arrayLit: ArrayLit, pkg: Package): Unit {
        if (let Some(initFunc) <- arrayLit.initFunc) {
            if (let Some(arrayTy) <- arrayLit.GetTy()) {
                InstantiateGenericDeclWithInstTys(initFunc, copyTypeArgs(Some(arrayTy)), pkg)
            }
        } else if (let Some(arrayTy) <- arrayLit.GetTy()) {
            if (let Some(target) <- Ty.GetDeclPtrOfTy(arrayTy)) {
                InstantiateGenericDeclWithInstTys(target, copyTypeArgs(Some(arrayTy)), pkg)
            }
        }
    }

    private func InstantiateGenericDeclWithInstTys(decl: Decl, instTys: ArrayList<Ty>, pkg: Package): Unit {
        let generalDecl = PartialInstantiation.GetGeneralDecl(decl)
        if (ignoredInstantiationKind(generalDecl) || !RequireInstantiation(generalDecl)) {
            return
        }
        if ((let None <- generalDecl.GetGeneric()) || instTys.isEmpty() || Ty.ExistGeneric(instTys)) {
            return
        }
        let genericInfo = ConstructGenericInfo(generalDecl, instTys)
        if (!genericInfo.gTyToTyMap.IsEmpty()) {
            let _ = GetInstantiatedDeclWithGenericInfo(genericInfo, pkg)
        }
    }

    private func hasInstantiation(genericDecl: Decl, instantiatedDecl: Decl, subst: TypeSubst): Bool {
        for (entry in instantiations) {
            if (SameDecl(entry.genericDecl, genericDecl) && SameDecl(entry.instantiatedDecl, instantiatedDecl) &&
                sameSubst(entry.subst, subst)) {
                return true
            }
        }
        return false
    }
}
