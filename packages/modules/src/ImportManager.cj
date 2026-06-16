package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::option.GlobalOptions
import cangjie_compiler::option.OutputMode

public class ExternalLibCfg {
    public var name: String = ""
    public var path: String = ""
    public let exports: HashSet<String> = HashSet<String>()

    public init() {}

    public init(name: String, path: String) {
        this.name = name
        this.path = path
    }
}

public enum DepType {
    | DIRECT
    | INDIRECT
    | BOTH
}

private func DepTypeIndex(depType: DepType): Int64 {
    return match (depType) {
        case DepType.DIRECT => 0
        case DepType.INDIRECT => 1
        case DepType.BOTH => 2
    }
}

extend DepType <: Equatable<DepType> {
    public operator func ==(right: DepType): Bool {
        return DepTypeIndex(this) == DepTypeIndex(right)
    }

    public operator func !=(right: DepType): Bool {
        return !(this == right)
    }
}

public class ImportedDeclGroup {
    public var name: String = ""
    public let decls: ArrayList<Decl> = ArrayList<Decl>()

    public init() {}

    public init(name: String, decls: ArrayList<Decl>) {
        this.name = name
        for (decl in decls) {
            this.decls.add(decl)
        }
    }
}

private class StdDepEntry {
    public var depType: DepType
    public var fullPackageName: String

    public init(depType: DepType, fullPackageName: String) {
        this.depType = depType
        this.fullPackageName = fullPackageName
    }
}

private class DependencyInfoItem {
    public var packageName: String = ""
    public var orPackage: String = ""
    public var isStd: Bool = false
    public let imports: ArrayList<ImportSpec> = ArrayList<ImportSpec>()

    public init() {}
}

public class ImportManager {
    private let diag: DiagnosticEngine
    private let opts: GlobalOptions
    private var useBCHIRCache: Bool = false
    private let bchirFileCacheMap: HashMap<String, ArrayList<UInt8>> = HashMap<String, ArrayList<UInt8>>()
    private let fileImportedDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    private let importedDeclsMap: HashMap<String, ArrayList<Decl>> = HashMap<String, ArrayList<Decl>>()
    private let stdDepsMap: HashMap<String, StdDepEntry> = HashMap<String, StdDepEntry>()
    private let directMacroDeps: HashMap<String, Package> = HashMap<String, Package>()
    private let declsImportedByNodeMap: HashMap<String, HashMap<String, ArrayList<ImportSpec>>> =
        HashMap<String, HashMap<String, ArrayList<ImportSpec>>>()
    private let fileUsedMacroDeclsMap: HashMap<UInt64, HashMap<String, ArrayList<Decl>>> =
        HashMap<UInt64, HashMap<String, ArrayList<Decl>>>()
    private let declToTypeAlias: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    private var importSrcCode: Bool = true
    private var cjoManager: CjoManager
    private var dependencyGraph: DependencyGraph
    private var curPackage: Option<Package> = None
    private let cjoFilePaths: HashMap<String, String> = HashMap<String, String>()
    private let cjdFilePaths: HashMap<String, String> = HashMap<String, String>()

    public var implicitPrelude: Bool = false

    public init() {
        diag = DiagnosticEngine()
        opts = GlobalOptions()
        let config = CjoManagerConfig(diag, opts, importSrcCode)
        cjoManager = CjoManager(config)
        dependencyGraph = DependencyGraph(cjoManager)
    }

    public init(diag: DiagnosticEngine, globalOptions: GlobalOptions) {
        this.diag = diag
        opts = globalOptions
        let config = CjoManagerConfig(diag, opts, importSrcCode)
        cjoManager = CjoManager(config)
        dependencyGraph = DependencyGraph(cjoManager)
    }

    public func GetCjoManager(): CjoManager {
        return cjoManager
    }

    public func ExportAST(
        saveFileWithAbsPath: Bool,
        astData: ArrayList<UInt8>,
        pkg: Package,
        additionalSerializations!: (ASTWriter) -> Unit = { _: ASTWriter => () }
    ): Unit {
        let writer = ASTWriter(
            diag,
            GeneratePkgDepInfo(pkg, true),
            ExportConfig(importSrcCode, false, opts.exportForTest, saveFileWithAbsPath, opts.compileCjd),
            cjoManager
        )
        if (opts.outputMode == OutputMode.CHIR) {
            writer.SetSerializingCommon()
        }
        writer.PreSaveFullExportDecls(pkg)
        writer.ExportAST(PackageDecl(pkg))
        writer.SaveOptions(opts.enableCompileDebug, opts.optimizationLevel)
        additionalSerializations(writer)
        writer.AST2FB(astData, PackageDecl(pkg))
    }

    public func ExportASTSignature(pkg: Package): ArrayList<UInt8> {
        let data = ArrayList<UInt8>()
        let writer = ASTWriter(
            diag,
            "",
            ExportConfig(true, true, false, false, opts.compileCjd),
            cjoManager
        )
        writer.PreSaveFullExportDecls(pkg)
        writer.ExportAST(PackageDecl(pkg))
        writer.SaveOptions(opts.enableCompileDebug, opts.optimizationLevel)
        writer.AST2FB(data, PackageDecl(pkg))
        return data
    }

    public func ExportDeclsWithContent(saveFileWithAbsPath: Bool, pkg: Package): Unit {
        let writer = ASTWriter(
            diag,
            GeneratePkgDepInfo(pkg, true),
            ExportConfig(importSrcCode, false, opts.exportForTest, saveFileWithAbsPath, opts.compileCjd),
            cjoManager
        )
        writer.PreSaveFullExportDecls(pkg)
        writer.SaveOptions(opts.enableCompileDebug, opts.optimizationLevel)
    }

    public func GetAllImportedPackages(includeMacroPkg!: Bool = false): ArrayList<PackageDecl> {
        return cjoManager.GetAllPackageDecls(includeMacroPkg: includeMacroPkg)
    }

    public func GetCurImportedPackages(fullPackageName: String): ArrayList<PackageDecl> {
        return dependencyGraph.GetDirectDependencyPackageDecls(fullPackageName)
    }

    public func GetPackageMembersByName(pkg: Package, name: String): ArrayList<Decl> {
        return cjoManager.GetPackageMembersByName(pkg.fullPackageName, name)
    }

    public func GetPackageMembers(srcFullPackageName: String, targetFullPackageName: String): HashMap<String, ArrayList<Decl>> {
        let res = HashMap<String, ArrayList<Decl>>()
        if (srcFullPackageName == targetFullPackageName) {
            return res
        }
        let relation = GetPackageRelation(srcFullPackageName, targetFullPackageName)
        let members = cjoManager.GetPackageMembers(targetFullPackageName)
        for (name in members.keys()) {
            if (let Some(decls) <- members.get(name)) {
                let visibleDecls = ArrayList<Decl>()
                for (decl in decls) {
                    if (IsVisible(decl, relation)) {
                        AddDeclUnique(visibleDecls, decl)
                    }
                }
                if (!visibleDecls.isEmpty()) {
                    res[name] = visibleDecls
                }
            }
        }
        return res
    }

    public func GetImportedDecls(file: File): ArrayList<ImportedDeclGroup> {
        let res = ArrayList<ImportedDeclGroup>()
        for (name in importedDeclsMap.keys()) {
            if (let Some(decls) <- importedDeclsMap.get(name)) {
                res.add(ImportedDeclGroup(name, decls))
            }
        }
        if (let Some(fileMap) <- fileImportedDeclsMap.get(file.fileHash)) {
            for (name in fileMap.keys()) {
                if (let Some(decls) <- fileMap.get(name)) {
                    res.add(ImportedDeclGroup(name, decls))
                }
            }
        }
        return res
    }

    public func GetAllImportedDecls(file: File): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        for (group in GetImportedDecls(file)) {
            for (decl in group.decls) {
                AddDeclUnique(out, decl)
            }
        }
        return out
    }

    public func GetImportedDeclsByName(file: File, name: String): ArrayList<Decl> {
        let ret = ArrayList<Decl>()
        if (let Some(decls) <- importedDeclsMap.get(name)) {
            for (decl in decls) {
                AddDeclUnique(ret, decl)
            }
        }
        if (let Some(fileMap) <- fileImportedDeclsMap.get(file.fileHash)) {
            if (let Some(decls) <- fileMap.get(name)) {
                for (decl in decls) {
                    AddDeclUnique(ret, decl)
                }
            }
        }
        return ret
    }

    public func GetImportsOfDecl(fullPackageName: String): HashMap<String, ArrayList<ImportSpec>> {
        let out = HashMap<String, ArrayList<ImportSpec>>()
        if (let Some(declImportMap) <- declsImportedByNodeMap.get(fullPackageName)) {
            for (declKey in declImportMap.keys()) {
                if (let Some(imports) <- declImportMap.get(declKey)) {
                    out[declKey] = CloneImportSpecArray(imports)
                }
            }
        }
        return out
    }

    public func AddUsedMacroDecls(file: File, decl: Decl): Unit {
        if (!fileUsedMacroDeclsMap.contains(file.indexOfPackage)) {
            fileUsedMacroDeclsMap[file.indexOfPackage] = HashMap<String, ArrayList<Decl>>()
        }
        if (let Some(usedDeclMap) <- fileUsedMacroDeclsMap.get(file.indexOfPackage)) {
            PutDeclMapValue(usedDeclMap, decl.fullPackageName, decl)
        }
    }

    public func GetUsedMacroDecls(file: File): HashMap<String, ArrayList<Decl>> {
        let out = HashMap<String, ArrayList<Decl>>()
        if (let Some(usedDeclMap) <- fileUsedMacroDeclsMap.get(file.indexOfPackage)) {
            for (pkgName in usedDeclMap.keys()) {
                if (let Some(decls) <- usedDeclMap.get(pkgName)) {
                    out[pkgName] = CloneDeclArray(decls)
                }
            }
        }
        return out
    }

    public func IsDeclAccessible(file: File, decl: Decl): Bool {
        var accessible = false
        var relation = PackageRelation.NONE
        if (let Some(filePackage) <- file.packageRef) {
            accessible = decl.fullPackageName == filePackage.fullPackageName
            relation = GetPackageRelation(filePackage.fullPackageName, decl.fullPackageName)
        }
        if (ContainsDecl(GetImportedDeclsByName(file, decl.identifier), decl)) {
            return true
        }
        let packageNames = SplitQualifiedName(decl.fullPackageName)
        var idx = packageNames.size - 1
        while (idx >= 0) {
            if (!GetImportedDeclsByName(file, packageNames[idx]).isEmpty() && IsVisible(decl, relation)) {
                accessible = true
            }
            idx--
        }
        if (let Some(aliases) <- declToTypeAlias.get(DeclAliasKey(decl))) {
            for (aliasName in aliases) {
                if (!GetImportedDeclsByName(file, aliasName).isEmpty()) {
                    accessible = true
                }
            }
        }
        return accessible
    }

    public func GetImportedPackageDecl(node: Node, packageName: String): (Option<PackageDecl>, Bool) {
        if (let Some(file) <- node.curFile) {
            let decls = GetImportedDeclsByName(file, packageName)
            var ret: Option<PackageDecl> = None
            for (decl in decls) {
                if (let Some(pd) <- (decl as PackageDecl)) {
                    if (let None <- ret) {
                        ret = Some(pd)
                    } else {
                        return (ret, true)
                    }
                }
            }
            return (ret, false)
        }
        return (None, false)
    }

    public func GetAllDependentPackageDecls(fullPackageName: String, includeMacroPkg!: Bool = false): ArrayList<PackageDecl> {
        return dependencyGraph.GetAllDependencyPackageDecls(fullPackageName, includeMacroPkg)
    }

    public func GetAllDependentPackageNames(fullPackageName: String): ArrayList<String> {
        return dependencyGraph.GetAllDependencyPackageNames(fullPackageName, false)
    }

    public func GeneratePkgDepInfo(packages: ArrayList<Package>): ArrayList<String> {
        let res = ArrayList<String>()
        for (pkg in packages) {
            res.add(GeneratePkgDepInfo(pkg, false))
        }
        return res
    }

    public func GeneratePkgDepInfoByCjo(cjoPath: String): ArrayList<String> {
        let packageDepInfo = cjoManager.GetPackageDepInfo(cjoPath)
        let out = ArrayList<String>()
        if (!packageDepInfo.isEmpty()) {
            out.add(packageDepInfo)
        }
        return out
    }

    public func CollectDirectDepPkg(pkg: Package): HashSet<String> {
        let depPkgs = HashSet<String>()
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti()) {
                    continue
                }
                for (name in cjoManager.GetPossibleCjoNames(importSpec)) {
                    depPkgs.add(name)
                }
            }
        }
        return depPkgs
    }

    public func BuildIndex(cangjieModules: String, globalOptions: GlobalOptions, packages: ArrayList<Package>): Bool {
        if (packages.isEmpty()) {
            diag.ReportError("empty_package_set", "BuildIndex requires at least one package")
            return false
        }
        let incrBuildIndex = HasBuildIndex()
        if (!incrBuildIndex) {
            cjoManager.UpdateSearchPath(cangjieModules)
        } else {
            ClearCachesForRebuild()
        }
        for (pkg in packages) {
            if (pkg.HasFtrDirective()) {
                CheckPackageFeatureSpec(pkg)
            }
            if (globalOptions.compileTestsOnly && !IsTestPackage(pkg.fullPackageName)) {
                pkg.fullPackageName = pkg.fullPackageName + TEST_PKG_SUFFIX
            }
            AddImplicitImports(pkg, globalOptions)
            cjoManager.AddSourcePackage(pkg)
        }
        let success = ResolveImportedPackages(packages)
        ClearPackageCjoCache()
        for (pkg in packages) {
            dependencyGraph.AddDependenciesForPackage(pkg)
        }
        for (pkg in packages) {
            AddImportedDeclsForSourcePackage(pkg)
        }
        for (pkg in packages) {
            ResolveImports(pkg)
        }
        for (pd in GetAllImportedPackages()) {
            if (pd.srcPackage.hasSourceImportedDecl && !ContainsPackage(packages, pd.srcPackage)) {
                packages.add(pd.srcPackage)
            }
        }
        curPackage = Some(packages[0])
        cjoManager.SetHasBuildIndex(true)
        return success
    }

    public func ReindexSourcePackagesAfterMacroExpand(srcPackages: ArrayList<Package>): Unit {
        if (srcPackages.size <= 1) {
            return
        }
        for (pkg in srcPackages) {
            cjoManager.RebuildSourcePackageDeclMap(pkg.fullPackageName)
        }
        importedDeclsMap.clear()
        fileImportedDeclsMap.clear()
        declsImportedByNodeMap.clear()
        declToTypeAlias.clear()
        for (pkg in srcPackages) {
            AddImportedDeclsForSourcePackage(pkg)
        }
    }

    public func LoadPackageFromCjo(fullPkgName: String, cjoPath: String): Option<Package> {
        if (!cjoManager.LoadPackageHeader(fullPkgName, cjoPath)) {
            return None
        }
        let packageOpt = cjoManager.GetPackage(fullPkgName)
        if (let None <- packageOpt) {
            return None
        }
        let packageValue = packageOpt.getOrThrow()
        let singleton = ArrayList<Package>()
        singleton.add(packageValue)
        cjoManager.LoadPackageDeclsOnDemand(singleton, fromLsp: true)
        cjoManager.ClearVisitedPkgs()
        cjoManager.AddPackageDeclMap(fullPkgName)
        return Some(packageValue)
    }

    public func GetImportedDecl(fullPackageName: String, name: String): Option<Decl> {
        let decls = cjoManager.GetPackageMembersByName(fullPackageName, name)
        if (decls.isEmpty()) {
            return cjoManager.GetImplicitPackageMembersByName(fullPackageName, name)
        }
        return Some(decls[0])
    }

    public func GetAstDecl(name: String): Option<Decl> {
        return GetImportedDecl(AST_PACKAGE_NAME, name)
    }

    public func GetCoreDecl(name: String): Option<Decl> {
        return GetImportedDecl(CORE_PACKAGE_NAME, name)
    }

    public func GetSyncDecl(name: String): Option<Decl> {
        return GetImportedDecl(SYNC_PACKAGE_NAME, name)
    }

    public func ResolveImports(pkg: Package): Unit {
        UpdateMacroPackageUsage(pkg)
        CheckImports(pkg)
        CheckRedefinition(pkg)
    }

    public func GetUsedSTDLibFiles(depType: DepType): HashSet<String> {
        let result = HashSet<String>()
        for (cjoPath in stdDepsMap.keys()) {
            if (let Some(entry) <- stdDepsMap.get(cjoPath)) {
                if (entry.depType == depType || entry.depType == DepType.BOTH) {
                    result.add(cjoPath)
                }
            }
        }
        return result
    }

    public func AnalyzeDepStdPkgsOfBC(fullPackageName: String): Bool {
        if (let Some(_) <- cjoManager.GetPackage(fullPackageName)) {
            return true
        }
        if (cjoFilePaths.contains(fullPackageName)) {
            return true
        }
        let cjoPath = cjoManager.GetPackageCjoPath(fullPackageName)
        if (cjoPath.isEmpty() || !cjoManager.LoadPackageHeader(fullPackageName, cjoPath)) {
            diag.ReportError("bc_cjo_error", "cannot analyze standard package dependency '${fullPackageName}'")
            return false
        }
        if (let Some(packageValue) <- cjoManager.GetPackage(fullPackageName)) {
            for (depStdPkg in packageValue.GetAllDependentStdPkgs()) {
                HandleStdPackage(depStdPkg, cjoManager.GetPackageCjoPath(depStdPkg), isRecursive: true)
            }
        }
        return true
    }

    public func IsMacroRelatedPackageName(fullPackageName: String): Bool {
        return cjoManager.IsMacroRelatedPackageName(fullPackageName)
    }

    public func UpdateFileNodeImportInfo(pkg: Package, file: File, newFile: File): Unit {
        newFile.packageRef = Some(pkg)
        for (importSpec in file.imports) {
            if (importSpec.TestAttr(Attribute.IMPLICIT_ADD)) {
                newFile.imports.add(importSpec)
            }
        }
        for (importSpec in newFile.imports) {
            if (!importSpec.IsImportMulti()) {
                let pair = cjoManager.GetPackageCjo(importSpec)
                if (pair[1].isEmpty()) {
                    diag.ReportError("macro_file_import_resolution", "failed to resolve imports for macro file")
                }
                if (!importSpec.IsImportAll() && !cjoManager.IsImportPackage(importSpec)) {
                    importSpec.content.isDecl = true
                }
            }
        }
        if (let Some(found) <- fileImportedDeclsMap.get(file.fileHash)) {
            fileImportedDeclsMap[newFile.fileHash] = found
            fileImportedDeclsMap.remove(file.fileHash)
        }
        newFile.indexOfPackage = file.indexOfPackage
        if (file.indexOfPackage < UInt64(pkg.files.size)) {
            pkg.files[Int64(file.indexOfPackage)] = newFile
        }
    }

    public func GetImportedStdMacroPackages(): ArrayList<String> {
        let stdMacroPackages: Array<String> = ["std.unittest.testmacro", "std.unittest.mock.mockmacro", "std.deriving"]
        let importedMacroPackages = ArrayList<String>()
        for (packageName in stdMacroPackages) {
            if (let Some(_) <- cjoManager.GetPackageDecl(packageName)) {
                importedMacroPackages.add(packageName)
            }
        }
        return importedMacroPackages
    }

    public func GetImportedPkgsForMacro(): ArrayList<Package> {
        let out = ArrayList<Package>()
        for (name in directMacroDeps.keys()) {
            if (let Some(pkg) <- directMacroDeps.get(name)) {
                out.add(pkg)
            }
        }
        return out
    }

    public func LoadCachedTypeForPackage(
        pkg: Package,
        mangledName2DeclMap: HashMap<String, Decl>
    ): HashSet<String> {
        let cachedCjo = opts.GenerateCachedPathName(pkg.fullPackageName, SERIALIZED_FILE_EXTENSION)
        return cjoManager.LoadCachedPackage(pkg, cachedCjo, mangledName2DeclMap)
    }

    public func SetPackageCjoCache(
        fullPackageName: String,
        cjoData: Array<UInt8>,
        changeState!: CjoChangeState = CjoChangeState.ADDED
    ): Unit {
        cjoManager.SetPackageCjoCache(fullPackageName, cjoData, changeState: changeState)
    }

    public func ClearPackageCjoCache(): Unit {
        cjoManager.ClearCjoCache()
    }

    public func SetPackageBchirCache(fullPackageName: String, bchirData: Array<UInt8>): Unit {
        if (fullPackageName.isEmpty() || bchirData.isEmpty()) {
            return
        }
        let copied = ArrayList<UInt8>()
        for (byte in bchirData) {
            copied.add(byte)
        }
        bchirFileCacheMap[fullPackageName] = copied
    }

    public func GetBchirCache(fullPackageName: String): Option<ArrayList<UInt8>> {
        return bchirFileCacheMap.get(fullPackageName)
    }

    public func ClearPackageBCHIRCache(): Unit {
        bchirFileCacheMap.clear()
    }

    public func SetUseBCHIRCache(shouldImport: Bool): Unit {
        useBCHIRCache = shouldImport
    }

    public func IsUseBCHIRCache(): Bool {
        return useBCHIRCache
    }

    public func SetSourceCodeImportStatus(shouldImport: Bool): Unit {
        importSrcCode = shouldImport
    }

    public func IsSourceCodeImported(): Bool {
        return importSrcCode
    }

    public func GetPackageDecl(fullPackageName: String): Option<PackageDecl> {
        return cjoManager.GetPackageDecl(fullPackageName)
    }

    public func GetPackage(fullPackageName: String): Option<Package> {
        return cjoManager.GetPackage(fullPackageName)
    }

    public func GetSearchPath(): ArrayList<String> {
        return cjoManager.GetSearchPath()
    }

    public func UpdateSearchPath(cangjieModules: String): Unit {
        cjoManager.UpdateSearchPath(cangjieModules)
    }

    public func DeleteASTWriters(): Unit {}

    public func DeleteASTLoaders(): Unit {
        cjoManager.DeleteASTLoaders()
    }

    public func GetDepPkgCjoPaths(): HashMap<String, String> {
        return cloneStringMap(cjoFilePaths)
    }

    public func GetDepPkgCjdPaths(): HashMap<String, String> {
        return cloneStringMap(cjdFilePaths)
    }

    public func GetDiagnosticEngine(): DiagnosticEngine {
        return diag
    }

    private func ResolveImportedPackages(packages: ArrayList<Package>): Bool {
        var success = true
        for (pkg in packages) {
            curPackage = Some(pkg)
            if (!cjoManager.LoadFilesOfCommonPart(pkg)) {
                return false
            }
            success = ResolveImportedPackageHeaders(pkg, isRecursive: false) && success
            pkg.ClearAllDependentStdPkgs()
            for (cjoPath in stdDepsMap.keys()) {
                if (let Some(entry) <- stdDepsMap.get(cjoPath)) {
                    pkg.AddDependentStdPkg(entry.fullPackageName)
                }
            }
        }
        for (pkg in packages) {
            cjoManager.AddPackageDeclMap(pkg.fullPackageName)
        }
        return success
    }

    private func ResolveImportedPackageHeaders(pkg: Package, isRecursive!: Bool = false): Bool {
        var success = true
        for (file in pkg.files) {
            if (!ResolveImportedPackageForFile(file, isRecursive: isRecursive)) {
                success = false
            }
        }
        return success
    }

    private func ResolveImportedPackageForFile(file: File, isRecursive!: Bool = false): Bool {
        var success = true
        let curPkgOpt = file.packageRef
        if (let None <- curPkgOpt) {
            return true
        }
        let curPkg = curPkgOpt.getOrThrow()
        let isMacroRelated = curPkg.isMacroPackage || IsMacroRelatedPackageName(curPkg.fullPackageName)
        let rootPkg = curPackage.getOrThrow()
        let relation = GetPackageRelation(rootPkg.fullPackageName, curPkg.fullPackageName)
        for (importSpec in file.imports) {
            if (importSpec.IsImportMulti() || !importSpec.withImplicitExport) {
                continue
            }
            let isVisibleImport = importSpec.IsReExport() && IsVisible(importSpec, relation)
            let pair = cjoManager.GetPackageCjo(importSpec)
            let fullPackageName = pair[0]
            let cjoPath = pair[1]
            SaveDepPkgCjoPath(fullPackageName, cjoPath)
            if (let Some(importPkg) <- cjoManager.GetPackage(fullPackageName)) {
                success = HandleParsedPackage(importPkg, cjoPath, !isMacroRelated || isVisibleImport, isRecursive) && success
                continue
            }
            let isMainPartPkgForTestPkg = opts.compileTestsOnly && IsTestPackage(curPkg.fullPackageName) &&
                GetMainPartPkgNameForTestPkg(curPkg.fullPackageName) == fullPackageName
            if (!CheckCjoPathLegality(importSpec, cjoPath, fullPackageName, isRecursive, isMainPartPkgForTestPkg) ||
                !cjoManager.LoadPackageHeader(fullPackageName, cjoPath)) {
                success = false
                continue
            }
            if (let Some(importPkg) <- cjoManager.GetPackage(fullPackageName)) {
                if (importPkg.isMacroPackage && isRecursive && !isVisibleImport && isMacroRelated) {
                    cjoManager.RemovePackage(fullPackageName, importPkg)
                    continue
                }
                let macroReExportCommonPackage = isVisibleImport && isMacroRelated && !importPkg.isMacroPackage
                if ((!IsMacroRelatedPackageName(curPkg.fullPackageName) && !importPkg.isMacroPackage) ||
                    rootPkg.isMacroPackage || macroReExportCommonPackage) {
                    HandleStdPackage(fullPackageName, cjoPath, isRecursive: isRecursive)
                    for (depStdPkg in importPkg.GetAllDependentStdPkgs()) {
                        HandleStdPackage(depStdPkg, cjoManager.GetPackageCjoPath(depStdPkg), isRecursive: true)
                    }
                } else {
                    cjoManager.SetOnlyUsedByMacro(fullPackageName, true)
                }
                success = ResolveImportedPackageHeaders(importPkg, isRecursive: true) && success
            }
        }
        return success
    }

    private func HandleParsedPackage(pkg: Package, filePath: String, isUsedAsCommon: Bool, isRecursive: Bool): Bool {
        var shouldPromoteMacroUse = false
        if (let Some(root) <- curPackage) {
            shouldPromoteMacroUse = root.isMacroPackage || (isUsedAsCommon && !pkg.isMacroPackage)
        }
        if (cjoManager.IsOnlyUsedByMacro(pkg.fullPackageName) && shouldPromoteMacroUse) {
            cjoManager.SetOnlyUsedByMacro(pkg.fullPackageName, false)
            HandleStdPackage(pkg.fullPackageName, filePath, isRecursive: isRecursive)
            for (depStdPkg in pkg.GetAllDependentStdPkgs()) {
                HandleStdPackage(depStdPkg, cjoManager.GetPackageCjoPath(depStdPkg), isRecursive: true)
            }
            return ResolveImportedPackageHeaders(pkg, isRecursive: true)
        }
        return true
    }

    private func SaveDepPkgCjoPath(fullPackageName: String, cjoPath: String): Unit {
        if (fullPackageName.isEmpty()) {
            return
        }
        cjoFilePaths[fullPackageName] = cjoPath
        if (cjoPath.endsWith(SERIALIZED_FILE_EXTENSION)) {
            cjdFilePaths[fullPackageName] = cjoPath[0..cjoPath.size - SERIALIZED_FILE_EXTENSION.size] + CJ_D_FILE_EXTENSION
        }
    }

    private func HandleStdPackage(fullPackageName: String, cjoPath: String, isRecursive!: Bool = false): Unit {
        let depType = if (isRecursive) { DepType.INDIRECT } else { DepType.DIRECT }
        if (let Some(entry) <- stdDepsMap.get(cjoPath)) {
            if (entry.depType != depType) {
                entry.depType = DepType.BOTH
            }
            return
        }
        if (IsStandardLibraryPackage(fullPackageName) && !cjoPath.isEmpty()) {
            stdDepsMap[cjoPath] = StdDepEntry(depType, fullPackageName)
        }
    }

    private func CheckCjoPathLegality(
        importSpec: ImportSpec,
        cjoPath: String,
        fullPackageName: String,
        isRecursive: Bool,
        isMainPartPkgForTestPkg: Bool
    ): Bool {
        if (!cjoPath.isEmpty()) {
            return true
        }
        let kind = if (isMainPartPkgForTestPkg) {
            "package_missed_cjo_main_pkg_part_for_test_pkg"
        } else {
            "package_search_error"
        }
        diag.ReportError(kind, "cannot find package '${fullPackageName}'; " + NO_CJO_HELP_INFO,
            range: GetPackageSearchErrorRange(importSpec, isRecursive))
        return false
    }

    private func GetPackageSearchErrorRange(importSpec: ImportSpec, isRecursive: Bool): Range {
        if (isRecursive) {
            return MakeRange(importSpec.begin, importSpec.begin + 1)
        }
        return GetPackageNameRange(importSpec)
    }

    private func GetPackageNameRange(importSpec: ImportSpec): Range {
        return MakeRange(importSpec.begin, importSpec.end)
    }

    private func UpdateMacroPackageUsage(pkg: Package): Unit {
        for (pd in GetCurImportedPackages(pkg.fullPackageName)) {
            if (!pd.srcPackage.TestAttr(Attribute.TOOL_ADD) && pd.srcPackage.isMacroPackage) {
                directMacroDeps[pd.srcPackage.fullPackageName] = pd.srcPackage
            }
        }
    }

    private func CheckImports(pkg: Package): Unit {
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti()) {
                    continue
                }
                let fullPackageName = cjoManager.GetPackageNameByImport(importSpec)
                let packageOpt = cjoManager.GetPackage(fullPackageName)
                if (fullPackageName.isEmpty() || (let None <- packageOpt)) {
                    continue
                }
                let packageValue = packageOpt.getOrThrow()
                let packageRange = GetPackageNameRange(importSpec)
                if (fullPackageName != packageValue.fullPackageName) {
                    diag.ReportError("package_import_inconsistent",
                        "import resolved to '${packageValue.fullPackageName}', not '${fullPackageName}'",
                        range: packageRange)
                    continue
                } else if (fullPackageName == pkg.fullPackageName) {
                    diag.ReportError("package_import_itself_illegal", "package '${fullPackageName}' imports itself",
                        range: packageRange)
                    continue
                }
                if (importSpec.TestAttr(Attribute.IMPLICIT_ADD)) {
                    continue
                }
                let relation = GetPackageRelation(pkg.fullPackageName, fullPackageName)
                if ((packageValue.accessible == AccessLevel.PROTECTED && relation == PackageRelation.NONE) ||
                    (packageValue.accessible == AccessLevel.INTERNAL && relation != PackageRelation.CHILD &&
                        !IsSuperPackage(pkg.fullPackageName, fullPackageName))) {
                    diag.ReportError("package_accessibility",
                        "package '${fullPackageName}' is ${GetAccessLevelStr(packageValue)} and is not visible from '${pkg.fullPackageName}'",
                        range: packageRange)
                } else if (importSpec.IsReExport() && !pkg.isMacroPackage && packageValue.isMacroPackage) {
                    diag.ReportError("package_cannot_export_macro_package",
                        "non-macro package cannot re-export a macro package", range: packageRange)
                } else if (!importSpec.IsImportAll() && !cjoManager.IsImportPackage(importSpec)) {
                    let decls = cjoManager.GetPackageMembersByName(packageValue.fullPackageName, importSpec.content.identifier)
                    let visibleDecls = GetVisibleDeclToMap(decls, GetAccessLevel(importSpec), relation)
                    if (visibleDecls.isEmpty()) {
                        diag.ReportError("package_decl_not_find_in_package",
                            "declaration '${importSpec.content.identifier}' was not found in package '${fullPackageName}'",
                            range: packageRange)
                    }
                }
            }
        }
    }

    private func CheckRedefinition(pkg: Package): Unit {
        let pkgImportNamePos = HashMap<String, Range>()
        let fileImportNamePos = HashMap<UInt64, HashMap<String, Range>>()
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti() || importSpec.IsImportAll()) {
                    continue
                }
                let name = if (importSpec.content.kind == ImportKind.IMPORT_SINGLE) {
                    importSpec.content.identifier
                } else {
                    importSpec.content.aliasName
                }
                let decls = GetImportedDeclsByName(file, name)
                if (decls.isEmpty()) {
                    continue
                }
                let rangeValue = MakeRange(importSpec.begin, importSpec.end)
                var previousRange: Option<Range> = None
                if (importSpec.IsReExport()) {
                    if (pkgImportNamePos.contains(name)) {
                        previousRange = pkgImportNamePos.get(name)
                    } else {
                        pkgImportNamePos[name] = rangeValue
                        let fileMapForReExport = GetFileImportNamePos(fileImportNamePos, file.fileHash)
                        if (fileMapForReExport.contains(name)) {
                            previousRange = fileMapForReExport.get(name)
                        } else {
                            fileMapForReExport[name] = rangeValue
                        }
                    }
                } else {
                    let fileMapForImport = GetFileImportNamePos(fileImportNamePos, file.fileHash)
                    if (fileMapForImport.contains(name)) {
                        previousRange = fileMapForImport.get(name)
                    } else {
                        fileMapForImport[name] = rangeValue
                    }
                }
                let sourceDecls = GetSourceDeclsForImportedName(pkg, name)
                if (!IsAllFuncDecls(sourceDecls)) {
                    WarnUselessImport(diag, rangeValue, sourceDecls[0])
                } else if (let Some(conflictRange) <- previousRange) {
                    WarnConflictImport(diag, name, rangeValue, conflictRange)
                }
            }
        }
    }

    private func CheckPackageFeatureSpec(pkg: Package): Unit {
        var referenceFile: Option<File> = None
        var referenceFeatureCount: Int64 = -1
        var hasNonProductFile = false
        for (file in pkg.files) {
            if (file.features.isEmpty()) {
                continue
            }
            let uniqueFeatures = CollectUniqueFeatures(file)
            WarnRepeatedFeatures(file)
            if (uniqueFeatures.size > referenceFeatureCount) {
                referenceFile = Some(file)
                referenceFeatureCount = uniqueFeatures.size
            }
            if (!file.isProduct) {
                hasNonProductFile = true
            }
        }
        if (let None <- referenceFile) {
            return
        }
        let refFile = referenceFile.getOrThrow()
        let referenceFeatures = CollectUniqueFeatures(refFile)
        var reported: Int64 = 0
        for (file in pkg.files) {
            if (reported >= 2) {
                return
            }
            if (file.features.isEmpty()) {
                DiagForNullPackageFeature(diag, MakeRange(file.begin, file.end), referenceFeatures)
                reported++
                continue
            }
            let currentFeatures = CollectUniqueFeatures(file)
            if ((hasNonProductFile && file.isProduct) || !SameFeatureSet(currentFeatures, referenceFeatures)) {
                DiagForDifferentPackageFeatureConsistency(
                    diag,
                    MakeRange(file.begin, file.end),
                    currentFeatures,
                    referenceFeatures,
                    hasNonProductFile
                )
                reported++
            }
        }
    }

    private func AddImportedDeclsForSourcePackage(pkg: Package): Unit {
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti()) {
                    continue
                }
                let fullPackageName = cjoManager.GetPackageNameByImport(importSpec)
                let pkgDeclOpt = cjoManager.GetPackageDecl(fullPackageName)
                if (fullPackageName.isEmpty() || (let None <- pkgDeclOpt)) {
                    continue
                }
                let relation = GetPackageRelation(pkg.fullPackageName, fullPackageName)
                let importLevel = GetAccessLevel(importSpec)
                let declMap = if (importSpec.IsReExport()) {
                    importedDeclsMap
                } else {
                    GetFileImportedDeclMap(file.fileHash)
                }
                if (importSpec.content.kind == ImportKind.IMPORT_ALL) {
                    let members = cjoManager.GetPackageMembers(fullPackageName)
                    for (memberName in members.keys()) {
                        if (let Some(memberDecls) <- members.get(memberName)) {
                            let visibleDecls = GetVisibleDeclToMap(memberDecls, importLevel, relation)
                            for (decl in visibleDecls) {
                                PutDeclMapValue(declMap, memberName, decl)
                                RecordImportOfDecl(pkg.fullPackageName, decl, importSpec)
                            }
                        }
                    }
                    continue
                }
                if (cjoManager.IsImportPackage(importSpec)) {
                    let importedName = if (importSpec.content.kind == ImportKind.IMPORT_SINGLE) {
                        lastPackageName(fullPackageName)
                    } else {
                        importSpec.content.aliasName
                    }
                    PutDeclMapValue(declMap, importedName, pkgDeclOpt.getOrThrow())
                    RecordImportOfDecl(pkg.fullPackageName, pkgDeclOpt.getOrThrow(), importSpec)
                } else {
                    let members = cjoManager.GetPackageMembersByName(fullPackageName, importSpec.content.identifier)
                    let importedName = if (importSpec.content.kind == ImportKind.IMPORT_SINGLE) {
                        importSpec.content.identifier
                    } else {
                        importSpec.content.aliasName
                    }
                    let visibleDecls = GetVisibleDeclToMap(members, importLevel, relation)
                    for (decl in visibleDecls) {
                        PutDeclMapValue(declMap, importedName, decl)
                        RecordImportOfDecl(pkg.fullPackageName, decl, importSpec)
                        if (decl.identifier != importedName) {
                            RecordTypeAlias(decl, importedName)
                            RecordTypeAlias(decl, decl.identifier)
                        }
                    }
                    importSpec.content.isDecl = true
                }
            }
        }
    }

    private func GeneratePkgDepInfo(pkg: Package, exportCJO: Bool): String {
        let dependencies = HashMap<String, DependencyInfoItem>()
        let features = HashSet<String>()
        var isProduct = true
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti() || importSpec.TestAttr(Attribute.IMPLICIT_ADD)) {
                    continue
                }
                let names = cjoManager.GetPossibleCjoNames(importSpec)
                if (names.isEmpty()) {
                    continue
                }
                let longName = ToPackageName(names[0])
                let shortName = ToPackageName(names[names.size - 1])
                if (!dependencies.contains(longName)) {
                    dependencies[longName] = CreateDependencyInfoItem(longName, shortName)
                }
                if (let Some(item) <- dependencies.get(longName)) {
                    item.imports.add(importSpec)
                }
            }
            for (feature in file.features) {
                features.add(feature)
            }
            isProduct = isProduct && file.isProduct
        }
        return "{\"package\":\"" + EscapeJson(pkg.fullPackageName) + "\"," +
            "\"isMacro\":" + BoolToJson(pkg.isMacroPackage) + "," +
            "\"accessLevel\":\"" + GetAccessLevelStr(pkg.accessible) + "\"," +
            "\"dependencies\":" + DependenciesToJson(dependencies, exportCJO) + "," +
            "\"std-dependencies\":" + StdDependenciesToJson(dependencies, pkg, exportCJO) + "," +
            "\"features\":" + FeatureSetToJson(features) + "," +
            "\"product\":" + BoolToJson(isProduct) + "}"
    }

    private func CreateDependencyInfoItem(longName: String, shortName: String): DependencyInfoItem {
        let item = DependencyInfoItem()
        if (IsStandardLibraryPackage(longName)) {
            item.packageName = longName
            item.isStd = true
        } else if (IsStandardLibraryPackage(shortName)) {
            item.packageName = shortName
            item.isStd = true
        } else {
            item.packageName = shortName
            if (longName != shortName) {
                item.orPackage = longName
            }
            item.isStd = false
        }
        return item
    }

    private func DependenciesToJson(dependencies: HashMap<String, DependencyInfoItem>, exportCJO: Bool): String {
        let keys = SortedMapKeys(dependencies)
        let dependencyItems = ArrayList<String>()
        for (dependencyName in keys) {
            if (let Some(item) <- dependencies.get(dependencyName)) {
                dependencyItems.add(DependencyItemToJson(item, exportCJO))
            }
        }
        return "[" + JoinStrings(dependencyItems, ",") + "]"
    }

    private func DependencyItemToJson(item: DependencyInfoItem, exportCJO: Bool): String {
        SortImportSpecsByPosition(item.imports)
        var value = "{\"package\":\"" + EscapeJson(item.packageName) + "\","
        if (!item.orPackage.isEmpty()) {
            value += "\"orPackage\":\"" + EscapeJson(item.orPackage) + "\","
        }
        value += "\"isStd\":" + BoolToJson(item.isStd) + ","
        value += "\"imports\":" + ImportSpecsToJson(item.imports, exportCJO) + "}"
        return value
    }

    private func ImportSpecsToJson(imports: ArrayList<ImportSpec>, exportCJO: Bool): String {
        let importItems = ArrayList<String>()
        for (importSpec in imports) {
            importItems.add(ImportSpecToJson(importSpec, exportCJO))
        }
        return "[" + JoinStrings(importItems, ",") + "]"
    }

    private func ImportSpecToJson(importSpec: ImportSpec, exportCJO: Bool): String {
        var fileName = ""
        if (let Some(curFileValue) <- importSpec.curFile) {
            fileName = if (exportCJO) { curFileValue.fileName } else { curFileValue.filePath }
        }
        return "{\"file\":\"" + EscapeJson(fileName) + "\"," +
            "\"begin\":" + PositionToJson(importSpec.begin) + "," +
            "\"end\":" + PositionToJson(importSpec.end) + "}"
    }

    private func PositionToJson(pos: Position): String {
        return "{\"line\":" + pos.line.toString() + ",\"column\":" + pos.column.toString() + "}"
    }

    private func StdDependenciesToJson(
        dependencies: HashMap<String, DependencyInfoItem>,
        pkg: Package,
        exportCJO: Bool
    ): String {
        let stdNames = HashSet<String>()
        stdNames.add(CORE_PACKAGE_NAME)
        if (exportCJO) {
            for (stdName in pkg.GetAllDependentStdPkgs()) {
                if (IsStandardLibraryPackage(stdName)) {
                    stdNames.add(stdName)
                }
            }
        } else {
            for (dependencyName in dependencies.keys()) {
                if (let Some(item) <- dependencies.get(dependencyName)) {
                    if (item.isStd) {
                        stdNames.add(item.packageName)
                    }
                }
            }
        }
        let orderedStdNames = SortedStringSet(stdNames)
        let stdItems = ArrayList<String>()
        for (stdName in orderedStdNames) {
            stdItems.add("{\"" + EscapeJson(stdName) + "\":[]}")
        }
        return "[" + JoinStrings(stdItems, ",") + "]"
    }

    private func FeatureSetToJson(features: HashSet<String>): String {
        let orderedFeatures = SortedStringSet(features)
        let featureItems = ArrayList<String>()
        for (feature in orderedFeatures) {
            featureItems.add("\"" + EscapeJson(feature) + "\"")
        }
        return "[" + JoinStrings(featureItems, ",") + "]"
    }

    private func AddImplicitImports(pkg: Package, globalOptions: GlobalOptions): Unit {
        for (file in pkg.files) {
            if (globalOptions.implicitPrelude) {
                AddImplicitImportAll(file, CORE_PACKAGE_NAME)
            }
            if (globalOptions.enableCompileTest) {
                AddImplicitImportAll(file, "std.unittest")
                AddImplicitImportAll(file, "std.unittest.testmacro")
            }
            if (globalOptions.compileTestsOnly && IsTestPackage(pkg.fullPackageName)) {
                AddImplicitImportAll(file, GetMainPartPkgNameForTestPkg(pkg.fullPackageName))
            }
        }
    }

    private func AddImplicitImportAll(file: File, fullPackageName: String): Unit {
        let names = SplitQualifiedName(fullPackageName)
        for (importSpec in file.imports) {
            if (!importSpec.TestAttr(Attribute.IMPLICIT_ADD) || importSpec.content.kind != ImportKind.IMPORT_ALL) {
                continue
            }
            if (sameStringList(importSpec.content.prefixPaths, names)) {
                return
            }
        }
        let importSpec = CreateImportSpec(fullPackageName, "*", "")
        importSpec.curFile = Some(file)
        importSpec.content.curFile = Some(file)
        file.imports.add(importSpec)
    }

    private func CreateImportSpec(fullPackageName: String, item: String, alias: String): ImportSpec {
        let importSpec = ImportSpec()
        let names = SplitQualifiedName(fullPackageName)
        if (!alias.isEmpty()) {
            importSpec.content.kind = ImportKind.IMPORT_ALIAS
        } else if (item != "*") {
            importSpec.content.kind = ImportKind.IMPORT_SINGLE
        } else {
            importSpec.content.kind = ImportKind.IMPORT_ALL
        }
        for (name in names) {
            if (!name.isEmpty()) {
                importSpec.content.prefixPaths.add(name)
            }
        }
        importSpec.content.identifier = item
        importSpec.content.aliasName = alias
        importSpec.EnableAttr(Attribute.COMPILER_ADD)
        importSpec.EnableAttr(Attribute.IMPLICIT_ADD)
        importSpec.SetAccessLevel(AccessLevel.PRIVATE)
        return importSpec
    }

    private func GetFileImportedDeclMap(fileHash: UInt64): HashMap<String, ArrayList<Decl>> {
        if (!fileImportedDeclsMap.contains(fileHash)) {
            fileImportedDeclsMap[fileHash] = HashMap<String, ArrayList<Decl>>()
        }
        return fileImportedDeclsMap.get(fileHash).getOrThrow()
    }

    private func RecordImportOfDecl(fullPackageName: String, decl: Decl, importSpec: ImportSpec): Unit {
        if (!declsImportedByNodeMap.contains(fullPackageName)) {
            declsImportedByNodeMap[fullPackageName] = HashMap<String, ArrayList<ImportSpec>>()
        }
        let key = decl.fullPackageName + "." + decl.identifier
        if (let Some(map) <- declsImportedByNodeMap.get(fullPackageName)) {
            if (!map.contains(key)) {
                map[key] = ArrayList<ImportSpec>()
            }
            if (let Some(imports) <- map.get(key)) {
                imports.add(importSpec)
            }
        }
    }

    private func GetFileImportNamePos(
        fileImportNamePos: HashMap<UInt64, HashMap<String, Range>>,
        fileHash: UInt64
    ): HashMap<String, Range> {
        if (!fileImportNamePos.contains(fileHash)) {
            fileImportNamePos[fileHash] = HashMap<String, Range>()
        }
        return fileImportNamePos.get(fileHash).getOrThrow()
    }

    private func GetSourceDeclsForImportedName(pkg: Package, name: String): ArrayList<Decl> {
        let out = ArrayList<Decl>()
        let members = cjoManager.GetPackageMembersByName(pkg.fullPackageName, name)
        for (decl in members) {
            if (decl.fullPackageName == pkg.fullPackageName) {
                AddDeclUnique(out, decl)
            }
        }
        return out
    }

    private func IsAllFuncDecls(decls: ArrayList<Decl>): Bool {
        for (decl in decls) {
            if (!decl.isFunction) {
                return false
            }
        }
        return true
    }

    private func CollectUniqueFeatures(file: File): ArrayList<String> {
        let out = ArrayList<String>()
        for (feature in file.features) {
            if (!ContainsStringValue(out, feature)) {
                out.add(feature)
            }
        }
        SortStringsInPlace(out)
        return out
    }

    private func WarnRepeatedFeatures(file: File): Unit {
        let seen = ArrayList<String>()
        for (feature in file.features) {
            if (ContainsStringValue(seen, feature)) {
                WarnRepeatedFeatureName(diag, feature, MakeRange(file.begin, file.end), MakeRange(file.begin, file.end))
            } else {
                seen.add(feature)
            }
        }
    }

    private func SameFeatureSet(left: ArrayList<String>, right: ArrayList<String>): Bool {
        if (left.size != right.size) {
            return false
        }
        var idx: Int64 = 0
        while (idx < left.size) {
            if (left[idx] != right[idx]) {
                return false
            }
            idx++
        }
        return true
    }

    private func ContainsStringValue(values: ArrayList<String>, target: String): Bool {
        for (value in values) {
            if (value == target) {
                return true
            }
        }
        return false
    }

    private func RecordTypeAlias(decl: Decl, alias: String): Unit {
        let key = DeclAliasKey(decl)
        if (!declToTypeAlias.contains(key)) {
            declToTypeAlias[key] = HashSet<String>()
        }
        if (let Some(values) <- declToTypeAlias.get(key)) {
            values.add(alias)
        }
    }

    private func HasBuildIndex(): Bool {
        return cjoManager.HasBuildIndex()
    }

    private func ClearCachesForRebuild(): Unit {
        cjoManager.ClearForReBuildIndex()
        cjoFilePaths.clear()
        cjdFilePaths.clear()
        stdDepsMap.clear()
        dependencyGraph.Clear()
        importedDeclsMap.clear()
        fileImportedDeclsMap.clear()
        declsImportedByNodeMap.clear()
        fileUsedMacroDeclsMap.clear()
        declToTypeAlias.clear()
        directMacroDeps.clear()
    }

    private func lastPackageName(fullPackageName: String): String {
        let names = SplitQualifiedName(fullPackageName, splitDc: true)
        if (names.isEmpty()) {
            return fullPackageName
        }
        return names[names.size - 1]
    }

    private func sameStringList(left: ArrayList<String>, right: ArrayList<String>): Bool {
        if (left.size != right.size) {
            return false
        }
        var idx: Int64 = 0
        while (idx < left.size) {
            if (left[idx] != right[idx]) {
                return false
            }
            idx++
        }
        return true
    }

    private func SortedMapKeys(input: HashMap<String, DependencyInfoItem>): ArrayList<String> {
        let values = ArrayList<String>()
        for (key in input.keys()) {
            values.add(key)
        }
        SortStringsInPlace(values)
        return values
    }

    private func SortedStringSet(input: HashSet<String>): ArrayList<String> {
        let values = ArrayList<String>()
        for (value in input) {
            values.add(value)
        }
        SortStringsInPlace(values)
        return values
    }

    private func SortStringsInPlace(values: ArrayList<String>): Unit {
        var i: Int64 = 1
        while (i < values.size) {
            let key = values[i]
            var j = i - 1
            while (j >= 0 && values[j] > key) {
                values[j + 1] = values[j]
                j--
            }
            values[j + 1] = key
            i++
        }
    }

    private func SortImportSpecsByPosition(values: ArrayList<ImportSpec>): Unit {
        var i: Int64 = 1
        while (i < values.size) {
            let key = values[i]
            var j = i - 1
            while (j >= 0 && ImportSpecComesAfter(values[j], key)) {
                values[j + 1] = values[j]
                j--
            }
            values[j + 1] = key
            i++
        }
    }

    private func ImportSpecComesAfter(left: ImportSpec, right: ImportSpec): Bool {
        if (right.begin < left.begin) {
            return true
        }
        if (left.begin == right.begin && right.end < left.end) {
            return true
        }
        return false
    }

    private func CloneImportSpecArray(values: ArrayList<ImportSpec>): ArrayList<ImportSpec> {
        let out = ArrayList<ImportSpec>()
        for (value in values) {
            out.add(value)
        }
        return out
    }

    private func ContainsDecl(values: ArrayList<Decl>, decl: Decl): Bool {
        for (value in values) {
            if (SameDecl(value, decl)) {
                return true
            }
        }
        return false
    }

    private func DeclAliasKey(decl: Decl): String {
        return decl.fullPackageName + "." + decl.identifier
    }

    private func ContainsPackage(values: ArrayList<Package>, pkg: Package): Bool {
        for (value in values) {
            if (value.fullPackageName == pkg.fullPackageName) {
                return true
            }
        }
        return false
    }

    private func cloneStringMap(input: HashMap<String, String>): HashMap<String, String> {
        let out = HashMap<String, String>()
        for (key in input.keys()) {
            if (let Some(value) <- input.get(key)) {
                out[key] = value
            }
        }
        return out
    }
}
