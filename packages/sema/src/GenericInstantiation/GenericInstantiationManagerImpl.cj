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

public class GenericInstantiationManagerImpl {
    private var ci: CompilerInstance
    private var context: GenericInstantiationContext
    private let instantiations: ArrayList<GenericInstantiationRecord> = ArrayList<GenericInstantiationRecord>()

    public init(ci: CompilerInstance) {
        this.ci = ci
        context = GenericInstantiationContext(ci.typeManager)
    }

    public func GenericInstantiatePackage(pkg: Package, resetGlobalState!: Bool = true): Unit {
        if (resetGlobalState) {
            ResetGenericInstantiationStage()
        }
        for (file in pkg.files) {
            for (decl in file.decls) {
                collectIdentityInstantiation(decl)
            }
        }
        for (decl in pkg.genericInstantiatedDecls) {
            collectIdentityInstantiation(decl)
        }
    }

    public func GetInstantiatedDeclWithGenericInfo(genericInfo: GenericInfo, pkg: Package): Option<Decl> {
        let _ = pkg
        if (let Some(cached) <- FindInCache(genericInfo)) {
            return cached
        }
        if (let Some(genericDecl) <- genericInfo.decl) {
            let instantiatedDecl = InstantiateGenericDecl(genericDecl, genericInfo.gTyToTyMap)
            instantiations.add(GenericInstantiationRecord(genericDecl, instantiatedDecl, genericInfo.gTyToTyMap.Clone()))
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
        if (let Some(genericDecl) <- info.decl) {
            for (entry in instantiations) {
                if (SameDecl(entry.genericDecl, genericDecl) && sameSubst(entry.subst, info.gTyToTyMap)) {
                    return entry.instantiatedDecl
                }
            }
        }
        return None
    }

    public func InstantiateGenericDecl(decl: Decl, typeMapping: TypeSubst): Decl {
        if (typeMapping.IsEmpty()) {
            collectIdentityInstantiation(decl)
            return decl
        }
        let cloned = PartialInstantiation.Instantiate(decl, { source: Node, target: Node =>
            if (let Some(sourceTy) <- source.GetTy()) {
                target.SetTy(ci.typeManager.GetInstantiatedTy(sourceTy, typeMapping))
            }
        })
        if (let Some(clonedDecl) <- (cloned as Decl)) {
            clonedDecl.EnableAttr(Attribute.GENERIC_INSTANTIATED)
            clonedDecl.genericDecl = decl
            PartialInstantiation.RegisterInstantiation(decl, clonedDecl)
            return clonedDecl
        }
        return decl
    }

    private func collectIdentityInstantiation(decl: Decl): Unit {
        if (let Some(_) <- decl.GetGeneric()) {
            if (!hasInstantiation(decl, decl, TypeSubst())) {
                instantiations.add(GenericInstantiationRecord(decl, decl, TypeSubst()))
                PartialInstantiation.RegisterInstantiation(decl, decl)
            }
        }
        for (member in decl.GetMemberDecls()) {
            collectIdentityInstantiation(member)
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
