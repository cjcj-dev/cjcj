package cjcj::sema

import std.collection.*
import cjcj::ast.*
import cjcj::basic.DiagnosticEngine as BasicDiagnosticEngine
import cjcj::incremental_compilation.IncreKind
import cjcj::incremental_compilation.SemanticInfo
import cjcj::modules.SemaImportManager
import cjcj::option.GlobalOptions as OptionGlobalOptions
import cjcj::utils.CORE_PACKAGE_NAME as UTILS_CORE_PACKAGE_NAME

// C++ include/cangjie/Frontend/CompileStrategy.h:28-32.
public enum StrategyType {
    | DEFAULT
    | FULL_COMPILE
    | INCREMENTAL_COMPILE
}

private func StrategyTypeIndex(kind: StrategyType): Int64 {
    return match (kind) {
        case StrategyType.DEFAULT => 0
        case StrategyType.FULL_COMPILE => 1
        case StrategyType.INCREMENTAL_COMPILE => 2
    }
}

extend StrategyType <: Equatable<StrategyType> {
    public operator func ==(rhs: StrategyType): Bool {
        return StrategyTypeIndex(this) == StrategyTypeIndex(rhs)
    }

    public operator func !=(rhs: StrategyType): Bool {
        return !(this == rhs)
    }
}

public class CompilerInstance {
    public var typeManager: TypeManager = TypeManager()
    public var globalOptions: OptionGlobalOptions = OptionGlobalOptions()
    public var kind: IncreKind = IncreKind.INVALID
    public var compileStrategy: StrategyType = StrategyType.DEFAULT
    public var buildTrie: Bool = true
    public var frontendDumpActionIsTypeCheck: Bool = false
    public var diag: Option<BasicDiagnosticEngine> = None
    public var importManager: Option<SemaImportManager> = None
    // CompilerInstance.h:573-574: merged source and imported packages.
    public let packages: ArrayList<Package> = ArrayList<Package>()
    public let sourcePackages: ArrayList<Package> = ArrayList<Package>()
    public let packageDecls: ArrayList<PackageDecl> = ArrayList<PackageDecl>()
    public let importedPackageDecls: ArrayList<PackageDecl> = ArrayList<PackageDecl>()
    public let resolvedImportedDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    public let resolvedPackageMemberDeclsMap: HashMap<String, HashMap<String, ArrayList<Decl>>> =
        HashMap<String, HashMap<String, ArrayList<Decl>>>()
    public let resolvedImplicitPackageMemberDeclsMap: HashMap<String, HashMap<String, Decl>> =
        HashMap<String, HashMap<String, Decl>>()
    public let resolvedImportPackageNameMap: HashMap<Node, (String, Bool)> =
        HashMap<Node, (String, Bool)>()
    public let resolvedPackageDeclMap: HashMap<String, PackageDecl> = HashMap<String, PackageDecl>()
    public let resolvedCjoPackageMemberDeclsMap: HashMap<String, HashMap<String, ArrayList<Decl>>> =
        HashMap<String, HashMap<String, ArrayList<Decl>>>()
    public let resolvedUsedMacroDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    public let pkgCtxMap: HashMap<Node, ASTContext> = HashMap<Node, ASTContext>()
    public var cacheSemaUsage: Option<(SemanticInfo) -> Unit> = None
    public init() {}

    // CompilerInstance.h:260-268 CompilerInstance::GetPackages.
    public func GetPackages(): ArrayList<Package> {
        let result = ArrayList<Package>()
        for (pkg in packages) {
            result.add(pkg)
        }
        return result
    }

    // CompilerInstance.cpp:1095-1102 CompilerInstance::GetSourcePackages.
    public func GetSourcePackages(): ArrayList<Package> {
        let result = ArrayList<Package>()
        for (pkg in sourcePackages) {
            result.add(pkg)
        }
        return result
    }

    // C++ CompilerInstance.h:563. The closure preserves the frontend-owned cache across the package boundary.
    public func CacheSemaUsage(info: SemanticInfo): Unit {
        cacheSemaUsage.getOrThrow()(info)
    }

    public func IsBuildTrie(): Bool {
        return buildTrie
    }

    public func SetBuildTrie(flag: Bool): Unit {
        buildTrie = flag
    }

    public func GetASTContextByPackage(pkg: Option<Package>): Option<ASTContext> {
        if (let None <- pkg) {
            return None
        }
        return pkgCtxMap.get(pkg.getOrThrow())
    }

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

    public func AddResolvedImportPackageName(importSpec: ImportSpec, packageName: String, isImportPackage: Bool): Unit {
        resolvedImportPackageNameMap[importSpec] = (packageName, isImportPackage)
    }

    public func AddResolvedPackageDecl(packageName: String, packageDecl: PackageDecl): Unit {
        resolvedPackageDeclMap[packageName] = packageDecl
    }

    public func AddResolvedCjoPackageMemberDecls(packageName: String, name: String, decls: ArrayList<Decl>): Unit {
        if (!resolvedCjoPackageMemberDeclsMap.contains(packageName)) {
            resolvedCjoPackageMemberDeclsMap[packageName] = HashMap<String, ArrayList<Decl>>()
        }
        if (let Some(packageMap) <- resolvedCjoPackageMemberDeclsMap.get(packageName)) {
            AddDeclsToNamedMap(packageMap, name, decls)
        }
    }

    public func AddResolvedUsedMacroDecls(fileIndex: UInt64, packageName: String, decls: ArrayList<Decl>): Unit {
        if (!resolvedUsedMacroDeclsMap.contains(fileIndex)) {
            resolvedUsedMacroDeclsMap[fileIndex] = HashMap<String, ArrayList<Decl>>()
        }
        if (let Some(fileMap) <- resolvedUsedMacroDeclsMap.get(fileIndex)) {
            AddDeclsToNamedMap(fileMap, packageName, decls)
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
        var idx: Int64 = 0
        while (idx < values.size) {
            if (CompNodeByPos(decl, values[idx])) {
                values.add(decl, at: idx)
                return
            }
            idx++
        }
        values.add(decl)
    }

    private func CompNodeByPos(left: Decl, right: Decl): Bool {
        return left.begin.fileID < right.begin.fileID ||
            (left.begin.fileID == right.begin.fileID && left.begin < right.begin) ||
            (left.begin.fileID == right.begin.fileID && left.begin == right.begin && left.objectId < right.objectId)
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
    if (let Some(packageMap) <- ctx.resolvedCjoPackageMemberDeclsMap.get(fullPackageName)) {
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
