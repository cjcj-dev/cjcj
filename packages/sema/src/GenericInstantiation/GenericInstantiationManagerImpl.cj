package cjcj::sema.GenericInstantiation

import std.collection.*
import cjcj::ast.*
import cjcj::sema.*
import cjcj::sema.Desugar.AfterTypeCheck.IsNeedRuntimeCheck
import cjcj::sema.Test.TestManager as RealTestManager
import cjcj::utils.{CJC_ASSERT, InternalError}

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

private func addDeclUnique(values: ArrayList<Decl>, seen: HashSet<Int64>, candidate: Decl): Unit {
    let key = candidate.objectId
    if (!seen.contains(key)) {
        seen.add(key)
        values.add(candidate)
    }
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

private func insertGenericInfoKeyPair(pairs: ArrayList<(Int64, Int64)>, pair: (Int64, Int64)): Unit {
    var idx: Int64 = 0
    while (idx < pairs.size) {
        let current = pairs[idx]
        if (pair[0] < current[0] || (pair[0] == current[0] && pair[1] < current[1])) {
            pairs.add(pair, at: idx)
            return
        }
        idx++
    }
    pairs.add(pair)
}

private func genericInfoKey(decl: Decl, subst: TypeSubst): String {
    let builder = StringBuilder()
    builder.append(decl.objectId.toString())
    let pairs = ArrayList<(Int64, Int64)>()
    for (entry in subst.entries) {
        insertGenericInfoKeyPair(pairs, (entry.tyVar.objectId, entry.ty.objectId))
    }
    for (pair in pairs) {
        builder.append("|")
        builder.append(pair[0].toString())
        builder.append("=")
        builder.append(pair[1].toString())
    }
    return builder.toString()
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

private func GetOriginalTy(ty: Ty, g2gTyMap: TypeSubst, typeManager: TypeManager): Ty {
    if (!ty.IsGeneric() && !ty.HasGeneric()) {
        return ty
    }
    if (let Some(gTy) <- (ty as GenericsTy)) {
        if (let Some(found) <- g2gTyMap.Get(gTy)) {
            return found
        }
    }
    if (!ty.IsFunc()) {
        let tyArgs = ArrayList<Ty>()
        for (tyArg in ty.typeArgs) {
            tyArgs.add(GetOriginalTy(tyArg, g2gTyMap, typeManager))
        }
        if (ty.IsTuple()) {
            return typeManager.GetTupleTy(tyArgs.toArray())
        }
        let decl = Ty.GetDeclPtrOfTy(ty)
        if (let None <- decl) {
            return ty
        }
        if (ty.IsClass()) {
            if (let Some(classDecl) <- (decl.getOrThrow() as ClassDecl)) {
                if ((ty as ClassThisTy).isSome()) {
                    return typeManager.GetClassThisTy(classDecl, tyArgs.toArray())
                }
                return typeManager.GetClassTy(classDecl, tyArgs.toArray())
            }
        }
        if (ty.IsInterface()) {
            if (let Some(interfaceDecl) <- (decl.getOrThrow() as InterfaceDecl)) {
                return typeManager.GetInterfaceTy(interfaceDecl, tyArgs.toArray())
            }
        }
        if (ty.IsEnum()) {
            if (let Some(enumDecl) <- (decl.getOrThrow() as EnumDecl)) {
                return typeManager.GetEnumTy(enumDecl, typeArgs: tyArgs.toArray())
            }
        }
        if (ty.IsStruct()) {
            if (let Some(structDecl) <- (decl.getOrThrow() as StructDecl)) {
                return typeManager.GetStructTy(structDecl, tyArgs.toArray())
            }
        }
        return ty
    }
    let funcTy = (ty as FuncTy).getOrThrow()
    let paramTys = ArrayList<Ty>()
    for (paramTy in funcTy.paramTys) {
        paramTys.add(GetOriginalTy(paramTy, g2gTyMap, typeManager))
    }
    return typeManager.GetFunctionTy(paramTys.toArray(), GetOriginalTy(funcTy.retTy, g2gTyMap, typeManager))
}

private func PerformTyInstantiationDuringClone(genericNode: Node, clonedNode: Node, typeManager: TypeManager,
    info: GenericInfo, g2gTyMap: TypeSubst): Unit {
    if (Ty.IsTyCorrect(genericNode.GetTy())) {
        if (let Some(genericTy) <- genericNode.GetTy()) {
            clonedNode.SetTy(typeManager.GetInstantiatedTy(GetOriginalTy(genericTy, g2gTyMap, typeManager),
                info.gTyToTyMap))
        }
    }
    if (let Some(refExpr) <- (clonedNode as NameReferenceExpr)) {
        if (let Some(parentTy) <- refExpr.matchedParentTy) {
            refExpr.matchedParentTy = typeManager.GetInstantiatedTy(GetOriginalTy(parentTy, g2gTyMap, typeManager),
                info.gTyToTyMap)
        }
        var idx: Int64 = 0
        while (idx < refExpr.instTys.size) {
            refExpr.instTys[idx] = typeManager.GetInstantiatedTy(GetOriginalTy(refExpr.instTys[idx], g2gTyMap,
                typeManager), info.gTyToTyMap)
            idx++
        }
    }
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
    PerformTyInstantiationDuringClone(genericNode, clonedNode, typeManager, GenericInfo(None, typeMapping), g2gTyMap)
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
    typeManager.AddDeclExtendsEntry(entry)
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

private func HasJavaTargetAttr(target: Decl): Bool {
    if (let Some(_) <- HasJavaAttr(target)) {
        return true
    }
    return false
}

class GenericInstantiationManagerImpl {
    private var ci: CompilerInstance
    private let instantiations: ArrayList<GenericInstantiationRecord> = ArrayList<GenericInstantiationRecord>()
    private let declInstantiationByTypeMap: HashMap<String, ArrayList<GenericInstantiationRecord>> =
        HashMap<String, ArrayList<GenericInstantiationRecord>>()
    private let instantiatedDeclsMap: HashMap<Int64, ArrayList<Decl>> = HashMap<Int64, ArrayList<Decl>>()
    let abstractFuncToDeclMap: AbstractFuncMap = AbstractFuncMap()
    private let inheritedMemberFuncsCache: HashMap<Int64, ArrayList<FuncDecl>> =
        HashMap<Int64, ArrayList<FuncDecl>>()
    private let inheritedInterfacesCache: HashMap<Int64, ArrayList<InheritableDecl>> =
        HashMap<Int64, ArrayList<InheritableDecl>>()
    private let membersIndexMap: HashMap<Int64, Int64> = HashMap<Int64, Int64>()
    private let skippedMemberOffsets: HashMap<Int64, ArrayList<Int64>> = HashMap<Int64, ArrayList<Int64>>()
    private let structContext: ArrayList<Decl> = ArrayList<Decl>()
    private let usedSrcImportedDecls: ArrayList<Decl> = ArrayList<Decl>()
    private let instantiationWalkerID: UInt32 = GetNextWalkerID()
    private let rearrangeWalkerID: UInt32 = GetNextWalkerID()
    private let promotion: Promotion
    private var curPkg: Option<Package> = None
    private var curTriggerNode: Option<Node> = None
    // Injected by the frontend so the two mock hooks (PrepareToMock/HandleCreateMock)
    // can run at the same points as C++ GenericInstantiatePackage; None when unset.
    private var testManager: Option<RealTestManager> = None

    public init(ci: CompilerInstance) {
        this.ci = ci
        promotion = Promotion(ci.typeManager)
        SetOptLevel(ci.globalOptions)
    }

    func SetTestManager(tm: RealTestManager): Unit {
        testManager = Some(tm)
    }

    public func GenericInstantiatePackage(pkg: Package, resetGlobalState!: Bool = true): Unit {
        if (resetGlobalState) {
            ResetGenericInstantiationStage()
        }
        curPkg = pkg
        InstantiatedExtendRecorder(this, ci.typeManager).Record(pkg)
        for (decl in pkg.genericInstantiatedDecls) {
            collectExistingInstantiation(decl)
        }
        InstantiateReferencedGenerics(pkg)
        // C++: Sema/GenericInstantiation/GenericInstantiationManagerImpl.cpp:296-298.
        if (let Some(tm) <- testManager) {
            tm.HandleCreateMock(pkg)
        }
        RearrangeReferences(pkg)
        RecoverDesugarForBuiltIn()
        updateInstantiatedExtendMap(ci.typeManager, pkg)
        updateInstantiatedDeclsLinkage(pkg)
        ClearImportedUnusedInstantiatedDecls()
    }

    public func GetInstantiatedDeclWithGenericInfo(genericInfo: GenericInfo, pkg: Package): Option<Decl> {
        if (let Some(cached) <- FindInCache(genericInfo, pkg)) {
            return cached
        }
        if (let Some(genericDecl) <- genericInfo.decl) {
            if (genericInfo.gTyToTyMap.IsEmpty()) {
                return genericDecl
            }
            let instantiatedDecl = InstantiateGenericDecl(genericDecl, genericInfo.gTyToTyMap, pkg)
            addInstantiationRecord(genericDecl, instantiatedDecl, genericInfo.gTyToTyMap)
            if (!SameDecl(genericDecl, instantiatedDecl)) {
                appendGenericInstantiation(pkg, instantiatedDecl)
                InstantiatedExtendRecorder(this, ci.typeManager).Record(instantiatedDecl)
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
        if (let Some(values) <- instantiatedDeclsMap.get(genericDecl.objectId)) {
            for (value in values) {
                out.add(value)
            }
        }
        return out
    }

    public func ResetGenericInstantiationStage(): Unit {
        instantiations.clear()
        declInstantiationByTypeMap.clear()
        instantiatedDeclsMap.clear()
        structContext.clear()
        usedSrcImportedDecls.clear()
        curPkg = None
        PartialInstantiation.ResetGlobalMap()
        BuildAbstractFuncMap()
    }

    private func AddFuncUnique(values: ArrayList<FuncDecl>, seen: HashSet<Int64>, candidate: FuncDecl): Unit {
        let key = candidate.objectId
        if (!seen.contains(key)) {
            seen.add(key)
            values.add(candidate)
        }
    }

    private func AddInheritableDeclUnique(values: ArrayList<InheritableDecl>, seen: HashSet<Int64>,
        candidate: InheritableDecl): Unit {
        let key = candidate.objectId
        if (!seen.contains(key)) {
            seen.add(key)
            values.add(candidate)
        }
    }

    private func SameDeclOptions(left: Option<Decl>, right: Option<Decl>): Bool {
        if (let Some(leftDecl) <- left) {
            if (let Some(rightDecl) <- right) {
                return SameDecl(leftDecl, rightDecl)
            }
            return false
        }
        return right.isNone()
    }

    private func HasVisitedInheritedMember(values: HashMap<Int64, HashSet<Int64>>, ty: Ty, decl: Decl): Bool {
        if (let Some(visitedDecls) <- values.get(ty.objectId)) {
            return visitedDecls.contains(decl.objectId)
        }
        return false
    }

    private func AddVisitedInheritedMember(values: HashMap<Int64, HashSet<Int64>>, ty: Ty, decl: Decl): Unit {
        let tyKey = ty.objectId
        if (!values.contains(tyKey)) {
            values[tyKey] = HashSet<Int64>()
        }
        values.get(tyKey).getOrThrow().add(decl.objectId)
    }

    private func CollectDeclMemberFuncs(decl: Decl, funcs: ArrayList<FuncDecl>, seen: HashSet<Int64>): Unit {
        for (member in decl.GetMemberDecls()) {
            let ignored = member.astKind == ASTKind.VAR_DECL ||
                member.TestAnyAttr(Attribute.PRIVATE, Attribute.CONSTRUCTOR)
            if (ignored) {
                continue
            }
            WorkForMembers(member, { current: Decl =>
                if (let Some(funcDecl) <- (current as FuncDecl)) {
                    AddFuncUnique(funcs, seen, funcDecl)
                }
            })
        }
    }

    private func MergeMemberFuncs(ty: Ty, decl: Decl, inheritedMembers: ArrayList<FuncDecl>): ArrayList<FuncDecl> {
        let memberFuncs = ArrayList<FuncDecl>()
        let memberFuncSet = HashSet<Int64>()
        CollectDeclMemberFuncs(decl, memberFuncs, memberFuncSet)
        let dropped = HashSet<Int64>()
        for (member in memberFuncs) {
            for (funcDecl in inheritedMembers) {
                if (funcDecl.identifier.Val() != member.identifier.Val()) {
                    continue
                }
                if (IsImplementationFunc(ty, funcDecl, member)) {
                    dropped.add(funcDecl.objectId)
                }
            }
        }
        for (funcDecl in inheritedMembers) {
            if (!dropped.contains(funcDecl.objectId)) {
                AddFuncUnique(memberFuncs, memberFuncSet, funcDecl)
            }
        }
        return memberFuncs
    }

    private func CollectInheritedMembers(ty: Ty, decl: Decl): ArrayList<FuncDecl> {
        let visited = HashMap<Int64, HashSet<Int64>>()
        return CollectInheritedMembersVisit(ty, decl, visited)
    }

    private func CollectInheritedMembersVisit(ty: Ty, decl: Decl,
        visited: HashMap<Int64, HashSet<Int64>>): ArrayList<FuncDecl> {
        if (HasVisitedInheritedMember(visited, ty, decl)) {
            return ArrayList<FuncDecl>()
        }
        AddVisitedInheritedMember(visited, ty, decl)
        var inheritedFuncs = ArrayList<FuncDecl>()
        if (let Some(inheritDecl) <- (decl as InheritableDecl)) {
            for (typeNode in inheritDecl.inheritedTypes) {
                let inheritedTy = if (let Some(value) <- typeNode.GetTy()) { value } else { continue }
                let baseDecl = if (let Some(value) <- Ty.GetDeclPtrOfTy(Some(inheritedTy))) { value } else { continue }
                if (inheritedFuncs.isEmpty()) {
                    inheritedFuncs = CollectInheritedMembersVisit(inheritedTy, baseDecl, visited)
                } else {
                    inheritedFuncs = MergeMemberFuncs(inheritedTy, baseDecl, inheritedFuncs)
                }
            }
        }
        return MergeMemberFuncs(ty, decl, inheritedFuncs)
    }

    private func GetInheritedMemberFuncs(ty: Ty): ArrayList<FuncDecl> {
        if (let Some(cached) <- inheritedMemberFuncsCache.get(ty.objectId)) {
            return cached
        }
        var funcs = ArrayList<FuncDecl>()
        if (let Some(baseDecl) <- Ty.GetInheritableDeclPtrOfTy(Some(ty))) {
            funcs = CollectInheritedMembers(ty, baseDecl)
        }
        let funcSet = HashSet<Int64>()
        for (funcDecl in funcs) {
            funcSet.add(funcDecl.objectId)
        }
        for (extendDecl in GetAllRelatedExtendsByTy(ci.typeManager, ty)) {
            if (extendDecl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                continue
            }
            CollectDeclMemberFuncs(extendDecl, funcs, funcSet)
        }
        inheritedMemberFuncsCache[ty.objectId] = funcs
        return funcs
    }

    private func CollectInterfacesFromDecl(decl: InheritableDecl, out: ArrayList<InheritableDecl>,
        seen: HashSet<Int64>): Unit {
        for (interfaceTy in decl.GetSuperInterfaceTys()) {
            if (let Some(interfaceDeclValue) <- Ty.GetDeclPtrOfTy(Some(interfaceTy))) {
                if (let Some(interfaceDecl) <- (interfaceDeclValue as InterfaceDecl)) {
                    AddInheritableDeclUnique(out, seen, interfaceDecl)
                }
            }
        }
    }

    private func CollectInheritedInterfacesFromDecl(decl: InheritableDecl,
        out: ArrayList<InheritableDecl>, seen: HashSet<Int64>): Unit {
        if (let Some(classDecl) <- (decl as ClassDecl)) {
            if (let Some(superClass) <- classDecl.GetSuperClassDecl()) {
                AddInheritableDeclUnique(out, seen, superClass)
                CollectInheritedInterfacesFromDecl(superClass, out, seen)
            }
        }
        CollectInterfacesFromDecl(decl, out, seen)
    }

    private func GetInheritedInterfaces(ty: Ty): ArrayList<InheritableDecl> {
        if (let Some(cached) <- inheritedInterfacesCache.get(ty.objectId)) {
            return cached
        }
        let inheritableType = ArrayList<InheritableDecl>()
        let inheritableTypeSet = HashSet<Int64>()
        for (extendDecl in GetAllRelatedExtendsByTy(ci.typeManager, ty)) {
            if (extendDecl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                continue
            }
            CollectInterfacesFromDecl(extendDecl, inheritableType, inheritableTypeSet)
        }
        if (let Some(decl) <- Ty.GetDeclPtrOfTy(Some(ty))) {
            if (let Some(inheritDecl) <- (decl as InheritableDecl)) {
                CollectInheritedInterfacesFromDecl(inheritDecl, inheritableType, inheritableTypeSet)
            }
        }
        let allInterfaceTys = TySet()
        for (inheritableDecl in inheritableType) {
            if (let Some(inheritableTy) <- inheritableDecl.GetTy()) {
                allInterfaceTys.AddAll(ci.typeManager.GetAllSuperTys(inheritableTy))
            }
        }
        let _ = allInterfaceTys.Remove(ty)
        for (interfaceTy in allInterfaceTys.values) {
            if (let Some(interfaceDeclValue) <- Ty.GetDeclPtrOfTy(Some(interfaceTy))) {
                if (let Some(interfaceDecl) <- (interfaceDeclValue as InterfaceDecl)) {
                    AddInheritableDeclUnique(inheritableType, inheritableTypeSet, interfaceDecl)
                }
            }
        }
        inheritedInterfacesCache[ty.objectId] = inheritableType
        return inheritableType
    }

    private func MapFuncWithDecl(ty: Ty, interfaceFunc: FuncDecl, target: FuncDecl): Unit {
        CJC_ASSERT(target.outerDecl.isSome())
        let outerDecl = target.outerDecl.getOrThrow()
        let decls = GetRealIndexingMembers(outerDecl.GetMemberDecls(),
            inGenericDecl: outerDecl.TestAttr(Attribute.GENERIC))
        let realDecl: Decl = if (let Some(propDecl) <- target.propDecl) {
            propDecl
        } else {
            target
        }
        for (idx in 0..decls.size) {
            if (SameDecl(decls[idx], realDecl)) {
                abstractFuncToDeclMap.Add(ty, interfaceFunc, outerDecl, idx)
                break
            }
        }
    }

    private func GetTypeMapping(baseTyInput: Option<Ty>, interfaceTy: Ty): (MultiTypeSubst, Option<Ty>) {
        var baseTy = baseTyInput
        var typeMapping = MultiTypeSubst()
        if (let None <- baseTy) {
            return (typeMapping, baseTy)
        }
        typeMapping = promotion.GetPromoteTypeMapping(baseTy.getOrThrow(), interfaceTy)
        if (!typeMapping.entries.isEmpty()) {
            return (typeMapping, baseTy)
        }
        for (extendDecl in GetAllRelatedExtendsByTy(ci.typeManager, baseTy.getOrThrow())) {
            if (extendDecl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                continue
            }
            if (let Some(extendedType) <- extendDecl.extendedType) {
                baseTy = extendedType.GetTy()
            } else {
                baseTy = None
            }
            let promoteRes = if (let Some(value) <- baseTy) {
                promotion.GetPromoteTypeMapping(value, interfaceTy)
            } else {
                MultiTypeSubst()
            }
            MergeMultiTypeSubsts(typeMapping, promoteRes)
        }
        return (typeMapping, baseTy)
    }

    private func IsImplementationFunc(ty: Ty, interfaceFunc: FuncDecl, fd: FuncDecl): Bool {
        CJC_ASSERT(fd.outerDecl.isSome())
        CJC_ASSERT(interfaceFunc.outerDecl.isSome())
        let noRelation = interfaceFunc.TestAttr(Attribute.STATIC) != fd.TestAttr(Attribute.STATIC) ||
            interfaceFunc.TestAttr(Attribute.GENERIC) != fd.TestAttr(Attribute.GENERIC)
        if (noRelation) {
            return false
        }
        let interfaceOuter = interfaceFunc.outerDecl.getOrThrow()
        let fdOuter = fd.outerDecl.getOrThrow()
        if (interfaceOuter.astKind == fdOuter.astKind) {
            if (fd.TestAttr(Attribute.ABSTRACT)) {
                return false
            }
        } else {
            if (fdOuter.astKind == ASTKind.INTERFACE_DECL) {
                return false
            }
        }
        var baseTy: Option<Ty> = Some(ty)
        let structDecl = if (let Some(value) <- (fdOuter as InheritableDecl)) { value } else { return false }
        var shouldUpdateImplementTy = true
        if (let Some(extendDecl) <- (structDecl as ExtendDecl)) {
            if (let Some(extendedType) <- extendDecl.extendedType) {
                if (SameDeclOptions(Ty.GetDeclPtrOfTy(extendedType.GetTy()), Ty.GetDeclPtrOfTy(baseTy))) {
                    baseTy = extendedType.GetTy()
                    shouldUpdateImplementTy = false
                }
            }
        }
        let interfaceTy = interfaceOuter.GetTy().getOrThrow()
        let mappingResult = GetTypeMapping(baseTy, interfaceTy)
        var typeMappings = mappingResult[0]
        baseTy = mappingResult[1]
        for (inheritedType in structDecl.inheritedTypes) {
            if (let Some(inheritedTy) <- inheritedType.GetTy()) {
                if (let Some(genericTy) <- Ty.GetGenericTyOfInsTy(inheritedTy)) {
                    if (ci.typeManager.IsSubtype(genericTy, interfaceTy)) {
                        ci.typeManager.GenerateGenericMapping(typeMappings, inheritedTy)
                        break
                    }
                }
            }
        }
        var iFuncTy = interfaceFunc.GetTy().getOrThrow()
        if (fd.TestAttr(Attribute.GENERIC)) {
            let typeMapping = ci.typeManager.GenerateGenericMappingFromGeneric(interfaceFunc, fd)
            iFuncTy = ci.typeManager.GetInstantiatedTy(iFuncTy, typeMapping)
        }
        let interfaceFuncTys = ci.typeManager.GetInstantiatedTys(iFuncTy, typeMappings)
        var implementedFuncTy = fd.GetTy().getOrThrow() as FuncTy
        if (shouldUpdateImplementTy) {
            if (let Some(baseTyValue) <- baseTy) {
                if (let Some(structTy) <- structDecl.GetTy()) {
                    typeMappings = promotion.GetPromoteTypeMapping(baseTyValue, structTy)
                } else {
                    typeMappings = MultiTypeSubst()
                }
            } else {
                typeMappings = MultiTypeSubst()
            }
            implementedFuncTy = ci.typeManager.GetBestInstantiatedTy(fd.GetTy().getOrThrow(), typeMappings) as FuncTy
        }
        for (interfaceFuncTy in interfaceFuncTys.values) {
            if (let Some(interfaceFuncValue) <- (interfaceFuncTy as FuncTy)) {
                if (let Some(implementedFuncValue) <- implementedFuncTy) {
                    if (ci.typeManager.IsFuncParameterTypesIdentical(implementedFuncValue, interfaceFuncValue)) {
                        return true
                    }
                }
            }
        }
        return false
    }

    func GetGeneralDecl(decl: Decl, getOriginal!: Bool = false): Decl {
        let target = GetRealTarget(decl)
        if (let Some(outerDecl) <- target.outerDecl) {
            if ((let Some(_) <- outerDecl.genericDecl) && !outerDecl.IsFunc()) {
                if (target.TestAttr(Attribute.GENERIC) && !getOriginal) {
                    return target
                }
                return PartialInstantiation.GetGeneralDecl(decl)
            }
        }
        if (let Some(genericDecl) <- target.genericDecl) {
            return genericDecl
        }
        return target
    }

    private func CountSkippedMembersBefore(decl: Decl, offset: Int64): Int64 {
        let declKey = decl.objectId
        let offsets = if (let Some(cached) <- skippedMemberOffsets.get(declKey)) {
            cached
        } else {
            let generated = ArrayList<Int64>()
            let members = GetRealIndexingMembers(decl.GetMemberDecls(), inGenericDecl: decl.TestAttr(Attribute.GENERIC))
            for (idx in 0..members.size) {
                let member = members[idx]
                let ignored = (member.astKind != ASTKind.VAR_DECL && !RequireInstantiation(member)) ||
                    IsStaticVar(member) || IsStaticInitializer(member)
                if (!ignored) {
                    generated.add(idx)
                }
            }
            skippedMemberOffsets[declKey] = generated
            generated
        }
        for (idx in 0..offsets.size) {
            if (offsets[idx] == offset) {
                return offset - idx
            }
        }
        return -1
    }

    private func GetMemberByOffset(decl: Decl, offset: Int64): Decl {
        var members = GetRealIndexingMembers(decl.GetMemberDecls(), inGenericDecl: decl.TestAttr(Attribute.GENERIC))
        if (!decl.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
            CJC_ASSERT(offset < members.size)
            return members[offset]
        }
        if (let Some(genericDecl) <- decl.genericDecl) {
            let count = CountSkippedMembersBefore(genericDecl, offset)
            if (count == -1) {
                members = GetRealIndexingMembers(genericDecl.GetMemberDecls(),
                    inGenericDecl: genericDecl.TestAttr(Attribute.GENERIC))
                CJC_ASSERT(offset < members.size)
                return members[offset]
            }
            CJC_ASSERT(count <= offset && offset - count < members.size)
            return members[offset - count]
        }
        CJC_ASSERT(false)
        return decl
    }

    private func SelectTypeMatchedImplMember(ty: Ty, interfaceFunc: FuncDecl,
        candidates: ArrayList<(Decl, Int64)>, targetBaseTy: Ty): Option<Decl> {
        var member: Option<Decl> = None
        for ((baseDecl, offset) in candidates) {
            var structDecl = baseDecl
            let instantiatedDecls = GetInstantiatedDecls(baseDecl)
            for (decl in instantiatedDecls) {
                if (let Some(declTy) <- GetDeclTy(decl)) {
                    if (ci.typeManager.IsSubtype(ty, declTy, implicitBoxed: false)) {
                        @When[backend == "cjnative"]
                        let selectedStructDecl = decl
                        @When[backend != "cjnative"]
                        let selectedStructDecl = structDecl
                        structDecl = selectedStructDecl
                        break
                    }
                }
            }
            let implMember = GetMemberByOffset(structDecl, offset)
            if (implMember.astKind == ASTKind.PROP_DECL || IsVirtualMember(implMember)) {
                member = implMember
                break
            }
            var iFuncTy = interfaceFunc.GetTy().getOrThrow() as FuncTy
            if (interfaceFunc.TestAttr(Attribute.GENERIC)) {
                let typeMapping = ci.typeManager.GenerateGenericMappingFromGeneric(interfaceFunc, implMember)
                if (let Some(funcTy) <- iFuncTy) {
                    iFuncTy = ci.typeManager.GetInstantiatedTy(funcTy, typeMapping) as FuncTy
                }
            } else if (let Some(interfaceOuter) <- interfaceFunc.outerDecl) {
                if (interfaceOuter.TestAttr(Attribute.GENERIC)) {
                    let typeMapping = GenerateTypeMappingByTy(interfaceOuter.GetTy(), Some(targetBaseTy))
                    if (let Some(implOuter) <- implMember.outerDecl) {
                        if (implOuter.TestAttr(Attribute.GENERIC)) {
                            let tmpMapping = GenerateTypeMappingByTy(implOuter.GetTy(), Some(ty))
                            let rts = GetReversedTypeSubst(tmpMapping)
                            let tg = TyGeneralizer(ci.typeManager, rts)
                            for (entry in typeMapping.entries) {
                                entry.ty = tg.Generalize(entry.ty)
                            }
                        }
                    }
                    if (let Some(funcTy) <- iFuncTy) {
                        iFuncTy = ci.typeManager.GetInstantiatedTy(funcTy, typeMapping) as FuncTy
                    }
                }
            }
            let usableDecls = GetInstantiatedDecls(implMember)
            if (usableDecls.isEmpty()) {
                usableDecls.add(implMember)
            }
            for (usableDecl in usableDecls) {
                if (let Some(usableTy) <- usableDecl.GetTy()) {
                    if (let Some(funcTy) <- (usableTy as FuncTy)) {
                        if (let Some(interfaceFuncTy) <- iFuncTy) {
                            if (ci.typeManager.IsFuncParameterTypesIdentical(funcTy, interfaceFuncTy)) {
                                member = usableDecl
                                break
                            }
                        }
                    }
                }
            }
            if (let Some(_) <- member) {
                break
            }
        }
        return member
    }

    private func FindImplFuncForAbstractFunc(ty: Ty, fd: FuncDecl, targetBaseTy: Ty): FuncDecl {
        let baseTyDecl = Ty.GetInheritableDeclPtrOfTy(Some(ty))
        var sameClassDecl = false
        if (ty.IsClass()) {
            if (let Some(baseDecl) <- baseTyDecl) {
                if (let Some(outerDecl) <- fd.outerDecl) {
                    if (let Some(outerTy) <- outerDecl.GetTy()) {
                        if (let Some(outerTyDecl) <- Ty.GetInheritableDeclPtrOfTy(Some(outerTy))) {
                            sameClassDecl = SameDecl(baseDecl, outerTyDecl)
                        }
                    }
                }
            }
        }
        let shouldIgnore = fd.outerDecl.isNone() || (ty.IsInterface() && !fd.TestAttr(Attribute.STATIC)) ||
            sameClassDecl
        if (shouldIgnore) {
            return fd
        }
        let baseTyForMap = ci.typeManager.GetTyForExtendMap(ty)
        var genericFdDecl = GetGeneralDecl(fd, getOriginal: true)
        if (let Some(genericDecl) <- genericFdDecl.genericDecl) {
            genericFdDecl = genericDecl
        }
        let genericFd = if (let Some(funcDecl) <- (genericFdDecl as FuncDecl)) { funcDecl } else { return fd }
        let foundAbstFunc = if (let Some(value) <- abstractFuncToDeclMap.Find(baseTyForMap, genericFd)) {
            value
        } else {
            return fd
        }
        let candidates = ArrayList<(Decl, Int64)>()
        let accessByInterface = ty.IsInterface()
        let fdOuter = fd.outerDecl.getOrThrow()
        let fdOuterGeneral = GetGeneralDecl(fdOuter, getOriginal: true)
        for ((decl, offset) in foundAbstFunc) {
            let notInSameDecl = !SameDecl(decl, fdOuterGeneral)
            let instInInterface = decl.astKind == ASTKind.INTERFACE_DECL
            if (accessByInterface) {
                if (notInSameDecl && instInInterface) {
                    candidates.add((decl, offset))
                }
            } else if (notInSameDecl) {
                candidates.add((decl, offset))
            }
        }
        if (let Some(member) <- SelectTypeMatchedImplMember(ty, fd, candidates, targetBaseTy)) {
            let usedMember = GetUsedMemberDecl(member, fd.isGetter)
            CJC_ASSERT(usedMember.astKind == ASTKind.FUNC_DECL)
            return (usedMember as FuncDecl).getOrThrow()
        }
        return fd
    }

    private func ReinstantiatedPartialMemberDecl(genericInfo: GenericInfo, structDecl: Decl, genericMember: Decl,
        memberIndex: Int64): Decl {
        let cloned = PartialInstantiation.Instantiate(genericMember, { genericNode: Node, clonedNode: Node =>
            PerformTyInstantiationDuringClone(genericNode, clonedNode, ci.typeManager, genericInfo, TypeSubst())
            if (let Some(clonedDecl) <- (clonedNode as Decl)) {
                if (let Some(genericDecl) <- genericInfo.decl) {
                    if (let Some(outerDecl) <- clonedDecl.outerDecl) {
                        if (SameDecl(outerDecl, genericDecl)) {
                            clonedDecl.outerDecl = structDecl
                        }
                    }
                }
            }
        })
        if (let Some(clonedDecl) <- (cloned as Decl)) {
            clonedDecl.EnableAttr(Attribute.GENERIC_INSTANTIATED)
            let partialDecl = clonedDecl
            let members = structDecl.GetMemberDecls()
            members[memberIndex] = clonedDecl
            return partialDecl
        }
        InternalError("generic instantiation failed")
        return genericMember
    }

    private func GetInstantiatedMemberTarget(baseTy: Ty, target: Decl, inRearrange!: Bool = false): Decl {
        let targetOuterDecl = target.outerDecl.getOrThrow()
        let declTy = GetDeclTy(targetOuterDecl)
        let noGeneric = if (let None <- targetOuterDecl.generic) { true } else { false }
        let ignore = noGeneric || !targetOuterDecl.TestAttr(Attribute.GENERIC) || !Ty.IsTyCorrect(declTy)
        if (ignore) {
            return target
        }
        let promotedTys = promotion.Promote(baseTy, declTy.getOrThrow())
        let realStructTy = if (promotedTys.IsEmpty()) { TypeManager.GetInvalidTy() } else { promotedTys.values[0] }
        if (realStructTy.HasInvalidTy() || realStructTy.HasGeneric()) {
            return target
        }
        let genericInfo = ConstructGenericInfo(targetOuterDecl, ci.typeManager.GetTypeArgs(realStructTy))
        var structDecl = FindInCache(genericInfo)
        if ((let None <- structDecl) && (let Some(triggerNode) <- curTriggerNode) &&
            triggerNode.visitedByWalkerID == instantiationWalkerID) {
            if (let Some(currentPkg) <- curPkg) {
                structDecl = GetInstantiatedDeclWithGenericInfo(genericInfo, currentPkg)
            }
        }
        let realMemberDecl = GetRealMemberDecl(target)
        let targetToFind = realMemberDecl.decl
        let foundIndex = membersIndexMap.get(targetToFind.objectId)
        if ((let None <- structDecl) || (let None <- foundIndex)) {
            if (!inRearrange) {
                InternalError("generic instantiation failed")
            }
            return target
        }
        let structDeclValue = structDecl.getOrThrow()
        let members = if (target.TestAttr(Attribute.ENUM_CONSTRUCTOR)) {
            (structDeclValue as EnumDecl).getOrThrow().constructors
        } else {
            structDeclValue.GetMemberDecls()
        }
        var found: Option<Decl> = None
        for (member in members) {
            if (SameDecl(PartialInstantiation.GetGeneralDecl(member), targetToFind)) {
                found = member
                break
            }
        }
        if (let None <- found) {
            return target
        }
        var resultDecl = found.getOrThrow()
        if (resultDecl.TestAttr(Attribute.GENERIC) && resultDecl.TestAttr(Attribute.GENERIC_INSTANTIATED) &&
            resultDecl.TestAttr(Attribute.UNREACHABLE)) {
            resultDecl = ReinstantiatedPartialMemberDecl(genericInfo, structDeclValue, targetToFind,
                foundIndex.getOrThrow())
        }
        resultDecl = GetUsedMemberDecl(resultDecl, realMemberDecl.isGetter)
        return resultDecl
    }

    private func BuildAbstractFuncMapHelper(ty: Ty): Unit {
        let funcs = GetInheritedMemberFuncs(ty)
        let interfaces = GetInheritedInterfaces(ty)
        let funcsByName = HashMap<String, ArrayList<FuncDecl>>()
        for (funcDecl in funcs) {
            let name = funcDecl.identifier.Val()
            if (!funcsByName.contains(name)) {
                funcsByName[name] = ArrayList<FuncDecl>()
            }
            funcsByName.get(name).getOrThrow().add(funcDecl)
        }
        for (interfaceDecl in interfaces) {
            if (let Some(interfaceTy) <- interfaceDecl.GetTy()) {
                for (realMember in GetInheritedMemberFuncs(interfaceTy)) {
                    let candidates = if (let Some(values) <- funcsByName.get(realMember.identifier.Val())) {
                        values
                    } else {
                        continue
                    }
                    for (funcDecl in candidates) {
                        if (IsImplementationFunc(ty, realMember, funcDecl)) {
                            MapFuncWithDecl(ty, realMember, funcDecl)
                        }
                    }
                }
            }
        }
    }

    private func MembersIndexFind(member: Decl): Option<Int64> {
        return membersIndexMap.get(member.objectId)
    }

    private func MembersIndexAdd(member: Decl, idx: Int64): Unit {
        if (let Some(_) <- MembersIndexFind(member)) {
            return
        }
        membersIndexMap[member.objectId] = idx
    }

    private func BuildAbstractFuncMap(): Unit {
        abstractFuncToDeclMap.Clear()
        inheritedMemberFuncsCache.clear()
        inheritedInterfacesCache.clear()
        membersIndexMap.clear()
        skippedMemberOffsets.clear()
        for (entry in ci.typeManager.builtinTyToExtendMap) {
            BuildAbstractFuncMapHelper(entry.ty)
        }
        let inheritableDecls = ArrayList<Decl>()
        let genericDecls = ArrayList<Decl>()
        let inheritableDeclSet = HashSet<Int64>()
        let genericDeclSet = HashSet<Int64>()
        let collectDecls = { decl: Decl =>
            if ((let None <- GetDeclTy(decl)) || !decl.IsNominalDecl()) {
                return
            }
            if (decl.astKind != ASTKind.EXTEND_DECL) {
                addDeclUnique(inheritableDecls, inheritableDeclSet, decl)
            }
            if (let Some(_) <- decl.generic) {
                addDeclUnique(genericDecls, genericDeclSet, decl)
            }
        }
        if (let Some(importManager) <- ci.importManager) {
            for (packageDecl in importManager.GetAllImportedPackages(false)) {
                IterateToplevelDecls(packageDecl.srcPackage, collectDecls)
            }
        } else {
            for (packageDecl in ci.importedPackageDecls) {
                IterateToplevelDecls(packageDecl.srcPackage, collectDecls)
            }
        }
        for (decl in inheritableDecls) {
            if (let Some(declTy) <- decl.GetTy()) {
                BuildAbstractFuncMapHelper(declTy)
            }
        }
        for (decl in genericDecls) {
            var idx: Int64 = 0
            for (member in decl.GetMemberDecls()) {
                if (member.astKind == ASTKind.PRIMARY_CTOR_DECL) {
                    continue
                }
                MembersIndexAdd(member, idx)
                idx++
            }
            if (let Some(enumDecl) <- (decl as EnumDecl)) {
                for (ctorIdx in 0..enumDecl.constructors.size) {
                    MembersIndexAdd(enumDecl.constructors[ctorIdx], ctorIdx)
                }
            }
        }
    }

    private func RecoverDesugarForBuiltIn(): Unit {
        if (let Some(pkg) <- curPkg) {
            for (decl in pkg.genericInstantiatedDecls) {
                let walker = Walker(decl, visitPost: { node: Node =>
                    if (let Some(callExpr) <- (node as CallExpr)) {
                        if (let Some(funcDecl) <- callExpr.resolvedFunction) {
                            if (let Some(outerDecl) <- funcDecl.outerDecl) {
                                var thisTy = outerDecl.GetTy()
                                var funcTy = funcDecl.GetTy() as FuncTy
                                if (let Some(baseFunc) <- callExpr.baseFunc) {
                                    if (baseFunc.astKind == ASTKind.MEMBER_ACCESS) {
                                        CJC_ASSERT((baseFunc as MemberAccess).isSome())
                                        if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                                            if (let Some(baseExpr) <- memberAccess.baseExpr) {
                                                thisTy = baseExpr.GetTy()
                                            }
                                            if (let Some(baseFuncTy) <- baseFunc.GetTy()) {
                                                CJC_ASSERT(baseFuncTy.IsFunc())
                                                funcTy = baseFuncTy as FuncTy
                                            }
                                        }
                                    }
                                }
                                if (let Some(funcTyValue) <- funcTy) {
                                    if (let Some(thisTyValue) <- thisTy) {
                                        if (funcTyValue.paramTys.size == 1 &&
                                            IsBuiltinBinaryExpr(funcDecl.op, thisTyValue, funcTyValue.paramTys[0])) {
                                            if (let Some(source) <- callExpr.sourceExpr) {
                                                if (let Some(binaryExpr) <- (source as BinaryExpr)) {
                                                    RecoverToBinaryExpr(binaryExpr)
                                                }
                                            } else if (let Some(baseFunc) <- callExpr.baseFunc) {
                                                CJC_ASSERT((baseFunc as MemberAccess).isSome())
                                                if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                                                    let binaryExpr = BinaryExpr()
                                                    binaryExpr.leftExpr = memberAccess.baseExpr
                                                    binaryExpr.rightExpr = callExpr.args[0].expr
                                                    memberAccess.baseExpr = None
                                                    callExpr.args[0].expr = None
                                                    binaryExpr.op = funcDecl.op
                                                    if (let Some(callTy) <- callExpr.GetTy()) {
                                                        binaryExpr.SetTy(callTy)
                                                    }
                                                    CopyBasicInfo(callExpr, binaryExpr)
                                                    AddCurFile(binaryExpr, file: callExpr.curFile)
                                                    callExpr.desugarExpr = binaryExpr
                                                }
                                            }
                                        } else if (funcTyValue.paramTys.isEmpty() &&
                                            IsBuiltinUnaryExpr(funcDecl.op, thisTyValue)) {
                                            if (let Some(source) <- callExpr.sourceExpr) {
                                                if (let Some(unaryExpr) <- (source as UnaryExpr)) {
                                                    RecoverToUnaryExpr(unaryExpr)
                                                }
                                            } else if (let Some(baseFunc) <- callExpr.baseFunc) {
                                                CJC_ASSERT((baseFunc as MemberAccess).isSome())
                                                if (let Some(memberAccess) <- (baseFunc as MemberAccess)) {
                                                    let unaryExpr = UnaryExpr()
                                                    unaryExpr.expr = memberAccess.baseExpr
                                                    memberAccess.baseExpr = None
                                                    unaryExpr.op = funcDecl.op
                                                    if (let Some(callTy) <- callExpr.GetTy()) {
                                                        unaryExpr.SetTy(callTy)
                                                    }
                                                    CopyBasicInfo(callExpr, unaryExpr)
                                                    AddCurFile(unaryExpr, file: callExpr.curFile)
                                                    callExpr.desugarExpr = unaryExpr
                                                }
                                            }
                                        }
                                        return VisitAction.SKIP_CHILDREN
                                    }
                                }
                            }
                        }
                    }
                    return VisitAction.WALK_CHILDREN
                })
                let _ = walker.Walk()
            }
        }
    }

    private func WalkImportedInstantiations(processFunc: (Decl) -> Unit, skipChecker: (Package) -> Bool): Unit {
        for (packageDecl in ci.importedPackageDecls) {
            let srcPkg = packageDecl.srcPackage
            if (skipChecker(srcPkg)) {
                continue
            }
            for (decl in srcPkg.genericInstantiatedDecls) {
                if (let Some(genericDecl) <- decl.genericDecl) {
                    if (IsMacroRelatedPackageName(genericDecl.fullPackageName)) {
                        continue
                    }
                }
                processFunc(decl)
            }
        }
    }

    private func RestoreInstantiatedDeclTy(): Unit {
        WalkImportedInstantiations({ decl: Decl =>
            RestoreInstantiatedDeclTy(decl)
        }, { pkg: Package =>
            IsMacroRelatedPackageName(pkg.fullPackageName)
        })
    }

    private func RestoreInstantiatedDeclTy(decl: Decl): Unit {
        if (Ty.IsInitialTy(decl.GetTy()) || !decl.IsNominalDecl() || decl.astKind == ASTKind.EXTEND_DECL) {
            return
        }
        if (!IsDeclCanRestoredForTy(decl)) {
            return
        }
        match (decl.TyKind()) {
            case TypeKind.TYPE_CLASS =>
                if (let Some(classTy) <- (decl.GetTy().getOrThrow() as ClassTy)) {
                    if (let Some(classDecl) <- (decl as ClassDecl)) {
                        classTy.decl = classDecl
                        classTy.commonDecl = classDecl
                        if (let Some(declPtr) <- classTy.declPtr) {
                            let thisTy = ci.typeManager.GetClassThisTy(declPtr, classTy.typeArgs.toArray())
                            thisTy.decl = classDecl
                            thisTy.commonDecl = classDecl
                        }
                    }
                }
            case TypeKind.TYPE_INTERFACE =>
                if (let Some(interfaceTy) <- (decl.GetTy().getOrThrow() as InterfaceTy)) {
                    if (let Some(interfaceDecl) <- (decl as InterfaceDecl)) {
                        interfaceTy.decl = interfaceDecl
                        interfaceTy.commonDecl = interfaceDecl
                    }
                }
            case TypeKind.TYPE_STRUCT =>
                if (let Some(structTy) <- (decl.GetTy().getOrThrow() as StructTy)) {
                    if (let Some(structDecl) <- (decl as StructDecl)) {
                        structTy.decl = structDecl
                    }
                }
            case TypeKind.TYPE_ENUM =>
                if (let Some(enumTy) <- (decl.GetTy().getOrThrow() as EnumTy)) {
                    if (let Some(enumDecl) <- (decl as EnumDecl)) {
                        enumTy.decl = enumDecl
                    }
                }
            case _ =>
                return
        }
    }

    private func IsDeclCanRestoredForTy(decl: Decl): Bool {
        if (let None <- curPkg) {
            return true
        }
        let currentPkg = curPkg.getOrThrow()
        if (decl.fullPackageName == currentPkg.fullPackageName) {
            return true
        }
        let typeMapping = BuildTypeMapping(decl)
        if (let Some(genericDecl) <- decl.genericDecl) {
            let info = GenericInfo(Some(genericDecl), typeMapping)
            if (let Some(_) <- FindInCache(info, currentPkg)) {
                return false
            }
        }
        return true
    }

    private func BuildTypeMapping(instantiatedDecl: Decl): TypeSubst {
        if (let Some(genericDecl) <- instantiatedDecl.genericDecl) {
            return ci.typeManager.GenerateGenericMappingFromGeneric(genericDecl, instantiatedDecl)
        }
        return TypeSubst()
    }

    private func ClearImportedUnusedInstantiatedDecls(): Unit {
        let currentPkg = curPkg.getOrThrow()
        let instantiatedTys = HashSet<Int64>()
        let removedDeclIds = HashSet<Int64>()
        let removedDecls = ArrayList<Decl>()
        for (decl in currentPkg.genericInstantiatedDecls) {
            if (decl.IsNominalDecl()) {
                RestoreInstantiatedDeclTy(decl)
                if (let Some(declTy) <- decl.GetTy()) {
                    instantiatedTys.add(declTy.objectId)
                }
            }
        }
        for (packageDecl in ci.importedPackageDecls) {
            let importPkg = packageDecl.srcPackage
            let ignore = importPkg == currentPkg || !importPkg.TestAttr(Attribute.IMPORTED)
            if (ignore) {
                continue
            }
            for (decl in importPkg.genericInstantiatedDecls) {
                if (let Some(declTy) <- decl.GetTy()) {
                    if (instantiatedTys.contains(declTy.objectId) && !removedDeclIds.contains(decl.objectId)) {
                        removedDeclIds.add(decl.objectId)
                        removedDecls.add(decl)
                    }
                }
            }
            let removedOtherDeclIds = HashSet<Int64>()
            for (decl in importPkg.genericInstantiatedDecls) {
                var outermostDecl = decl.outerDecl
                while (let Some(outerDecl) <- outermostDecl) {
                    if (let Some(nextOuterDecl) <- outerDecl.outerDecl) {
                        outermostDecl = nextOuterDecl
                    } else {
                        break
                    }
                }
                if (let Some(rootDecl) <- outermostDecl) {
                    if (removedDeclIds.contains(rootDecl.objectId)) {
                        removedOtherDeclIds.add(decl.objectId)
                    }
                }
            }
            for (removedDecl in removedDecls) {
                if (let Some(extendDecl) <- (removedDecl as ExtendDecl)) {
                    ci.typeManager.RemoveExtendFromMap(extendDecl)
                }
            }
            var srcImportedIdx: Int64 = 0
            while (srcImportedIdx < importPkg.srcImportedNonGenericDecls.size) {
                let srcImportedDecl = importPkg.srcImportedNonGenericDecls[srcImportedIdx]
                if (let Some(outerDecl) <- srcImportedDecl.outerDecl) {
                    if (removedDeclIds.contains(outerDecl.objectId)) {
                        importPkg.srcImportedNonGenericDecls.remove(at: srcImportedIdx)
                        continue
                    }
                }
                srcImportedIdx++
            }
            var genericIdx: Int64 = 0
            while (genericIdx < importPkg.genericInstantiatedDecls.size) {
                let genericDecl = importPkg.genericInstantiatedDecls[genericIdx]
                if (removedDeclIds.contains(genericDecl.objectId)) {
                    importPkg.genericInstantiatedDecls.remove(at: genericIdx)
                    continue
                }
                genericIdx++
            }
            var innerIdx: Int64 = 0
            while (innerIdx < importPkg.genericInstantiatedDecls.size) {
                let innerDecl = importPkg.genericInstantiatedDecls[innerIdx]
                if (removedOtherDeclIds.contains(innerDecl.objectId)) {
                    importPkg.genericInstantiatedDecls.remove(at: innerIdx)
                    continue
                }
                innerIdx++
            }
            removedDeclIds.clear()
            removedDecls.clear()
        }
        updateInstantiatedExtendMap(ci.typeManager, currentPkg)
    }

    private func IsMacroRelatedPackageName(fullPackageName: String): Bool {
        for (packageDecl in ci.importedPackageDecls) {
            if (packageDecl.srcPackage.fullPackageName == fullPackageName) {
                return packageDecl.srcPackage.isMacroPackage
            }
        }
        for (pkg in ci.sourcePackages) {
            if (pkg.fullPackageName == fullPackageName) {
                return pkg.isMacroPackage
            }
        }
        return false
    }

    public func GetAllGenericToInsDecls(): ArrayList<(Decl, ArrayList<Decl>)> {
        let out = ArrayList<(Decl, ArrayList<Decl>)>()
        for (entry in instantiations) {
            var found = false
            var idx: Int64 = 0
            while (idx < out.size) {
                let (decl, values) = out[idx]
                if (SameDecl(decl, entry.genericDecl)) {
                    if (!containsDecl(values, entry.instantiatedDecl)) {
                        values.add(entry.instantiatedDecl)
                    }
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
        CJC_ASSERT(decl.TestAttr(Attribute.GENERIC))
        let gTyToTyMap = GenerateTypeMapping(decl, instTys)
        CJC_ASSERT(!gTyToTyMap.IsEmpty())
        let genericInfo = GenericInfo(Some(decl), gTyToTyMap)
        return genericInfo
    }

    public func FindInCache(info: GenericInfo): Option<Decl> {
        return FindInCache(info, None)
    }

    private func FindInCache(info: GenericInfo, pkg: Package): Option<Decl> {
        return FindInCache(info, Some(pkg))
    }

    private func FindInCache(info: GenericInfo, pkg: Option<Package>): Option<Decl> {
        if (let Some(genericDecl) <- info.decl) {
            let key = genericInfoKey(genericDecl, info.gTyToTyMap)
            if (let Some(entries) <- declInstantiationByTypeMap.get(key)) {
                for (entry in entries) {
                    if (!SameDecl(entry.genericDecl, genericDecl) || !sameSubst(entry.subst, info.gTyToTyMap)) {
                        continue
                    }
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

    private func hasInstantiation(genericDecl: Decl, instantiatedDecl: Decl, subst: TypeSubst): Bool {
        let key = genericInfoKey(genericDecl, subst)
        if (let Some(entries) <- declInstantiationByTypeMap.get(key)) {
            for (entry in entries) {
                if (SameDecl(entry.genericDecl, genericDecl) && SameDecl(entry.instantiatedDecl, instantiatedDecl) &&
                    sameSubst(entry.subst, subst)) {
                    return true
                }
            }
        }
        return false
    }

    public func InstantiateGenericDecl(decl: Decl, typeMapping: TypeSubst, pkg: Package): Decl {
        if (typeMapping.IsEmpty()) {
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
            let record = GenericInstantiationRecord(genericDecl, instantiatedDecl, subst.Clone())
            instantiations.add(record)
            let infoKey = genericInfoKey(genericDecl, record.subst)
            if (!declInstantiationByTypeMap.contains(infoKey)) {
                declInstantiationByTypeMap[infoKey] = ArrayList<GenericInstantiationRecord>()
            }
            declInstantiationByTypeMap.get(infoKey).getOrThrow().add(record)
            let declKey = genericDecl.objectId
            if (!instantiatedDeclsMap.contains(declKey)) {
                instantiatedDeclsMap[declKey] = ArrayList<Decl>()
            }
            let instantiatedDecls = instantiatedDeclsMap.get(declKey).getOrThrow()
            if (!containsDecl(instantiatedDecls, instantiatedDecl)) {
                instantiatedDecls.add(instantiatedDecl)
            }
        }
    }

    private func collectExistingInstantiation(decl: Decl): Unit {
        if (let Some(genericDecl) <- decl.genericDecl) {
            addInstantiationRecord(genericDecl, decl, buildTypeMappingFromDecl(genericDecl, decl))
            PartialInstantiation.RegisterInstantiation(genericDecl, decl)
        }
        for (member in decl.GetMemberDecls()) {
            collectExistingInstantiation(member)
        }
    }

    private func InstantiateReferencedGenerics(pkg: Package): Unit {
        for (file in pkg.files) {
            InstantiateReferencedGenericsInNode(file, pkg)
        }
    }

    private func InstantiateReferencedGenericsInNode(root: Node, pkg: Package): Unit {
        let walker = Walker(root, instantiationWalkerID, visitPre: { node: Node =>
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
        curTriggerNode = node
        if (let Some(ty) <- node.GetTy()) {
            if (Ty.IsTyCorrect(ty) && !ty.HasIntersectionTy()) {
                InstantiateGenericTysForMemoryLayout(ty, pkg)
                GenericTyExtendInstantiate(ty, pkg)
            }
        }
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

    func PushStructContext(node: Node): Unit {
        if (let Some(decl) <- (node as Decl)) {
            if (NeedSwitchContext(decl)) {
                structContext.add(decl)
            }
        }
    }

    func PopStructContext(node: Node): VisitAction {
        if (let Some(decl) <- (node as Decl)) {
            if (!structContext.isEmpty() && NeedSwitchContext(decl) &&
                SameDecl(structContext[structContext.size - 1], decl)) {
                structContext.remove(at: structContext.size - 1)
            }
        }
        return VisitAction.KEEP_DECISION
    }

    func GetStructDeclByContext(): Option<Decl> {
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

    private func GenericTyExtendInstantiate(ty: Ty, pkg: Package): Unit {
        if (ty.HasGeneric()) {
            return
        }
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(ty)) {
            InstantiateGenericDeclWithInstTys(decl, copyTypeArgs(Some(ty)), pkg)
        }
        let extends = ArrayList<ExtendDecl>()
        for (extendDecl in ci.typeManager.GetTyUsedExtends(ty)) {
            extends.add(extendDecl)
        }
        if (extends.isEmpty()) {
            return
        }
        for (extendDecl in extends) {
            if (!RequireInstantiation(extendDecl)) {
                continue
            }
            let extendTy = GetDeclTy(extendDecl).getOrThrow()
            let promotedTys = promotion.Promote(ty, extendTy)
            CJC_ASSERT(!promotedTys.IsEmpty())
            if (!ci.typeManager.CheckExtendWithConstraint(ty, Some(extendDecl))) {
                continue
            }
            InstantiateGenericDeclWithInstTys(extendDecl,
                ci.typeManager.GetTypeArgs(promotedTys.values[0]), pkg)
        }
    }

    private func InstantiateGenericTysForMemoryLayout(ty: Ty, pkg: Package): Unit {
        if (ty.HasGeneric()) {
            return
        }
        for (arg in ty.typeArgs) {
            if (!arg.typeArgs.isEmpty()) {
                InstantiateGenericTysForMemoryLayout(arg, pkg)
            }
        }
        if (let Some(decl) <- Ty.GetInheritableDeclPtrOfTy(ty)) {
            InstantiateGenericDeclWithInstTys(decl, copyTypeArgs(Some(ty)), pkg)
        }
    }

    private func GenericRefExprInstantiate(refExpr: RefExpr, pkg: Package): Unit {
        WalkNameReferenceTypeArguments(refExpr, pkg)
        if (let Some(target) <- refExpr.GetTarget()) {
            if (target.astKind == ASTKind.GENERIC_PARAM_DECL || target.astKind == ASTKind.PACKAGE_DECL ||
                !Ty.IsTyCorrect(refExpr.GetTy())) {
                return
            }
            var targetDecl = GetRealTarget(target)
            if (targetDecl.IsBuiltIn() || !RequireInstantiation(targetDecl)) {
                return
            }
            let instTys = ArrayList<Ty>()
            for (ty in refExpr.instTys) {
                instTys.add(ty)
            }
            if (IsClassOrEnumConstructor(targetDecl)) {
                targetDecl = target.outerDecl.getOrThrow()
                instTys.clear()
                if (let Some(refTy) <- refExpr.GetTy()) {
                    let constructorBaseTy =
                        if (let Some(funcTy) <- (refTy as FuncTy)) { funcTy.retTy } else { refTy }
                    for (arg in constructorBaseTy.typeArgs) {
                        instTys.add(arg)
                    }
                }
            }
            let needInstantiateParent = if (let Some(outerDecl) <- targetDecl.outerDecl) {
                outerDecl.IsNominalDecl() &&
                    (IsGenericInGenericStruct(targetDecl) || outerDecl.TestAttr(Attribute.GENERIC))
            } else {
                false
            }
            let structDecl = if (structContext.isEmpty()) { targetDecl.outerDecl } else { GetStructDeclByContext() }
            var baseTy: Option<Ty> = None
            if (!SameDeclOptions(structDecl, targetDecl.outerDecl)) {
                baseTy = GetDeclTy(structDecl.getOrThrow())
            }
            if (needInstantiateParent) {
                if (let Some(baseTyValue) <- baseTy) {
                    targetDecl = GetInstantiatedMemberTarget(baseTyValue, targetDecl)
                }
            }
            InstantiateGenericDeclWithInstTys(targetDecl, instTys, pkg)
            if (let Some(baseTyValue) <- baseTy) {
                if (let Some(funcDecl) <- (targetDecl as FuncDecl)) {
                    if (targetDecl.TestAttr(Attribute.GENERIC)) {
                        targetDecl = FindImplFuncForAbstractFunc(baseTyValue, funcDecl, baseTyValue)
                        InstantiateGenericDeclWithInstTys(targetDecl, instTys, pkg)
                    }
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
            if (target.astKind == ASTKind.PACKAGE_DECL || !Ty.IsTyCorrect(memberAccess.GetTy()) ||
                RealTestManager.IsMockAccessor(target)) {
                return
            }
            if (let None <- memberAccess.baseExpr) {
                return
            }
            var targetDecl = GetRealTarget(target)
            if (targetDecl.IsBuiltIn() || !RequireInstantiation(targetDecl)) {
                return
            }
            let instTys = ArrayList<Ty>()
            for (ty in memberAccess.instTys) {
                instTys.add(ty)
            }
            if (IsClassOrEnumConstructor(targetDecl)) {
                targetDecl = targetDecl.outerDecl.getOrThrow()
                instTys.clear()
                if (let Some(memberTy) <- memberAccess.GetTy()) {
                    let constructorBaseTy =
                        if (let Some(funcTy) <- (memberTy as FuncTy)) { funcTy.retTy } else { memberTy }
                    for (arg in constructorBaseTy.typeArgs) {
                        instTys.add(arg)
                    }
                }
            }
            let needInstantiateParent = if (let Some(outerDecl) <- targetDecl.outerDecl) {
                outerDecl.IsNominalDecl() && memberAccess.baseExpr.getOrThrow().GetTy().isSome() &&
                    (IsGenericInGenericStruct(targetDecl) || outerDecl.TestAttr(Attribute.GENERIC))
            } else {
                false
            }
            if (needInstantiateParent) {
                let memberBaseTy = if (Ty.IsTyCorrect(memberAccess.matchedParentTy)) {
                    memberAccess.matchedParentTy.getOrThrow()
                } else {
                    memberAccess.baseExpr.getOrThrow().GetTy().getOrThrow()
                }
                targetDecl = GetInstantiatedMemberTarget(memberBaseTy, targetDecl)
            }
            InstantiateGenericDeclWithInstTys(targetDecl, instTys, pkg)
            let baseExprTy = memberAccess.baseExpr.getOrThrow().GetTy()
            if (!Ty.IsTyCorrect(baseExprTy)) {
                return
            }
            if (let Some(funcDecl) <- (targetDecl as FuncDecl)) {
                if (targetDecl.TestAttr(Attribute.GENERIC)) {
                    targetDecl = FindImplFuncForAbstractFunc(baseExprTy.getOrThrow(), funcDecl,
                        baseExprTy.getOrThrow())
                    InstantiateGenericDeclWithInstTys(targetDecl, instTys, pkg)
                } else if (!IsInDeclWithAttribute(targetDecl, Attribute.GENERIC) && memberAccess.isExposedAccess) {
                    targetDecl = FindImplFuncForAbstractFunc(baseExprTy.getOrThrow(), funcDecl,
                        baseExprTy.getOrThrow())
                    InstantiateGenericDeclWithInstTys(targetDecl, instTys, pkg)
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

    private func MarkAndInstantiateSrcImportedDecl(keyDecl: Decl, rootDecl: Decl, pkg: Package): Unit {
        if (containsDecl(usedSrcImportedDecls, keyDecl)) {
            return
        }
        usedSrcImportedDecls.add(keyDecl)
        InstantiateReferencedGenericsInNode(rootDecl, pkg)
    }

    private func InstantiateSrcImportedDefaultParamDecls(decl: Decl, pkg: Package): Unit {
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (let Some(body) <- funcDecl.funcBody) {
                if (!body.paramLists.isEmpty()) {
                    for (param in body.paramLists[0].params) {
                        if (let Some(desugarDecl) <- param.desugarDecl) {
                            if (desugarDecl.TestAttr(Attribute.SRC_IMPORTED)) {
                                MarkAndInstantiateSrcImportedDecl(desugarDecl, desugarDecl, pkg)
                            }
                        }
                    }
                }
            }
        }
    }

    private func InstantiateGenericDeclWithInstTys(decl: Decl, instTys: ArrayList<Ty>, pkg: Package): Unit {
        let generalDecl = GetGeneralDecl(decl)
        if (ignoredInstantiationKind(generalDecl)) {
            return
        }
        if ((let None <- generalDecl.GetGeneric()) || !RequireInstantiation(generalDecl)) {
            if (!decl.TestAnyAttr(Attribute.IMPORTED, Attribute.GENERATED_TO_MOCK)) {
                return
            }
            InstantiateSrcImportedDefaultParamDecls(generalDecl, pkg)
            if (generalDecl.TestAttr(Attribute.SRC_IMPORTED)) {
                MarkAndInstantiateSrcImportedDecl(generalDecl, decl, pkg)
            }
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
            if (decl.IsConst() || containsDecl(usedSrcImportedDecls, decl)) {
                RearrangeReferencesInNode(decl, pkg)
            }
        }
    }

    private func RearrangeReferencesInNode(root: Node, pkg: Package): Unit {
        let walker = Walker(root, rearrangeWalkerID, visitPre: { node: Node =>
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
        curTriggerNode = node
        if (let Some(callExpr) <- (node as CallExpr)) {
            RearrangeCallExprReference(callExpr, pkg)
        } else if (let Some(refExpr) <- (node as RefExpr)) {
            RearrangeRefExprReference(refExpr)
        } else if (let Some(memberAccess) <- (node as MemberAccess)) {
            RearrangeMemberAccessReference(memberAccess, pkg)
        } else if (let Some(typeNode) <- (node as Type)) {
            RearrangeTypeReference(typeNode)
            if (typeNode.astKind == ASTKind.REF_TYPE || typeNode.astKind == ASTKind.QUALIFIED_TYPE) {
                return VisitAction.SKIP_CHILDREN
            }
        } else if (let Some(arrayExpr) <- (node as ArrayExpr)) {
            RearrangeArrayExprReference(arrayExpr)
        } else if (let Some(arrayLit) <- (node as ArrayLit)) {
            RearrangeArrayLitReference(arrayLit)
        } else if (let Some(funcBody) <- (node as FuncBody)) {
            RearrangeFuncBodyReference(funcBody)
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

    private func GetInstantiatedTarget(baseTy: Ty, target: Decl, instTys: ArrayList<Ty>,
        upperTy: Option<Ty>): Decl {
        let genericDecl = GetGeneralDecl(target)
        if (genericDecl.IsBuiltIn()) {
            return target
        }
        if (genericDecl.IsNominalDecl() || (let None <- genericDecl.outerDecl) ||
            !genericDecl.outerDecl.getOrThrow().IsNominalDecl()) {
            if ((let None <- genericDecl.GetGeneric()) || !genericDecl.TestAttr(Attribute.GENERIC)) {
                return genericDecl
            }
            if (let Some(instantiatedDecl) <- FindInCache(ConstructGenericInfo(genericDecl, instTys))) {
                return instantiatedDecl
            }
            return target
        }
        let targetBase = if (Ty.IsTyCorrect(upperTy) && !upperTy.getOrThrow().HasGeneric()) {
            upperTy.getOrThrow()
        } else {
            baseTy
        }
        let instantiatedMember = GetInstantiatedMemberTarget(targetBase, genericDecl, inRearrange: true)
        var decl: Option<Decl> = if (instantiatedMember.TestAttr(Attribute.GENERIC)) {
            FindInCache(ConstructGenericInfo(instantiatedMember, instTys))
        } else {
            Some(instantiatedMember)
        }
        if (let Some(declValue) <- decl) {
            if (let Some(funcDecl) <- (declValue as FuncDecl)) {
                let implDecl = FindImplFuncForAbstractFunc(baseTy, funcDecl, targetBase)
                if (implDecl.TestAttr(Attribute.GENERIC)) {
                    decl = FindInCache(ConstructGenericInfo(implDecl, instTys))
                } else {
                    decl = implDecl
                }
            }
        }
        if (let Some(declValue) <- decl) {
            return declValue
        }
        return target
    }

    private func RearrangeRefExprReference(refExpr: RefExpr): Unit {
        if (!Ty.IsTyCorrect(refExpr.GetTy())) {
            return
        }
        if (let Some(target) <- refExpr.GetTarget()) {
            if (ignoredInstantiationKind(target) || !RequireInstantiation(target)) {
                return
            }
            var baseTy = refExpr.GetTy()
            let instTys = ArrayList<Ty>()
            if (refExpr.isThis || refExpr.isSuper) {
                for (arg in copyTypeArgs(baseTy)) {
                    instTys.add(arg)
                }
            } else {
                for (arg in refExpr.instTys) {
                    instTys.add(arg)
                }
            }
            if (IsClassOrEnumConstructor(target)) {
                if (let Some(currentBaseTy) <- baseTy) {
                    baseTy = if (let Some(funcTy) <- (currentBaseTy as FuncTy)) { Some(funcTy.retTy) } else { baseTy }
                    instTys.clear()
                    for (arg in baseTy.getOrThrow().typeArgs) {
                        instTys.add(arg)
                    }
                }
            } else if (!structContext.isEmpty()) {
                if (let Some(structDecl) <- GetStructDeclByContext()) {
                    baseTy = GetDeclTy(structDecl)
                }
            }
            refExpr.ref.target = GetInstantiatedTarget(baseTy.getOrThrow(), target, instTys,
                refExpr.matchedParentTy)
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
            var baseTy = GetMemberBaseTy(memberAccess)
            let instTys = ArrayList<Ty>()
            for (arg in memberAccess.instTys) {
                instTys.add(arg)
            }
            if (IsClassOrEnumConstructor(target)) {
                if (let Some(currentBaseTy) <- baseTy) {
                    baseTy = if (let Some(funcTy) <- (currentBaseTy as FuncTy)) { Some(funcTy.retTy) } else { baseTy }
                    instTys.clear()
                    for (arg in baseTy.getOrThrow().typeArgs) {
                        instTys.add(arg)
                    }
                }
            }
            memberAccess.target = GetInstantiatedTarget(baseTy.getOrThrow(), target, instTys,
                memberAccess.matchedParentTy)
            ClearInstTysIfNeeded(memberAccess)
        }
    }

    private func RearrangeTypeReference(typeNode: Type): Unit {
        if (!Ty.IsTyCorrect(typeNode.GetTy())) {
            return
        }
        if (let Some(typeTy) <- typeNode.GetTy()) {
            if (typeTy.HasGeneric() || typeTy.HasIntersectionTy()) {
                return
            }
            if (let Some(target) <- Ty.GetDeclPtrOfTy(typeTy)) {
                let instantiatedDecl = GetInstantiatedTarget(typeTy, target, copyTypeArgs(Some(typeTy)), None)
                if (let Some(refType) <- (typeNode as RefType)) {
                    refType.ref.target = instantiatedDecl
                } else if (let Some(qualifiedType) <- (typeNode as QualifiedType)) {
                    qualifiedType.target = instantiatedDecl
                }
            }
        }
    }

    private func RearrangeArrayExprReference(arrayExpr: ArrayExpr): Unit {
        if (let Some(initFunc) <- arrayExpr.initFunc) {
            if (let Some(arrayTy) <- arrayExpr.GetTy()) {
                if (Ty.IsTyCorrect(arrayTy)) {
                    if (let Some(target) <- FindInCache(ConstructGenericInfo(initFunc,
                        ci.typeManager.GetTypeArgs(arrayTy)))) {
                        arrayExpr.initFunc = (target as FuncDecl).getOrThrow()
                    }
                }
            }
        }
    }

    private func RearrangeArrayLitReference(arrayLit: ArrayLit): Unit {
        if (let Some(initFunc) <- arrayLit.initFunc) {
            if (let Some(arrayTy) <- arrayLit.GetTy()) {
                if (let Some(target) <- (GetInstantiatedTarget(arrayTy, initFunc, arrayTy.typeArgs, None) as FuncDecl)) {
                    arrayLit.initFunc = target
                }
            }
        }
    }

    private func RearrangeFuncBodyReference(funcBody: FuncBody): Unit {
        if (structContext.isEmpty()) {
            return
        }
        let contextDecl = GetStructDeclByContext().getOrThrow()
        let baseTy = GetDeclTy(contextDecl).getOrThrow()
        if (let Some(parentClassLike) <- funcBody.parentClassLike) {
            funcBody.parentClassLike =
                (GetInstantiatedTarget(baseTy, parentClassLike, baseTy.typeArgs, None) as ClassLikeDecl).getOrThrow()
        } else if (let Some(parentStruct) <- funcBody.parentStruct) {
            funcBody.parentStruct =
                (GetInstantiatedTarget(baseTy, parentStruct, baseTy.typeArgs, None) as StructDecl).getOrThrow()
        } else if (let Some(parentEnum) <- funcBody.parentEnum) {
            funcBody.parentEnum =
                (GetInstantiatedTarget(baseTy, parentEnum, baseTy.typeArgs, None) as EnumDecl).getOrThrow()
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

}
