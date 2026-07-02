package cangjie_compiler::sema

import std.collection.*
import cangjie_compiler::ast.*
import cangjie_compiler::basic.DiagnosticEngine as BasicDiagnosticEngine
import cangjie_compiler::option.GlobalOptions as OptionGlobalOptions
import cangjie_compiler::utils.CORE_PACKAGE_NAME as UTILS_CORE_PACKAGE_NAME

public class CompilerInstance {
    public var typeManager: TypeManager = TypeManager()
    public var globalOptions: OptionGlobalOptions = OptionGlobalOptions()
    public var frontendDumpActionIsTypeCheck: Bool = false
    public var diag: Option<BasicDiagnosticEngine> = None
    public let sourcePackages: ArrayList<Package> = ArrayList<Package>()
    public let packageDecls: ArrayList<PackageDecl> = ArrayList<PackageDecl>()
    public let resolvedImportedDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    public let resolvedPackageMemberDeclsMap: HashMap<String, HashMap<String, ArrayList<Decl>>> =
        HashMap<String, HashMap<String, ArrayList<Decl>>>()
    public let resolvedImplicitPackageMemberDeclsMap: HashMap<String, HashMap<String, Decl>> =
        HashMap<String, HashMap<String, Decl>>()
    public init() {}

    public func AddResolvedImportedDecls(fileHash: UInt64, name: String, decls: ArrayList<Decl>): Unit {
        if (!resolvedImportedDeclsMap.contains(fileHash)) {
            resolvedImportedDeclsMap[fileHash] = HashMap<String, ArrayList<Decl>>()
        }
        if (let Some(fileMap) <- resolvedImportedDeclsMap.get(fileHash)) {
            AddDeclsToNamedMap(fileMap, name, decls)
        }
        typeManager.AddResolvedImportedDecls(fileHash, name, decls)
    }

    public func AddResolvedPackageMemberDecls(packageName: String, name: String, decls: ArrayList<Decl>): Unit {
        if (!resolvedPackageMemberDeclsMap.contains(packageName)) {
            resolvedPackageMemberDeclsMap[packageName] = HashMap<String, ArrayList<Decl>>()
        }
        if (let Some(packageMap) <- resolvedPackageMemberDeclsMap.get(packageName)) {
            AddDeclsToNamedMap(packageMap, name, decls)
        }
    }

    public func AddResolvedImplicitPackageMemberDecl(packageName: String, name: String, decl: Decl): Unit {
        if (!resolvedImplicitPackageMemberDeclsMap.contains(packageName)) {
            resolvedImplicitPackageMemberDeclsMap[packageName] = HashMap<String, Decl>()
        }
        if (let Some(packageMap) <- resolvedImplicitPackageMemberDeclsMap.get(packageName)) {
            packageMap[name] = decl
        }
    }

    private func AddDeclsToNamedMap(map: HashMap<String, ArrayList<Decl>>, name: String,
        decls: ArrayList<Decl>): Unit {
        if (!map.contains(name)) {
            map[name] = ArrayList<Decl>()
        }
        if (let Some(values) <- map.get(name)) {
            for (decl in decls) {
                AddDeclIfMissing(values, decl)
            }
        }
    }

    private func AddDeclIfMissing(values: ArrayList<Decl>, decl: Decl): Unit {
        for (value in values) {
            if (SameImportedAwareDecl(value, decl)) {
                return
            }
        }
        values.add(decl)
    }

    private func SameImportedAwareDecl(left: Decl, right: Decl): Bool {
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
}

public func GetImportedDecl(ctx: ASTContext, fullPackageName: String, name: String): Option<Decl> {
    if (let Some(packageMap) <- ctx.resolvedPackageMemberDeclsMap.get(fullPackageName)) {
        if (let Some(decls) <- packageMap.get(name)) {
            if (!decls.isEmpty()) {
                return Some(decls[0])
            }
        }
    }
    if (let Some(implicitPackageMap) <- ctx.resolvedImplicitPackageMemberDeclsMap.get(fullPackageName)) {
        return implicitPackageMap.get(name)
    }
    return None
}

public func GetCoreDecl(ctx: ASTContext, name: String): Option<Decl> {
    return GetImportedDecl(ctx, UTILS_CORE_PACKAGE_NAME, name)
}

public class GenericInfo {
    public var decl: Option<Decl>
    public var gTyToTyMap: TypeSubst

    public init(decl: Option<Decl>, map: TypeSubst) {
        this.decl = decl
        gTyToTyMap = map
    }
}

private class GenericDeclInstantiation {
    public var genericDecl: Decl
    public var instantiatedDecl: Decl
    public var subst: TypeSubst

    public init(genericDecl: Decl, instantiatedDecl: Decl, subst: TypeSubst) {
        this.genericDecl = genericDecl
        this.instantiatedDecl = instantiatedDecl
        this.subst = subst
    }
}

public class GenericInstantiationManager {
    private var ci: Option<CompilerInstance> = None
    private let instantiations: ArrayList<GenericDeclInstantiation> = ArrayList<GenericDeclInstantiation>()

    public init(ci: CompilerInstance) {
        this.ci = ci
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
    }

    public func GetInstantiatedDeclWithGenericInfo(genericInfo: GenericInfo, pkg: Package): Option<Decl> {
        let _ = pkg
        if (let Some(decl) <- genericInfo.decl) {
            for (entry in instantiations) {
                if (SameDecl(entry.genericDecl, decl) && sameSubst(entry.subst, genericInfo.gTyToTyMap)) {
                    return entry.instantiatedDecl
                }
            }
            collectIdentityInstantiation(decl)
            return decl
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

    private func collectIdentityInstantiation(decl: Decl): Unit {
        if (let Some(_) <- decl.GetGeneric()) {
            if (!hasInstantiation(decl, decl, TypeSubst())) {
                instantiations.add(GenericDeclInstantiation(decl, decl, TypeSubst()))
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
}
