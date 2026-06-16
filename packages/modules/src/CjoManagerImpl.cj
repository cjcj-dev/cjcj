package cangjie_compiler::modules

import std.collection.*
import std.fs.File as FSFile
import std.fs.exists
import cangjie_compiler::option.GlobalOptions
import cangjie_compiler::option.OptimizationLevel
import cangjie_compiler::option.enumIndex

public func OptimizationLevelToString(level: OptimizationLevel): String {
    return match (level) {
        case OptimizationLevel.O0 => "O0"
        case OptimizationLevel.O1 => "O1"
        case OptimizationLevel.O2 => "O2"
        case OptimizationLevel.O3 => "O3"
        case OptimizationLevel.Os => "Os"
        case OptimizationLevel.Oz => "Oz"
    }
}

public class CjoManagerConfig {
    public var diag: DiagnosticEngine = DiagnosticEngine()
    public var globalOptions: GlobalOptions = GlobalOptions()
    public var importSrcCode: Bool = true

    public init() {}

    public init(diag: DiagnosticEngine, globalOptions: GlobalOptions, importSrcCode: Bool) {
        this.diag = diag
        this.globalOptions = globalOptions
        this.importSrcCode = importSrcCode
    }
}

public enum CjoChangeState {
    | UNCHANGED
    | CHANGED
    | ADDED
    | DELETED
}

private func CjoChangeStateIndex(state: CjoChangeState): Int64 {
    return match (state) {
        case CjoChangeState.UNCHANGED => 0
        case CjoChangeState.CHANGED => 1
        case CjoChangeState.ADDED => 2
        case CjoChangeState.DELETED => 3
    }
}

extend CjoChangeState <: Equatable<CjoChangeState> {
    public operator func ==(right: CjoChangeState): Bool {
        return CjoChangeStateIndex(this) == CjoChangeStateIndex(right)
    }

    public operator func !=(right: CjoChangeState): Bool {
        return !(this == right)
    }
}

public class CjoCacheInfo {
    public var state: CjoChangeState = CjoChangeState.UNCHANGED
    public let data: ArrayList<UInt8> = ArrayList<UInt8>()

    public init() {}

    public init(data: Array<UInt8>, state: CjoChangeState) {
        this.state = state
        for (byte in data) {
            this.data.add(byte)
        }
    }
}

public class CjoPackageInfo {
    public var loader: Option<ASTLoader> = None
    public var pkg: Package
    public var pkgDecl: PackageDecl
    public let exportIDDeclMap: HashMap<String, Decl> = HashMap<String, Decl>()
    public let declMap: HashMap<String, ArrayList<Decl>> = HashMap<String, ArrayList<Decl>>()
    public let implicitDeclMap: HashMap<String, Decl> = HashMap<String, Decl>()
    public var cjoPath: String = ""
    public var onlyUsedByMacro: Bool = false

    public init(pkg: Package) {
        this.pkg = pkg
        this.pkgDecl = PackageDecl(pkg)
    }

    public init(pkg: Package, loader: ASTLoader, cjoPath: String) {
        this.pkg = pkg
        this.pkgDecl = PackageDecl(pkg)
        this.loader = Some(loader)
        this.cjoPath = cjoPath
    }
}

public class CjoManagerImpl {
    private let diag: DiagnosticEngine
    private let globalOptions: GlobalOptions
    private var importSrcCode: Bool
    private let packageNameMap: HashMap<String, CjoPackageInfo> = HashMap<String, CjoPackageInfo>()
    private let cjoFileCacheMap: HashMap<String, CjoCacheInfo> = HashMap<String, CjoCacheInfo>()
    private let importedPackageNameMap: HashMap<String, (String, Bool)> = HashMap<String, (String, Bool)>()
    private let visitedPkgs: HashSet<String> = HashSet<String>()
    private let loadedPackages: HashSet<String> = HashSet<String>()
    private let commonPartLoaders: ArrayList<ASTLoader> = ArrayList<ASTLoader>()
    private let searchPath: ArrayList<String> = ArrayList<String>()
    private let cjoPathFindCache: HashMap<String, String> = HashMap<String, String>()
    private var hasBuildIndex: Bool = false
    private var canInline: Bool = false

    public init(config: CjoManagerConfig) {
        diag = config.diag
        globalOptions = config.globalOptions
        importSrcCode = config.importSrcCode
        canInline = config.globalOptions.chirLLVM &&
            enumIndex(config.globalOptions.optimizationLevel) > enumIndex(OptimizationLevel.O1) &&
            !config.globalOptions.enableCompileTest && !config.globalOptions.enableHotReload
    }

    public func GetDiag(): DiagnosticEngine {
        return diag
    }

    public func GetGlobalOptions(): GlobalOptions {
        return globalOptions
    }

    public func GetPackageNameMap(): HashMap<String, CjoPackageInfo> {
        return packageNameMap
    }

    public func GetPackageInfo(fullPackageName: String): Option<CjoPackageInfo> {
        return packageNameMap.get(fullPackageName)
    }

    public func AddPackageInfo(fullPackageName: String, info: CjoPackageInfo): Unit {
        packageNameMap[fullPackageName] = info
    }

    public func RemovePackageInfo(fullPackageName: String): Unit {
        packageNameMap.remove(fullPackageName)
    }

    public func GetExportIdDeclMap(fullPackageName: String): Option<HashMap<String, Decl>> {
        if (let Some(info) <- GetPackageInfo(fullPackageName)) {
            return Some(info.exportIDDeclMap)
        }
        return None
    }

    public func GetCanInline(): Bool {
        return canInline
    }

    public func AddLoadedPackages(pkgName: String): Bool {
        if (loadedPackages.contains(pkgName)) {
            return false
        }
        loadedPackages.add(pkgName)
        return true
    }

    public func AlreadyLoaded(pkgName: String): Bool {
        return loadedPackages.contains(pkgName)
    }

    public func AddImportedPackageName(importSpec: ImportSpec, pkgName: String, isImportPackage: Bool): Unit {
        importedPackageNameMap[ImportSpecKey(importSpec)] = (pkgName, isImportPackage)
    }

    public func GetPackageNameByImport(importSpec: ImportSpec): String {
        if (let Some(pair) <- importedPackageNameMap.get(ImportSpecKey(importSpec))) {
            return pair[0]
        }
        return ""
    }

    public func IsImportPackage(importSpec: ImportSpec): Bool {
        if (let Some(pair) <- importedPackageNameMap.get(ImportSpecKey(importSpec))) {
            return pair[1]
        }
        return false
    }

    public func UpdateSearchPath(cangjieModules: String): Unit {
        searchPath.clear()
        for (path in globalOptions.importPaths) {
            searchPath.add(path)
        }
        searchPath.add(".")
        for (path in globalOptions.environment.cangjiePaths) {
            searchPath.add(path)
        }
        if (!cangjieModules.isEmpty()) {
            searchPath.add(cangjieModules)
        }
    }

    public func GetSearchPath(): ArrayList<String> {
        return searchPath
    }

    public func SetPackageCjoCache(fullPackageName: String, cjoData: Array<UInt8>, changeState: CjoChangeState): Unit {
        if (fullPackageName.isEmpty() || cjoData.isEmpty()) {
            return
        }
        cjoFileCacheMap[fullPackageName] = CjoCacheInfo(cjoData, changeState)
    }

    public func ClearCjoCache(): Unit {
        cjoFileCacheMap.clear()
    }

    public func GetCjoFileCacheMap(): HashMap<String, CjoCacheInfo> {
        return cjoFileCacheMap
    }

    public func IsVisitedPackage(fullPackageName: String): Bool {
        return visitedPkgs.contains(fullPackageName)
    }

    public func AddVisitedPackage(fullPackageName: String): Unit {
        visitedPkgs.add(fullPackageName)
    }

    public func RemoveVisitedPackage(fullPackageName: String): Unit {
        visitedPkgs.remove(fullPackageName)
    }

    public func ClearVisitedPkgs(): Unit {
        visitedPkgs.clear()
    }

    public func ClearForReBuildIndex(): Unit {
        packageNameMap.clear()
        importedPackageNameMap.clear()
        visitedPkgs.clear()
        loadedPackages.clear()
        commonPartLoaders.clear()
        hasBuildIndex = false
    }

    public func HasBuildIndex(): Bool {
        return hasBuildIndex
    }

    public func SetHasBuildIndex(value: Bool): Unit {
        hasBuildIndex = value
    }

    public func GetCjoPathFromFindCache(cjoName: String): Option<String> {
        return cjoPathFindCache.get(cjoName)
    }

    public func CacheCjoPathForFind(cjoName: String, cjoPath: String): Unit {
        cjoPathFindCache[cjoName] = cjoPath
    }

    public func GetCommonPartCjos(expectedName: String, cjoManager: CjoManager): ArrayList<ASTLoader> {
        if (!commonPartLoaders.isEmpty()) {
            return commonPartLoaders
        }
        for (path in globalOptions.commonPartCjos) {
            let loaderOpt = ReadCjo(expectedName, path, cjoManager, printErr: false)
            if (let Some(loader) <- loaderOpt) {
                commonPartLoaders.add(loader)
            }
        }
        return commonPartLoaders
    }

    public func ReadCjo(
        fullPackageName: String,
        cjoPath: String,
        cjoManager: CjoManager,
        printErr!: Bool = true
    ): Option<ASTLoader> {
        if (let Some(cache) <- cjoFileCacheMap.get(fullPackageName)) {
            return Some(ASTLoader(cache.data.toArray(), fullPackageName, cjoManager, globalOptions))
        }
        if (cjoPath.isEmpty() || !exists(cjoPath)) {
            if (printErr) {
                diag.ReportError("package_search_error", "cannot find serialized package '${fullPackageName}'")
            }
            return None
        }
        try {
            let bytes = FSFile.readFrom(cjoPath)
            return Some(ASTLoader(bytes, fullPackageName, cjoManager, globalOptions))
        } catch (e: Exception) {
            if (printErr) {
                diag.ReportError("cjo_read_error", "cannot read serialized package '${fullPackageName}'")
            }
            return None
        }
    }

    public func IsReExportBy(srcPackage: String, reExportPackage: String): Bool {
        if (let Some(info) <- GetPackageInfo(srcPackage)) {
            for (file in info.pkg.files) {
                for (importSpec in file.imports) {
                    if (!importSpec.IsReExport()) {
                        continue
                    }
                    let mapped = GetPackageNameByImport(importSpec)
                    if (mapped == reExportPackage) {
                        return true
                    }
                }
            }
        }
        return false
    }

    public func AddImportsToMap(importSpec: ImportSpec, importedPackage: String, declMap: HashMap<String, ArrayList<Decl>>): Unit {
        let pkgInfoOpt = GetPackageInfo(importedPackage)
        if (let None <- pkgInfoOpt) {
            return
        }
        let pkgInfo = pkgInfoOpt.getOrThrow()
        let importLevel = GetAccessLevel(importSpec)
        if (importSpec.content.kind == ImportKind.IMPORT_ALL) {
            for (name in pkgInfo.declMap.keys()) {
                if (let Some(decls) <- pkgInfo.declMap.get(name)) {
                    if (!declMap.contains(name)) {
                        declMap[name] = ArrayList<Decl>()
                    }
                    if (let Some(targetMap) <- declMap.get(name)) {
                        AddImportedDeclToMap(decls, targetMap, importLevel)
                    }
                }
            }
            return
        }
        let sourceName = importSpec.content.identifier
        if (let Some(decls) <- pkgInfo.declMap.get(sourceName)) {
            let targetName = if (importSpec.content.kind == ImportKind.IMPORT_ALIAS) {
                importSpec.content.aliasName
            } else {
                sourceName
            }
            if (!declMap.contains(targetName)) {
                declMap[targetName] = ArrayList<Decl>()
            }
            if (let Some(targetMap) <- declMap.get(targetName)) {
                AddImportedDeclToMap(decls, targetMap, importLevel)
            }
        }
    }
}
