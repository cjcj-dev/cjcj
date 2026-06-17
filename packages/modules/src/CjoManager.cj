package cangjie_compiler::modules

import std.collection.*
import cangjie_compiler::utils.FileUtil

public class CjoManager {
    private var impl: CjoManagerImpl

    public init() {
        impl = CjoManagerImpl(CjoManagerConfig())
    }

    public init(config: CjoManagerConfig) {
        impl = CjoManagerImpl(config)
    }

    public func GetImpl(): CjoManagerImpl {
        return impl
    }

    public func SetImportSourceCode(enable: Bool): Unit {
        impl.SetImportSourceCode(enable)
    }

    public func AddSourcePackage(pkg: Package): Unit {
        NormalizePackageFiles(pkg)
        let info = CjoPackageInfo(pkg)
        impl.AddPackageInfo(pkg.fullPackageName, info)
    }

    public func AddImportedPackageFromASTNode(pkg: Package): Unit {
        pkg.EnableAttr(Attribute.TOOL_ADD)
        NormalizePackageFiles(pkg)
        let info = CjoPackageInfo(pkg)
        impl.AddPackageInfo(pkg.fullPackageName, info)
    }

    public func LoadPackageHeader(fullPackageName: String, cjoPath: String): Bool {
        if (let Some(_) <- impl.GetPackageInfo(fullPackageName)) {
            return true
        }
        let loaderOpt = impl.ReadCjo(fullPackageName, cjoPath, this)
        if (let None <- loaderOpt) {
            return false
        }
        let loader = loaderOpt.getOrThrow()
        let pkgOpt = loader.LoadPackageDependencies()
        if (let None <- pkgOpt) {
            return false
        }
        let pkg = pkgOpt.getOrThrow()
        pkg.EnableAttr(Attribute.IMPORTED)
        NormalizePackageFiles(pkg)
        let info = CjoPackageInfo(pkg, loader, cjoPath)
        impl.AddPackageInfo(fullPackageName, info)
        return true
    }

    public func LoadAllDeclsAndRefs(): Unit {
        for (name in impl.GetPackageNameMap().keys()) {
            if (let Some(info) <- impl.GetPackageInfo(name)) {
                if (let Some(loader) <- info.loader) {
                    loader.LoadPackageDecls()
                }
            }
        }
        for (name in impl.GetPackageNameMap().keys()) {
            if (let Some(info) <- impl.GetPackageInfo(name)) {
                if (let Some(loader) <- info.loader) {
                    loader.LoadRefs()
                }
            }
        }
    }

    public func NeedCollectDependency(curName: String, isCurMacro: Bool, depName: String): Bool {
        if (depName == curName || impl.AlreadyLoaded(depName)) {
            return false
        }
        if (let Some(depPd) <- GetPackageDecl(depName)) {
            let isDepMacro = depPd.srcPackage.isMacroPackage
            if (!isCurMacro || isDepMacro || depName == AST_PACKAGE_NAME || IsReExportByResolved(curName, depName)) {
                return true
            }
        }
        return false
    }

    public func LoadPackageDeclsOnDemand(packages: ArrayList<Package>, fromLsp!: Bool = false): Unit {
        let queue = ArrayList<CjoPackageInfo>()
        let loaders = ArrayList<ASTLoader>()
        for (pkg in packages) {
            if (fromLsp) {
                if (let Some(info) <- impl.GetPackageInfo(pkg.fullPackageName)) {
                    queue.add(info)
                }
            }
            for (file in pkg.files) {
                for (importSpec in file.imports) {
                    let pkgName = GetPackageNameByImport(importSpec)
                    if (!pkgName.isEmpty()) {
                        if (let Some(info) <- impl.GetPackageInfo(pkgName)) {
                            queue.add(info)
                        }
                    }
                }
            }
        }
        for (pkg in packages) {
            if (impl.GetGlobalOptions().IsCompilingCJMPSpecific() || !impl.GetGlobalOptions().commonPartCjos.isEmpty()) {
                for (commonLoader in GetCommonPartCjos(pkg.fullPackageName)) {
                    commonLoader.LoadPackageDecls()
                    loaders.add(commonLoader)
                }
            }
        }
        var head: Int64 = 0
        while (head < queue.size) {
            let cur = queue[head]
            head++
            if (let None <- cur.loader) {
                continue
            }
            let loader = cur.loader.getOrThrow()
            let pkgName = loader.GetImportedPackageName()
            if (!impl.AddLoadedPackages(pkgName)) {
                continue
            }
            loaders.add(loader)
            loader.LoadPackageDecls()
            let isCurMacro = cur.pkg.isMacroPackage
            for (depPkg in loader.GetDependentPackageNames()) {
                if (NeedCollectDependency(pkgName, isCurMacro, depPkg)) {
                    if (let Some(depInfo) <- impl.GetPackageInfo(depPkg)) {
                        queue.add(depInfo)
                    }
                }
            }
        }
        for (loader in loaders) {
            loader.LoadRefs()
        }
    }

    public func AddPackageDeclMap(fullPackageName: String, importedPackage!: String = ""): Unit {
        let infoOpt = impl.GetPackageInfo(fullPackageName)
        if (let None <- infoOpt) {
            return
        }
        if (impl.IsVisitedPackage(fullPackageName)) {
            return
        }
        let info = infoOpt.getOrThrow()
        impl.AddVisitedPackage(fullPackageName)
        let relation = if (importedPackage.isEmpty()) {
            PackageRelation.CHILD
        } else {
            GetPackageRelation(importedPackage, fullPackageName)
        }
        for (file in info.pkg.files) {
            for (decl in file.decls) {
                if (decl.TestAttr(Attribute.MACRO_EXPAND_DECL)) {
                    continue
                }
                AddDeclToMap(decl, info.declMap)
            }
            for (decl in file.exportedInternalDecls) {
                if (decl.TestAttr(Attribute.IMPLICIT_USED)) {
                    info.implicitDeclMap[decl.identifier] = decl
                }
            }
        }
        for (file in info.pkg.files) {
            for (importSpec in file.imports) {
                if (importSpec.IsImportMulti()) {
                    continue
                }
                let pkgName = GetPackageNameByImport(importSpec)
                if (pkgName.isEmpty()) {
                    continue
                }
                AddPackageDeclMap(pkgName, importedPackage: fullPackageName)
                if (importSpec.IsReExport() && IsVisible(importSpec, relation)) {
                    impl.AddImportsToMap(importSpec, pkgName, info.declMap)
                }
            }
        }
    }

    public func RebuildSourcePackageDeclMap(fullPackageName: String): Unit {
        if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
            info.declMap.clear()
            info.implicitDeclMap.clear()
            impl.RemoveVisitedPackage(fullPackageName)
            AddPackageDeclMap(fullPackageName)
        }
    }

    public func LoadCachedPackage(
        pkg: Package,
        cjoPath: String,
        mangledName2DeclMap: HashMap<String, Decl>
    ): HashSet<String> {
        let result = HashSet<String>()
        let loaderOpt = impl.ReadCjo(pkg.fullPackageName, cjoPath, this, printErr: false)
        if (let Some(loader) <- loaderOpt) {
            for (name in loader.LoadCachedTypeForPackage(pkg, mangledName2DeclMap)) {
                result.add(name)
            }
        }
        return result
    }

    public func GetPackageDepInfo(cjoPath: String): String {
        let loaderOpt = impl.ReadCjo("", cjoPath, this, printErr: false)
        if (let Some(loader) <- loaderOpt) {
            return loader.LoadPackageDepInfo()
        }
        return ""
    }

    public func GetPackageDecl(fullPackageName: String): Option<PackageDecl> {
        if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
            return Some(info.pkgDecl)
        }
        return None
    }

    public func GetPackage(fullPackageName: String): Option<Package> {
        if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
            return Some(info.pkg)
        }
        return None
    }

    public func LoadFilesOfCommonPart(pkg: Package): Bool {
        if (!impl.GetGlobalOptions().IsCompilingCJMPSpecific() && impl.GetGlobalOptions().commonPartCjos.isEmpty()) {
            return true
        }
        var removeIndex = pkg.files.size - 1
        while (removeIndex >= 0) {
            if (pkg.files[removeIndex].TestAttr(Attribute.FROM_COMMON_PART)) {
                pkg.files.remove(at: removeIndex)
            }
            removeIndex--
        }
        var fileIndex: Int64 = 0
        while (fileIndex < pkg.files.size) {
            pkg.files[fileIndex].packageRef = Some(pkg)
            pkg.files[fileIndex].indexOfPackage = UInt64(fileIndex)
            fileIndex++
        }
        for (loader in impl.GetCommonPartCjos(pkg.fullPackageName, this)) {
            if (!loader.PreloadCommonPartOfPackage(pkg)) {
                return false
            }
        }
        return true
    }

    public func GetCommonPartCjos(expectedName: String): ArrayList<ASTLoader> {
        return impl.GetCommonPartCjos(expectedName, this)
    }

    public func GetAllPackageDecls(includeMacroPkg!: Bool = false): ArrayList<PackageDecl> {
        let ret = ArrayList<PackageDecl>()
        for (name in impl.GetPackageNameMap().keys()) {
            if (let Some(info) <- impl.GetPackageInfo(name)) {
                if (!info.pkg.TestAttr(Attribute.IMPORTED) || includeMacroPkg ||
                    (!info.onlyUsedByMacro && !info.pkg.isMacroPackage)) {
                    ret.add(info.pkgDecl)
                }
            }
        }
        return ret
    }

    public func RemovePackage(fullPkgName: String, pkg: Package): Unit {
        let _ = pkg
        impl.RemovePackageInfo(fullPkgName)
    }

    public func GetPackageMembers(fullPackageName: String): HashMap<String, ArrayList<Decl>> {
        let out = HashMap<String, ArrayList<Decl>>()
        if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
            for (name in info.declMap.keys()) {
                if (let Some(values) <- info.declMap.get(name)) {
                    out[name] = CloneDeclArray(values)
                }
            }
        }
        return out
    }

    public func GetPackageMembersByName(fullPackageName: String, name: String): ArrayList<Decl> {
        if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
            return GetDeclMapValue(info.declMap, name)
        }
        return ArrayList<Decl>()
    }

    public func GetImplicitPackageMembersByName(fullPackageName: String, name: String): Option<Decl> {
        if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
            return info.implicitDeclMap.get(name)
        }
        return None
    }

    public func GetPackageCjoPath(fullPackageName: String): String {
        return FindCjoPath(fullPackageName, fullPackageName, GetSearchPath())
    }

    public func GetPackageCjo(importSpec: ImportSpec): (String, String) {
        let mapped = GetPackageNameByImport(importSpec)
        if (!mapped.isEmpty()) {
            return (mapped, FindCjoPath(mapped, ToCjoFileName(mapped), GetSearchPath()))
        }
        var cjoPath = ""
        var cjoName = ""
        var cjoPackageName = ""
        var inGroupPackageName = ""
        for (candidate in GetPossibleCjoNames(importSpec)) {
            cjoName = candidate
            cjoPackageName = ToPackageName(candidate)
            if (inGroupPackageName.isEmpty() && impl.GetPackageInfo(cjoPackageName).isSome()) {
                inGroupPackageName = cjoPackageName
            }
            cjoPath = FindCjoPath(cjoPackageName, candidate, GetSearchPath())
            if (!cjoPath.isEmpty()) {
                break
            }
        }
        if (!inGroupPackageName.isEmpty() && inGroupPackageName != cjoPackageName) {
            cjoPackageName = inGroupPackageName
            cjoPath = ""
        }
        if (cjoName.isEmpty()) {
            cjoPackageName = importSpec.content.GetImportedPackageName()
        }
        let possibleName = importSpec.content.GetImportedPackageName()
        impl.AddImportedPackageName(
            importSpec,
            cjoPackageName,
            cjoPackageName == possibleName && importSpec.content.kind != ImportKind.IMPORT_ALL
        )
        return (cjoPackageName, cjoPath)
    }

    public func GetFullPackageNames(importSpec: ImportSpec): ArrayList<String> {
        let out = ArrayList<String>()
        for (name in GetPossibleCjoNames(importSpec)) {
            out.add(ToPackageName(name))
        }
        return out
    }

    public func GetPossibleCjoNames(importSpec: ImportSpec): ArrayList<String> {
        let mapped = GetPackageNameByImport(importSpec)
        let out = ArrayList<String>()
        if (!mapped.isEmpty()) {
            out.add(ToCjoFileName(mapped))
            return out
        }
        for (name in importSpec.content.GetPossiblePackageNames()) {
            out.add(ToCjoFileName(name))
        }
        return out
    }

    public func GetPackageNameByImport(importSpec: ImportSpec): String {
        return impl.GetPackageNameByImport(importSpec)
    }

    public func IsImportPackage(importSpec: ImportSpec): Bool {
        return impl.IsImportPackage(importSpec)
    }

    public func IsOnlyUsedByMacro(fullPackageName: String): Bool {
        if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
            return info.onlyUsedByMacro
        }
        return false
    }

    public func SetOnlyUsedByMacro(fullPackageName: String, onlyUsedByMacro: Bool): Unit {
        if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
            info.onlyUsedByMacro = onlyUsedByMacro
        }
    }

    public func IsMacroRelatedPackageName(fullPackageName: String): Bool {
        if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
            return info.onlyUsedByMacro
        }
        return false
    }

    public func UpdateSearchPath(cangjieModules: String): Unit {
        impl.UpdateSearchPath(cangjieModules)
    }

    public func GetSearchPath(): ArrayList<String> {
        return impl.GetSearchPath()
    }

    public func GetCanInline(): Bool {
        return impl.GetCanInline()
    }

    public func SetPackageCjoCache(
        fullPackageName: String,
        cjoData: Array<UInt8>,
        changeState!: CjoChangeState = CjoChangeState.ADDED
    ): Unit {
        impl.SetPackageCjoCache(fullPackageName, cjoData, changeState)
    }

    public func ClearCjoCache(): Unit {
        impl.ClearCjoCache()
    }

    public func DeleteASTLoaders(): Unit {
        for (fullPackageName in impl.GetPackageNameMap().keys()) {
            if (let Some(info) <- impl.GetPackageInfo(fullPackageName)) {
                info.loader = None
            }
        }
    }

    public func ClearVisitedPkgs(): Unit {
        impl.ClearVisitedPkgs()
    }

    public func ClearForReBuildIndex(): Unit {
        impl.ClearForReBuildIndex()
    }

    public func HasBuildIndex(): Bool {
        return impl.HasBuildIndex()
    }

    public func SetHasBuildIndex(value: Bool): Unit {
        impl.SetHasBuildIndex(value)
    }

    public func GetDiag(): DiagnosticEngine {
        return impl.GetDiag()
    }

    public func GetExportIdDeclMap(fullPackageName: String): Option<HashMap<String, Decl>> {
        return impl.GetExportIdDeclMap(fullPackageName)
    }

    private func FindCjoPath(fullPackageName: String, cjoName: String, paths: ArrayList<String>): String {
        if (impl.GetCjoFileCacheMap().contains(fullPackageName)) {
            return cjoName
        }
        if (let Some(cached) <- impl.GetCjoPathFromFindCache(fullPackageName)) {
            return cached
        }
        let cjoPath = FileUtil.FindSerializationFile(fullPackageName, SERIALIZED_FILE_EXTENSION, paths.toArray())
        impl.CacheCjoPathForFind(fullPackageName, cjoPath)
        return cjoPath
    }

    private func IsReExportByResolved(srcPackage: String, reExportPackage: String): Bool {
        if (let Some(info) <- impl.GetPackageInfo(srcPackage)) {
            for (file in info.pkg.files) {
                for (importSpec in file.imports) {
                    if (!importSpec.IsReExport()) {
                        continue
                    }
                    var mapped = GetPackageNameByImport(importSpec)
                    if (mapped.isEmpty()) {
                        let pair = GetPackageCjo(importSpec)
                        mapped = pair[0]
                    }
                    if (mapped == reExportPackage) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func AddDeclToMap(decl: Decl, declMap: HashMap<String, ArrayList<Decl>>): Unit {
        if (decl.doNotExport || decl.identifier.isEmpty()) {
            return
        }
        PutDeclMapValue(declMap, decl.identifier, decl)
    }

    private func NormalizePackageFiles(pkg: Package): Unit {
        var idx: Int64 = 0
        while (idx < pkg.files.size) {
            let file = pkg.files[idx]
            file.packageRef = Some(pkg)
            file.indexOfPackage = UInt64(idx)
            for (importSpec in file.imports) {
                importSpec.curFile = Some(file)
                importSpec.content.curFile = Some(file)
            }
            for (decl in file.decls) {
                decl.curFile = Some(file)
                if (decl.fullPackageName.isEmpty()) {
                    decl.fullPackageName = pkg.fullPackageName
                }
            }
            idx++
        }
    }
}

public func ImportSpecKey(importSpec: ImportSpec): String {
    return ImportKindToWire(importSpec.content.kind) + "|" + importSpec.content.GetImportedPackageName() + "|" +
        importSpec.content.aliasName + "|" + GetAccessLevelStr(importSpec.accessLevel)
}
