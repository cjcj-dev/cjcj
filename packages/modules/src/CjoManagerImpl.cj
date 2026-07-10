package cjcj::modules

import std.collection.*
import std.fs.File as FSFile
import std.fs.exists
import cjcj::basic.DiagKindRefactor
import cjcj::basic.FaithfulUnorderedMap
import cjcj::option.GlobalOptions
import cjcj::option.OptimizationLevel
import cjcj::option.enumIndex

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

public func WireToOptimizationLevel(value: String): OptimizationLevel {
    return match (value) {
        case "O1" => OptimizationLevel.O1
        case "O2" => OptimizationLevel.O2
        case "O3" => OptimizationLevel.O3
        case "Os" => OptimizationLevel.Os
        case "Oz" => OptimizationLevel.Oz
        case _ => OptimizationLevel.O0
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
    private let packageNameMap: FaithfulUnorderedMap<CjoPackageInfo> = FaithfulUnorderedMap<CjoPackageInfo>()
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

    public func SetImportSourceCode(enable: Bool): Unit {
        importSrcCode = enable
    }

    public func GetPackageNameMap(): FaithfulUnorderedMap<CjoPackageInfo> {
        return packageNameMap
    }

    public func GetPackageInfo(fullPackageName: String): Option<CjoPackageInfo> {
        return packageNameMap.get(fullPackageName)
    }

    public func AddPackageInfo(fullPackageName: String, info: CjoPackageInfo): Unit {
        packageNameMap.add(fullPackageName, info)
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
        searchPath.add(cangjieModules)
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
        for (fullPackageName in packageNameMap.keys()) {
            if (let Some(info) <- packageNameMap.get(fullPackageName)) {
                info.loader = None
            }
        }
        packageNameMap.clear()
        importedPackageNameMap.clear()
        visitedPkgs.clear()
        loadedPackages.clear()
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
        if (globalOptions.commonPartCjos.isEmpty()) {
            diag.DiagnoseRefactor(DiagKindRefactor.module_common_part_path_is_required, DEFAULT_POSITION).Emit()
        }
        for (path in globalOptions.commonPartCjos) {
            let loaderOpt = ReadCjo(expectedName, path, cjoManager)
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
            return Some(CreateASTLoader(cache.data.toArray(), fullPackageName, cjoManager))
        }
        if (cjoPath.isEmpty() || !exists(cjoPath)) {
            if (printErr) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.module_read_file_to_buffer_failed,
                    DEFAULT_POSITION,
                    arguments: [cjoPath, "file does not exist"]
                ).Emit()
                return None
            }
            return Some(CreateASTLoader("".toArray(), fullPackageName, cjoManager))
        }
        try {
            let bytes = FSFile.readFrom(cjoPath)
            return Some(CreateASTLoader(bytes, fullPackageName, cjoManager))
        } catch (e: Exception) {
            if (printErr) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.module_read_file_to_buffer_failed,
                    DEFAULT_POSITION,
                    arguments: [cjoPath, e.message]
                ).Emit()
                return None
            }
            return Some(CreateASTLoader("".toArray(), fullPackageName, cjoManager))
        }
    }

    private func CreateASTLoader(data: Array<UInt8>, fullPackageName: String, cjoManager: CjoManager): ASTLoader {
        let loader = ASTLoader(data, fullPackageName, cjoManager, globalOptions)
        loader.SetImportSourceCode(importSrcCode)
        return loader
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
        if (SameImportKind(importSpec.content.kind, ImportKind.IMPORT_ALL)) {
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
            let targetName = if (SameImportKind(importSpec.content.kind, ImportKind.IMPORT_ALIAS)) {
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
