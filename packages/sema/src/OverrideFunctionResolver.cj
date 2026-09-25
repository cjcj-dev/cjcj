package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::utils.CJC_ASSERT

// Upstream 2e110911, OverrideFunctionResolver.h:25-26. Ptr preserves object identity.
public type MemberFuncsWithInstTys = HashMap<FuncDecl, HashSet<Ptr<FuncTy>>>
public type MemberFuncWithInstTys = (FuncDecl, HashSet<Ptr<FuncTy>>)

// A tuple is not Hashable in Cangjie; retain the upstream pair's two fields.
struct ResolverCacheKey <: Hashable & Equatable<ResolverCacheKey> {
    let typeId: Int64
    let identifier: String
    init(typeId: Int64, identifier: String) {
        this.typeId = typeId
        this.identifier = identifier
    }
    public operator func ==(right: ResolverCacheKey): Bool {
        return typeId == right.typeId && identifier == right.identifier
    }
    public operator func !=(right: ResolverCacheKey): Bool { return !(this == right) }
    public func hashCode(): Int64 { return typeId.hashCode() ^ identifier.hashCode() }
}

public class OverrideFunctionResolver {
    private let typeManager: TypeManager
    static let instTy2MembersCache = HashMap<ResolverCacheKey, MemberFuncsWithInstTys>()

    public init(typeManager: TypeManager) {
        this.typeManager = typeManager
    }

    // C++ containers have value semantics; detach both map and sets at the cache boundary.
    private func CopyFuncs(funcs: MemberFuncsWithInstTys): MemberFuncsWithInstTys {
        let copied = MemberFuncsWithInstTys()
        for ((fd, tys) in funcs) {
            copied[fd] = HashSet<Ptr<FuncTy>>(tys)
        }
        return copied
    }

    public func GetInstMemberFuncWithInstTy(instBaseTy: Ty, identifier: String): MemberFuncsWithInstTys {
        let key = ResolverCacheKey(instBaseTy.objectId, identifier)
        if (let Some(found) <- instTy2MembersCache.get(key)) {
            return CopyFuncs(found)
        }
        let funcs = MemberFuncsWithInstTys()
        let baseDecl = Ty.GetInheritableDeclPtrOfTy(Some(instBaseTy))
        let extendDecls = TreeSet<ExtendDecl>()
        if (let Some(base) <- baseDecl) {
            let superInterfaceFuncs = MemberFuncsWithInstTys()
            GetInstMemberFromSuper(instBaseTy, base, superInterfaceFuncs, identifier, true)
            GetInstMemberFromSuper(instBaseTy, base, funcs, identifier, false)
            MergeIntoFuncs(funcs, superInterfaceFuncs)
            CollectDeclMemberFunc(base, instBaseTy, funcs, identifier)
            for (ed in typeManager.GetDeclExtends(base)) {
                extendDecls.add(ed)
            }
        } else {
            for (ed in typeManager.GetAllExtendsByTy(instBaseTy)) {
                extendDecls.add(ed)
            }
        }
        let allExtendFuncs = MemberFuncsWithInstTys()
        for (entry in extendDecls) {
            let ed = entry
            if (ed.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                continue
            }
            let extendFuncs = MemberFuncsWithInstTys()
            GetInstMemberFromSuper(instBaseTy, ed, extendFuncs, identifier, true)
            MergeExtendSuperMember(instBaseTy, allExtendFuncs, extendFuncs)
            CollectDeclMemberFunc(ed, instBaseTy, allExtendFuncs, identifier)
        }
        MergeIntoFuncs(funcs, allExtendFuncs)
        instTy2MembersCache[key] = CopyFuncs(funcs)
        return funcs
    }

    private func CollectDeclMemberFunc(decl: Decl, instBaseTy: Ty, funcs: MemberFuncsWithInstTys,
        identifier: String): Unit {
        let mapping = GenerateTypeMappingByTy(decl.GetTy(), Some(instBaseTy))
        for (member in decl.GetMemberDecls()) {
            WorkForMembers(member, { m: Decl =>
                if (m.identifier.Val() != identifier || m.astKind != ASTKind.FUNC_DECL ||
                    m.TestAttr(Attribute.ABSTRACT)) {
                    return
                }
                let memberFunc = (m as FuncDecl).getOrThrow()
                let instTy = typeManager.GetInstantiatedTy(memberFunc.GetTy().getOrThrow(), mapping)
                CJC_ASSERT(instTy.IsFunc())
                let instMemberFuncTy = (instTy as FuncTy).getOrThrow()
                RemoveImplementedSupers(memberFunc, instMemberFuncTy, funcs)
                AddInstTyToFuncs(memberFunc, instMemberFuncTy, funcs)
            })
        }
    }

    private func GetInstMemberFromSuper(instBaseTy: Ty, baseDecl: InheritableDecl,
        funcs: MemberFuncsWithInstTys, identifier: String, isCheckingInterface: Bool): Unit {
        for (typeNode in baseDecl.inheritedTypes) {
            let ty = typeNode.GetTy().getOrThrow()
            let notSkipSuper = if (isCheckingInterface) { ty.IsInterface() } else { ty.IsClass() }
            if (!notSkipSuper) {
                continue
            }
            let superFuncs = GetInstMemberFuncWithInstTy(ty, identifier)
            MergeIntoFuncs(funcs, superFuncs)
        }
        let mapping = GenerateTypeMappingByTy(baseDecl.GetTy(), Some(instBaseTy))
        for ((fd, tys) in funcs) {
            let newTySet = HashSet<Ptr<FuncTy>>()
            for (superTy in tys) {
                let instTy = typeManager.GetInstantiatedTy(superTy.value, mapping)
                CJC_ASSERT(instTy.IsFunc())
                newTySet.add(Ptr<FuncTy>((instTy as FuncTy).getOrThrow()))
            }
            funcs[fd] = newTySet
        }
    }

    private func MergeExtendSuperMember(instBaseTy: Ty, funcs: MemberFuncsWithInstTys,
        newFuncs: MemberFuncsWithInstTys): Unit {
        for ((fd, tys) in newFuncs) {
            let outerTys = Promotion(typeManager).Promote(instBaseTy, fd.outerDecl.getOrThrow().GetTy().getOrThrow())
            for (ty in tys) {
                if (IsImplementedInSameDirection(instBaseTy, fd, ty.value, outerTys, funcs)) {
                    continue
                }
                AddInstTyToFuncs(fd, ty.value, funcs)
            }
        }
    }

    private func MergeIntoFuncs(funcs: MemberFuncsWithInstTys, newFuncs: MemberFuncsWithInstTys): Unit {
        for ((fd, tys) in newFuncs) {
            for (ty in tys) {
                if (IsImplementedByAny(fd, ty.value, funcs)) {
                    continue
                }
                AddInstTyToFuncs(fd, ty.value, funcs)
            }
        }
    }

    private func RemoveImplementedSupers(memberFunc: FuncDecl, instMemberFuncTy: FuncTy,
        funcs: MemberFuncsWithInstTys): Unit {
        // Snapshot keys permits erase while iterating, as C++ erase(iterator) does.
        for (fd in ArrayList<FuncDecl>(funcs.keys())) {
            let tys = funcs.get(fd).getOrThrow()
            for (ty in ArrayList<Ptr<FuncTy>>(tys)) {
                if (IsImplementationFunc(memberFunc, fd, instMemberFuncTy, ty.value)) {
                    tys.remove(ty)
                }
            }
            if (tys.isEmpty()) {
                funcs.remove(fd)
            }
        }
    }

    private func IsImplementedByAny(newFunc: FuncDecl, newFuncInstTy: FuncTy,
        funcs: MemberFuncsWithInstTys): Bool {
        for ((fd, tys) in funcs) {
            for (ty in tys) {
                if (IsImplementationFunc(fd, newFunc, ty.value, newFuncInstTy)) {
                    return true
                }
            }
        }
        return false
    }

    private func IsImplementedInSameDirection(instBaseTy: Ty, newFunc: FuncDecl, newFuncInstTy: FuncTy,
        newFuncOuterDeclInstTys: TySet, funcs: MemberFuncsWithInstTys): Bool {
        for ((fd, tys) in funcs) {
            var isImplRelation = false
            for (ty in tys) {
                if (IsImplementationFunc(fd, newFunc, ty.value, newFuncInstTy)) {
                    isImplRelation = true
                    break
                }
            }
            if (!isImplRelation) {
                continue
            }
            let outerTys = Promotion(typeManager).Promote(instBaseTy, fd.outerDecl.getOrThrow().GetTy().getOrThrow())
            for (root in newFuncOuterDeclInstTys.values) {
                for (leaf in outerTys.values) {
                    if (typeManager.IsSubtype(leaf, root)) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func AddInstTyToFuncs(funcDecl: FuncDecl, instTy: FuncTy, funcs: MemberFuncsWithInstTys): Unit {
        let key = funcDecl
        if (let Some(tys) <- funcs.get(key)) {
            tys.add(Ptr<FuncTy>(instTy))
        } else {
            let tys = HashSet<Ptr<FuncTy>>()
            tys.add(Ptr<FuncTy>(instTy))
            funcs[key] = tys
        }
    }

    private func IsImplementationFunc(srcFunc: FuncDecl, superFunc: FuncDecl,
        srcInstFuncTy: FuncTy, superInstFuncTy: FuncTy): Bool {
        CJC_ASSERT(srcFunc.outerDecl.isSome() && superFunc.outerDecl.isSome())
        if (!IsVirtualMember(superFunc)) {
            return false
        }
        let noRelation = srcFunc.TestAttr(Attribute.STATIC) != superFunc.TestAttr(Attribute.STATIC) ||
            srcFunc.TestAttr(Attribute.GENERIC) != superFunc.TestAttr(Attribute.GENERIC) ||
            srcFunc.identifier != superFunc.identifier
        if (noRelation) {
            return false
        }
        if (srcFunc.TestAttr(Attribute.GENERIC) && superFunc.TestAttr(Attribute.GENERIC)) {
            let mapping = typeManager.GenerateGenericMappingFromGeneric(srcFunc, superFunc)
            let subst = typeManager.GetInstantiatedTy(srcInstFuncTy, mapping)
            CJC_ASSERT(subst.IsFunc())
            return typeManager.IsFuncTySubType((subst as FuncTy).getOrThrow(), superInstFuncTy)
        }
        return typeManager.IsFuncTySubType(srcInstFuncTy, superInstFuncTy)
    }

    public static func ClearCache(): Unit {
        instTy2MembersCache.clear()
    }

    public func GetMatchedFuncInstTyByGivenTarget(candidates: MemberFuncWithInstTys,
        target: FuncDecl, targetBaseTy: Ty): Ty {
        let implFunc = candidates[0]
        let typeMappings = Promotion(typeManager).GetPromoteTypeMapping(
            targetBaseTy, target.outerDecl.getOrThrow().GetTy().getOrThrow())
        let instFuncTys = typeManager.GetInstantiatedTys(target.GetTy().getOrThrow(), typeMappings)
        var matchedTy: Ty = TypeManager.GetInvalidTy()
        for (entry in candidates[1]) {
            let instTy = entry.value
            var substImplFuncTy: Ty = instTy
            if (implFunc.TestAttr(Attribute.GENERIC) && target.TestAttr(Attribute.GENERIC)) {
                let mapping = typeManager.GenerateGenericMappingFromGeneric(implFunc, target)
                substImplFuncTy = typeManager.GetInstantiatedTy(instTy, mapping)
                CJC_ASSERT(substImplFuncTy.IsFunc())
            }
            for (instFuncTy in instFuncTys.values) {
                if (typeManager.IsFuncTySubType((substImplFuncTy as FuncTy).getOrThrow(),
                    (instFuncTy as FuncTy).getOrThrow())) {
                    matchedTy = instTy
                    break
                }
            }
            if (Ty.IsTyCorrect(matchedTy)) {
                break
            }
        }
        return matchedTy
    }
}
