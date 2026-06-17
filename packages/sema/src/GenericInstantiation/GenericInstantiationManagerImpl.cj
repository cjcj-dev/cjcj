package cangjie_compiler::sema.GenericInstantiation

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::sema.*
import cangjie_compiler::sema.Desugar.AfterTypeCheck.IsNeedRuntimeCheck

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

private func buildDefaultParamGenericsTyMap(funcDecl: FuncDecl): TypeSubst {
    let out = TypeSubst()
    if ((let None <- funcDecl.GetGeneric()) || (let None <- funcDecl.funcBody)) {
        return out
    }
    let body = funcDecl.funcBody.getOrThrow()
    if (body.paramLists.isEmpty()) {
        return out
    }
    let ownerGeneric = funcDecl.GetGeneric().getOrThrow()
    let ownerTypeParams = ownerGeneric.typeParameters
    for (param in body.paramLists[0].params) {
        if (let Some(desugarDecl) <- param.desugarDecl) {
            if (let Some(desugarGeneric) <- desugarDecl.GetGeneric()) {
                if (desugarGeneric.typeParameters.size == ownerTypeParams.size) {
                    var idx: Int64 = 0
                    while (idx < ownerTypeParams.size) {
                        if (let Some(desugarParamTy) <- desugarGeneric.typeParameters[idx].GetTy()) {
                            if (let Some(desugarGenTy) <- (desugarParamTy as GenericsTy)) {
                                if (let Some(ownerParamTy) <- ownerTypeParams[idx].GetTy()) {
                                    out.Put(desugarGenTy, ownerParamTy)
                                }
                            }
                        }
                        idx++
                    }
                }
            }
        }
    }
    return out
}

private func buildCloneGenericToGenericMap(decl: Decl): TypeSubst {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        return buildDefaultParamGenericsTyMap(funcDecl)
    }
    return TypeSubst()
}

private func instantiateCloneTy(ty: Ty, typeManager: TypeManager, typeMapping: TypeSubst, g2gTyMap: TypeSubst): Ty {
    if (!g2gTyMap.IsEmpty()) {
        return typeManager.GetInstantiatedTy(typeManager.GetInstantiatedTy(ty, g2gTyMap), typeMapping)
    }
    return typeManager.GetInstantiatedTy(ty, typeMapping)
}

private func disableDefaultParamDesugarGenericAttr(decl: Decl): Unit {
    if (let Some(funcDecl) <- (decl as FuncDecl)) {
        if (let Some(body) <- funcDecl.funcBody) {
            if (!body.paramLists.isEmpty()) {
                for (param in body.paramLists[0].params) {
                    if (let Some(desugarDecl) <- param.desugarDecl) {
                        desugarDecl.DisableAttr(Attribute.GENERIC)
                    }
                }
            }
        }
    }
}

private func updateClonedNode(genericNode: Node, clonedNode: Node, typeManager: TypeManager, typeMapping: TypeSubst,
    g2gTyMap: TypeSubst, pkg: Package): Unit {
    if (let Some(sourceTy) <- genericNode.GetTy()) {
        clonedNode.SetTy(instantiateCloneTy(sourceTy, typeManager, typeMapping, g2gTyMap))
    }
    if (let Some(refExpr) <- (clonedNode as NameReferenceExpr)) {
        if (let Some(parentTy) <- refExpr.matchedParentTy) {
            refExpr.matchedParentTy = instantiateCloneTy(parentTy, typeManager, typeMapping, g2gTyMap)
        }
        var idx: Int64 = 0
        while (idx < refExpr.instTys.size) {
            refExpr.instTys[idx] = instantiateCloneTy(refExpr.instTys[idx], typeManager, typeMapping, g2gTyMap)
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

private func HasJavaTargetAttr(target: Decl): Bool {
    if (let Some(_) <- HasJavaAttr(target)) {
        return true
    }
    return false
}

public class GenericInstantiationManagerImpl {
    private var ci: CompilerInstance
    private var context: GenericInstantiationContext
    private let instantiations: ArrayList<GenericInstantiationRecord> = ArrayList<GenericInstantiationRecord>()
    private let structContext: ArrayList<Decl> = ArrayList<Decl>()

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
        RearrangeReferences(pkg)
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
                RearrangeReferencesInNode(instantiatedDecl, pkg)
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
        structContext.clear()
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
        let g2gTyMap = buildCloneGenericToGenericMap(decl)
        let cloned = PartialInstantiation.Instantiate(decl, { source: Node, target: Node =>
            updateClonedNode(source, target, ci.typeManager, typeMapping, g2gTyMap, pkg)
        })
        if (let Some(clonedDecl) <- (cloned as Decl)) {
            clonedDecl.EnableAttr(Attribute.GENERIC_INSTANTIATED)
            clonedDecl.EnableAttr(Attribute.NO_REFLECT_INFO)
            clonedDecl.DisableAttr(Attribute.GENERIC)
            clonedDecl.DisableAttr(Attribute.IMPORTED)
            clonedDecl.genericDecl = decl
            markNoReflectInfo(clonedDecl)
            disableDefaultParamDesugarGenericAttr(clonedDecl)
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
        }, visitPost: { node: Node =>
            PopStructContext(node)
        })
        let _ = walker.Walk()
    }

    private func CheckNodeInstantiation(node: Node, pkg: Package): VisitAction {
        if (ShouldSkipInstantiationNode(node)) {
            return VisitAction.SKIP_CHILDREN
        }
        PushStructContext(node)
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                InstantiateReferencedGenericsInNode(desugar, pkg)
                return VisitAction.SKIP_CHILDREN
            }
        }
        InstantiateGenericTysForNode(node, pkg)
        if (let Some(refExpr) <- (node as RefExpr)) {
            GenericRefExprInstantiate(refExpr, pkg)
            return VisitAction.SKIP_CHILDREN
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            GenericMemberAccessInstantiate(memberAccess, pkg)
            return VisitAction.SKIP_CHILDREN
        } else if (let Some(typeNode) <- (node as Type)) {
            GenericTypeInstantiate(typeNode, pkg)
            if (typeNode.astKind == ASTKind.REF_TYPE || typeNode.astKind == ASTKind.QUALIFIED_TYPE) {
                return VisitAction.SKIP_CHILDREN
            }
        } else if (let Some(arrayExpr) <- (node as ArrayExpr)) {
            GenericArrayExprInstantiate(arrayExpr, pkg)
        } else if (let Some(arrayLit) <- (node as ArrayLit)) {
            GenericArrayLitInstantiate(arrayLit, pkg)
            return VisitAction.SKIP_CHILDREN
        }
        return VisitAction.WALK_CHILDREN
    }

    private func PushStructContext(node: Node): Unit {
        if (let Some(decl) <- (node as Decl)) {
            if (NeedSwitchContext(decl)) {
                structContext.add(decl)
            }
        }
    }

    private func PopStructContext(node: Node): VisitAction {
        if (let Some(decl) <- (node as Decl)) {
            if (!structContext.isEmpty() && NeedSwitchContext(decl) &&
                SameDecl(structContext[structContext.size - 1], decl)) {
                structContext.remove(at: structContext.size - 1)
            }
        }
        return VisitAction.KEEP_DECISION
    }

    private func GetStructDeclByContext(): Option<Decl> {
        if (structContext.isEmpty()) {
            return None
        }
        var decl: Option<Decl> = Some(structContext[structContext.size - 1])
        while (let Some(value) <- decl) {
            if (value.IsNominalDecl()) {
                return value
            }
            decl = value.outerDecl
        }
        return None
    }

    private func WalkNameReferenceTypeArguments(expr: NameReferenceExpr, pkg: Package): Unit {
        for (typeArg in expr.typeArguments) {
            InstantiateReferencedGenericsInNode(typeArg, pkg)
        }
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
        WalkNameReferenceTypeArguments(refExpr, pkg)
        if (let Some(target) <- refExpr.GetTarget()) {
            if (target.astKind == ASTKind.GENERIC_PARAM_DECL || target.astKind == ASTKind.PACKAGE_DECL) {
                return
            }
            var targetDecl = GetRealTarget(target)
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
            let contextBaseTy = GetContextBaseTy(targetDecl)
            if (let Some(baseTy) <- contextBaseTy) {
                InstantiateParentDeclForMemberTarget(targetDecl, baseTy, pkg)
            }
            InstantiateGenericDeclWithInstTys(targetDecl, instTys, pkg)
            if (let Some(baseTy) <- contextBaseTy) {
                if (targetDecl.IsFunc() && targetDecl.TestAttr(Attribute.GENERIC)) {
                    let contextTarget = FindInstantiatedTarget(targetDecl, Some(baseTy), instTys,
                        refExpr.matchedParentTy, pkg)
                    InstantiateGenericDeclWithInstTys(contextTarget, instTys, pkg)
                }
            }
        }
    }

    private func GenericMemberAccessInstantiate(memberAccess: MemberAccess, pkg: Package): Unit {
        WalkNameReferenceTypeArguments(memberAccess, pkg)
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            InstantiateReferencedGenericsInNode(baseExpr, pkg)
        }
        if (let Some(target) <- memberAccess.GetTarget()) {
            if (target.astKind == ASTKind.PACKAGE_DECL) {
                return
            }
            var targetDecl = GetRealTarget(target)
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
            if (let Some(baseTy) <- GetMemberBaseTy(memberAccess)) {
                InstantiateParentDeclForMemberTarget(targetDecl, baseTy, pkg)
            }
            InstantiateGenericDeclWithInstTys(targetDecl, instTys, pkg)
        }
    }

    private func GetContextBaseTy(target: Decl): Option<Ty> {
        if (let Some(contextDecl) <- GetStructDeclByContext()) {
            if (let Some(targetOuter) <- target.outerDecl) {
                if (!SameDecl(contextDecl, targetOuter)) {
                    return GetDeclTy(contextDecl)
                }
            }
        }
        return None
    }

    private func InstantiateParentDeclForMemberTarget(target: Decl, baseTy: Ty, pkg: Package): Unit {
        if (let Some(outer) <- target.outerDecl) {
            if (outer.IsNominalDecl() && (IsGenericInGenericStruct(target) || outer.TestAttr(Attribute.GENERIC))) {
                let outerTy = GetDeclTy(outer) ?? baseTy
                let promotedTys = Promotion(ci.typeManager).Promote(baseTy, outerTy)
                if (!promotedTys.IsEmpty()) {
                    InstantiateGenericDeclWithInstTys(outer, copyTypeArgs(Some(promotedTys.values[0])), pkg)
                }
            }
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
                if (!arrayTy.IsArray()) {
                    return
                }
                InstantiateGenericDeclWithInstTys(initFunc, copyTypeArgs(Some(arrayTy)), pkg)
            }
        }
    }

    private func GenericArrayLitInstantiate(arrayLit: ArrayLit, pkg: Package): Unit {
        for (child in arrayLit.children) {
            InstantiateReferencedGenericsInNode(child, pkg)
        }
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

    private func RearrangeReferences(pkg: Package): Unit {
        for (decl in pkg.genericInstantiatedDecls) {
            RearrangeReferencesInNode(decl, pkg)
        }
        for (file in pkg.files) {
            RearrangeReferencesInNode(file, pkg)
        }
        for (decl in pkg.srcImportedNonGenericDecls) {
            RearrangeReferencesInNode(decl, pkg)
        }
    }

    private func RearrangeReferencesInNode(root: Node, pkg: Package): Unit {
        let walker = Walker(root, visitPre: { node: Node =>
            CheckNodeRearrangement(node, pkg)
        }, visitPost: { node: Node =>
            PopStructContext(node)
        })
        let _ = walker.Walk()
    }

    private func CheckNodeRearrangement(node: Node, pkg: Package): VisitAction {
        if (node.astKind == ASTKind.GENERIC_PARAM_DECL || node.astKind == ASTKind.GENERIC_CONSTRAINT ||
            node.astKind == ASTKind.MODIFIER) {
            return VisitAction.SKIP_CHILDREN
        }
        PushStructContext(node)
        if (let Some(expr) <- (node as Expr)) {
            if (let Some(desugar) <- expr.desugarExpr) {
                RearrangeReferencesInNode(desugar, pkg)
                ClearInstTysIfNeeded(node)
                return VisitAction.SKIP_CHILDREN
            }
        }
        if (let Some(callExpr) <- (node as CallExpr)) {
            RearrangeCallExprReference(callExpr, pkg)
        } else if (let Some(refExpr) <- (node as RefExpr)) {
            RearrangeRefExprReference(refExpr, pkg)
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            RearrangeMemberAccessReference(memberAccess, pkg)
        } else if (let Some(typeNode) <- (node as Type)) {
            RearrangeTypeReference(typeNode, pkg)
            if (typeNode.astKind == ASTKind.REF_TYPE || typeNode.astKind == ASTKind.QUALIFIED_TYPE) {
                return VisitAction.SKIP_CHILDREN
            }
        } else if (let Some(arrayExpr) <- (node as ArrayExpr)) {
            RearrangeArrayExprReference(arrayExpr, pkg)
        } else if (let Some(arrayLit) <- (node as ArrayLit)) {
            RearrangeArrayLitReference(arrayLit, pkg)
        } else if (let Some(funcBody) <- (node as FuncBody)) {
            RearrangeFuncBodyReference(funcBody, pkg)
        } else if (let Some(pattern) <- (node as Pattern)) {
            UpdateTypePatternMatchResult(pattern)
        }
        return VisitAction.WALK_CHILDREN
    }

    private func ClearInstTysIfNeeded(node: Node): Unit {
        if (let Some(refExpr) <- (node as RefExpr)) {
            if (let Some(target) <- refExpr.GetTarget()) {
                if (TargetNoLongerGeneric(target)) {
                    refExpr.instTys.clear()
                    if (target.astKind != ASTKind.TYPE_ALIAS_DECL) {
                        if (let Some(targetTy) <- target.GetTy()) {
                            refExpr.SetTy(targetTy)
                        }
                    }
                }
            }
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            if (let Some(target) <- memberAccess.GetTarget()) {
                if (TargetNoLongerGeneric(target)) {
                    memberAccess.instTys.clear()
                    if (target.astKind != ASTKind.TYPE_ALIAS_DECL && !HasJavaTargetAttr(target)) {
                        if (let Some(targetTy) <- target.GetTy()) {
                            memberAccess.SetTy(targetTy)
                        }
                    }
                }
            }
        } else if (let Some(callExpr) <- (node as CallExpr)) {
            if (let Some(desugarExpr) <- callExpr.desugarExpr) {
                if (let Some(desugarTy) <- desugarExpr.GetTy()) {
                    if (!desugarTy.HasGeneric()) {
                        if (let Some(callBaseFunc) <- callExpr.baseFunc) {
                            if (let Some(nameRefExpr) <- (callBaseFunc as NameReferenceExpr)) {
                                nameRefExpr.instTys.clear()
                                return
                            }
                        }
                    }
                }
            }
            if (let Some(baseFunc) <- callExpr.baseFunc) {
                ClearInstTysIfNeeded(baseFunc)
            }
        }
    }

    private func TargetNoLongerGeneric(target: Decl): Bool {
        if (target.TestAnyAttr(Attribute.INTRINSIC, Attribute.GENERIC)) {
            return false
        }
        if (let Some(targetTy) <- target.GetTy()) {
            return Ty.IsTyCorrect(targetTy) && !targetTy.HasGeneric()
        }
        return false
    }

    private func RearrangeCallExprReference(callExpr: CallExpr, pkg: Package): Unit {
        if (let Some(baseFunc) <- callExpr.baseFunc) {
            if (baseFunc.IsReferenceExpr()) {
                RearrangeReferencesInNode(baseFunc, pkg)
                if (let Some(target) <- baseFunc.GetTarget()) {
                    if (let Some(funcDecl) <- (target as FuncDecl)) {
                        callExpr.resolvedFunction = funcDecl
                        if (!HasJavaTargetAttr(target)) {
                            if (let Some(targetTy) <- target.GetTy()) {
                                if (let Some(funcTy) <- (targetTy as FuncTy)) {
                                    if (!funcTy.retTy.HasGeneric()) {
                                        callExpr.SetTy(funcTy.retTy)
                                        UpdateDynamicThisCallTy(callExpr)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func UpdateDynamicThisCallTy(callExpr: CallExpr): Unit {
        if (let Some(callTy) <- callExpr.GetTy()) {
            if (let Some(_) <- (callTy as ClassThisTy)) {
                if (let Some(baseFunc) <- callExpr.baseFunc) {
                    if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                        if (let Some(baseExpr) <- memberAccess.baseExpr) {
                            if (let Some(baseTy) <- baseExpr.GetTy()) {
                                callExpr.SetTy(baseTy)
                            }
                        }
                    }
                }
            }
        }
    }

    private func RearrangeRefExprReference(refExpr: RefExpr, pkg: Package): Unit {
        if (!Ty.IsTyCorrect(refExpr.GetTy())) {
            return
        }
        if (let Some(target) <- refExpr.GetTarget()) {
            if (ignoredInstantiationKind(target) || !RequireInstantiation(target)) {
                return
            }
            let instTys = GetInstTysForRefExpr(refExpr, target)
            refExpr.ref.target = FindInstantiatedTarget(target, refExpr.GetTy(), instTys, refExpr.matchedParentTy, pkg)
            ClearInstTysIfNeeded(refExpr)
        }
    }

    private func RearrangeMemberAccessReference(memberAccess: MemberAccess, pkg: Package): Unit {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            RearrangeReferencesInNode(baseExpr, pkg)
        }
        if (!Ty.IsTyCorrect(memberAccess.GetTy())) {
            return
        }
        if (let Some(target) <- memberAccess.GetTarget()) {
            if (ignoredInstantiationKind(target)) {
                return
            }
            let baseTy = GetMemberBaseTy(memberAccess)
            let instTys = GetInstTysForMemberAccess(memberAccess, target, baseTy)
            memberAccess.target = FindInstantiatedTarget(target, baseTy, instTys, memberAccess.matchedParentTy, pkg)
            ClearInstTysIfNeeded(memberAccess)
        }
    }

    private func RearrangeTypeReference(typeNode: Type, pkg: Package): Unit {
        if (!Ty.IsTyCorrect(typeNode.GetTy())) {
            return
        }
        if (let Some(typeTy) <- typeNode.GetTy()) {
            if (typeTy.HasGeneric() || typeTy.HasIntersectionTy()) {
                return
            }
            if (let Some(target) <- Ty.GetDeclPtrOfTy(typeTy)) {
                let instantiatedDecl = FindInstantiatedTarget(target, Some(typeTy), copyTypeArgs(Some(typeTy)), None, pkg)
                if (let Some(refType) <- (typeNode as RefType)) {
                    refType.ref.target = instantiatedDecl
                } else if (let Some(qualifiedType) <- (typeNode as QualifiedType)) {
                    qualifiedType.target = instantiatedDecl
                }
            }
        }
    }

    private func RearrangeArrayExprReference(arrayExpr: ArrayExpr, pkg: Package): Unit {
        if (let Some(initFunc) <- arrayExpr.initFunc) {
            if (let Some(arrayTy) <- arrayExpr.GetTy()) {
                if (let Some(target) <- (FindInstantiatedTarget(initFunc, Some(arrayTy), copyTypeArgs(Some(arrayTy)),
                    None, pkg) as FuncDecl)) {
                    arrayExpr.initFunc = target
                }
            }
        }
    }

    private func RearrangeArrayLitReference(arrayLit: ArrayLit, pkg: Package): Unit {
        if (let Some(initFunc) <- arrayLit.initFunc) {
            if (let Some(arrayTy) <- arrayLit.GetTy()) {
                if (let Some(target) <- (FindInstantiatedTarget(initFunc, Some(arrayTy), copyTypeArgs(Some(arrayTy)),
                    None, pkg) as FuncDecl)) {
                    arrayLit.initFunc = target
                }
            }
        }
    }

    private func SelectContextOrDeclTy(contextTy: Option<Ty>, decl: Decl): Option<Ty> {
        if (let Some(value) <- contextTy) {
            return value
        }
        return decl.GetTy()
    }

    private func RearrangeFuncBodyReference(funcBody: FuncBody, pkg: Package): Unit {
        var contextTy: Option<Ty> = None
        if (let Some(contextDecl) <- GetStructDeclByContext()) {
            contextTy = GetDeclTy(contextDecl)
        }
        if (let Some(parentClassLike) <- funcBody.parentClassLike) {
            if (let Some(parentTy) <- SelectContextOrDeclTy(contextTy, parentClassLike)) {
                let target = FindInstantiatedTarget(parentClassLike, Some(parentTy), copyTypeArgs(Some(parentTy)),
                    None, pkg)
                if (let Some(classLike) <- (target as ClassLikeDecl)) {
                    funcBody.parentClassLike = classLike
                }
            }
        } else if (let Some(parentStruct) <- funcBody.parentStruct) {
            if (let Some(parentTy) <- SelectContextOrDeclTy(contextTy, parentStruct)) {
                let target = FindInstantiatedTarget(parentStruct, Some(parentTy), copyTypeArgs(Some(parentTy)),
                    None, pkg)
                if (let Some(structDecl) <- (target as StructDecl)) {
                    funcBody.parentStruct = structDecl
                }
            }
        } else if (let Some(parentEnum) <- funcBody.parentEnum) {
            if (let Some(parentTy) <- SelectContextOrDeclTy(contextTy, parentEnum)) {
                let target = FindInstantiatedTarget(parentEnum, Some(parentTy), copyTypeArgs(Some(parentTy)),
                    None, pkg)
                if (let Some(enumDecl) <- (target as EnumDecl)) {
                    funcBody.parentEnum = enumDecl
                }
            }
        }
    }

    private func UpdateTypePatternMatchResult(pattern: Pattern): Unit {
        if (!Ty.IsTyCorrect(pattern.GetTy())) {
            return
        }
        if (let Some(tuplePattern) <- (pattern as TuplePattern)) {
            if (let Some(patternTy) <- tuplePattern.GetTy()) {
                if (let Some(tupleTy) <- (patternTy as TupleTy)) {
                    UpdateChildTypePatterns(tupleTy.typeArgs, tuplePattern.patterns)
                }
            }
        } else if (let Some(enumPattern) <- (pattern as EnumPattern)) {
            if (let Some(constructor) <- enumPattern.constructor) {
                if (let Some(constructorTy) <- constructor.GetTy()) {
                    if (let Some(funcTy) <- (constructorTy as FuncTy)) {
                        UpdateChildTypePatterns(funcTy.paramTys, enumPattern.patterns)
                    }
                }
            }
        } else if (let Some(ctxExpr) <- pattern.ctxExpr) {
            if (let Some(ctxTy) <- ctxExpr.GetTy()) {
                UpdateTypePattern(ctxTy, pattern)
            }
        }
    }

    private func UpdateChildTypePatterns(targetTys: ArrayList<Ty>, patterns: ArrayList<Pattern>): Unit {
        let limit = if (targetTys.size < patterns.size) { targetTys.size } else { patterns.size }
        for (idx in 0..limit) {
            UpdateTypePattern(targetTys[idx], patterns[idx])
        }
    }

    private func UpdateTypePattern(targetTy: Ty, pattern: Pattern): Unit {
        if (let Some(typePattern) <- (pattern as TypePattern)) {
            if (typePattern.matchBeforeRuntime) {
                return
            }
            if (let Some(typeNode) <- typePattern.typeNode) {
                if (let Some(patternTy) <- typeNode.GetTy()) {
                    typePattern.matchBeforeRuntime =
                        ci.typeManager.IsSubtype(targetTy, patternTy, implicitBoxed: true, allowOptionBox: false)
                    typePattern.needRuntimeTypeCheck =
                        !typePattern.matchBeforeRuntime && IsNeedRuntimeCheck(ci.typeManager, targetTy, patternTy)
                }
            }
        }
    }

    private func GetInstTysForRefExpr(refExpr: RefExpr, target: Decl): ArrayList<Ty> {
        let instTys = ArrayList<Ty>()
        for (ty in refExpr.instTys) {
            instTys.add(ty)
        }
        if (refExpr.isThis || refExpr.isSuper || IsClassOrEnumConstructor(target)) {
            instTys.clear()
            if (let Some(refTy) <- refExpr.GetTy()) {
                let baseTy = if (let Some(funcTy) <- (refTy as FuncTy)) { funcTy.retTy } else { refTy }
                for (arg in baseTy.typeArgs) {
                    instTys.add(arg)
                }
            }
        }
        return instTys
    }

    private func GetInstTysForMemberAccess(memberAccess: MemberAccess, target: Decl, baseTy: Option<Ty>):
        ArrayList<Ty> {
        let instTys = ArrayList<Ty>()
        for (ty in memberAccess.instTys) {
            instTys.add(ty)
        }
        if (IsClassOrEnumConstructor(target)) {
            instTys.clear()
            if (let Some(ty) <- memberAccess.GetTy()) {
                let resultTy = if (let Some(funcTy) <- (ty as FuncTy)) { funcTy.retTy } else { ty }
                for (arg in resultTy.typeArgs) {
                    instTys.add(arg)
                }
            } else if (let Some(ty) <- baseTy) {
                for (arg in ty.typeArgs) {
                    instTys.add(arg)
                }
            }
        }
        return instTys
    }

    private func GetMemberBaseTy(memberAccess: MemberAccess): Option<Ty> {
        if (let Some(baseExpr) <- memberAccess.baseExpr) {
            if (let Some(baseTy) <- baseExpr.GetTy()) {
                if (Ty.IsTyCorrect(baseTy)) {
                    return baseTy
                }
            }
        }
        return memberAccess.GetTy()
    }

    private func FindInstantiatedTarget(target: Decl, baseTy: Option<Ty>, instTys: ArrayList<Ty>,
        upperTy: Option<Ty>, pkg: Package): Decl {
        let generalDecl = PartialInstantiation.GetGeneralDecl(target)
        if (ignoredInstantiationKind(generalDecl) || generalDecl.IsBuiltIn()) {
            return target
        }
        if (generalDecl.IsNominalDecl() || (let None <- generalDecl.outerDecl)) {
            return FindCachedGenericDecl(generalDecl, instTys, pkg) ?? target
        }
        if (let Some(outerDecl) <- generalDecl.outerDecl) {
            if (outerDecl.IsNominalDecl()) {
                let targetBaseTy = if (let Some(value) <- upperTy) { value } else if (let Some(value) <- baseTy) {
                    value
                } else {
                    return FindCachedGenericDecl(generalDecl, instTys, pkg) ?? target
                }
                let outerGeneral = PartialInstantiation.GetGeneralDecl(outerDecl)
                if ((let Some(_) <- outerGeneral.GetGeneric()) && !targetBaseTy.HasGeneric()) {
                    let outerInfo = ConstructGenericInfo(outerGeneral, copyTypeArgs(Some(targetBaseTy)))
                    if (let Some(instantiatedOuter) <- FindInCache(outerInfo, pkg)) {
                        if (let Some(member) <- FindMemberInInstantiatedDecl(instantiatedOuter, generalDecl)) {
                            if ((let Some(_) <- member.GetGeneric()) && !instTys.isEmpty()) {
                                return FindCachedGenericDecl(member, instTys, pkg) ?? member
                            }
                            return member
                        }
                    }
                }
            }
        }
        return FindCachedGenericDecl(generalDecl, instTys, pkg) ?? target
    }

    private func FindCachedGenericDecl(genericDecl: Decl, instTys: ArrayList<Ty>, pkg: Package): Option<Decl> {
        if ((let None <- genericDecl.GetGeneric()) || instTys.isEmpty() || Ty.ExistGeneric(instTys)) {
            return None
        }
        let genericInfo = ConstructGenericInfo(genericDecl, instTys)
        if (genericInfo.gTyToTyMap.IsEmpty()) {
            return None
        }
        return FindInCache(genericInfo, pkg)
    }

    private func FindMemberInInstantiatedDecl(owner: Decl, genericMember: Decl): Option<Decl> {
        for (member in owner.GetMemberDecls()) {
            if (SameDecl(PartialInstantiation.GetGeneralDecl(member), genericMember)) {
                return member
            }
            if (let Some(propDecl) <- (member as PropDecl)) {
                for (getter in propDecl.getters) {
                    if (SameDecl(PartialInstantiation.GetGeneralDecl(getter), genericMember)) {
                        return getter
                    }
                }
                for (setter in propDecl.setters) {
                    if (SameDecl(PartialInstantiation.GetGeneralDecl(setter), genericMember)) {
                        return setter
                    }
                }
            }
        }
        return None
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
