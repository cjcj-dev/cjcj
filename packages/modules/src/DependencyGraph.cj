package cangjie_compiler::modules

import std.collection.*

public class DependencyGraph {
    private let cjoManager: CjoManager
    private let dependencyMap: HashMap<String, HashMap<String, ArrayList<ImportSpec>>> =
        HashMap<String, HashMap<String, ArrayList<ImportSpec>>>()
    private let pkgReExportMap: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    private let cacheDirectDependencyPackageDecls: HashMap<String, ArrayList<PackageDecl>> =
        HashMap<String, ArrayList<PackageDecl>>()
    private let cacheDependencyPackageDecls: HashMap<String, ArrayList<PackageDecl>> =
        HashMap<String, ArrayList<PackageDecl>>()
    private let cacheDependencyPackageNames: HashMap<String, ArrayList<String>> = HashMap<String, ArrayList<String>>()

    public init(cjoManager: CjoManager) {
        this.cjoManager = cjoManager
    }

    public func GetDirectDependencyPackageDecls(fullPackageName: String): ArrayList<PackageDecl> {
        if (let Some(cached) <- cacheDirectDependencyPackageDecls.get(fullPackageName)) {
            return clonePackageDecls(cached)
        }
        let packageDecls = ArrayList<PackageDecl>()
        let collected = HashSet<String>()
        let tmpQueue = ArrayList<PackageDecl>()
        for (edgeName in GetEdges(fullPackageName).keys()) {
            if (let Some(pkgDecl) <- cjoManager.GetPackageDecl(edgeName)) {
                tmpQueue.add(pkgDecl)
            }
        }
        var head: Int64 = 0
        while (head < tmpQueue.size) {
            let pkgDecl = tmpQueue[head]
            head++
            if (!collected.contains(pkgDecl.fullPackageName)) {
                collected.add(pkgDecl.fullPackageName)
                packageDecls.add(pkgDecl)
            }
            if (!pkgDecl.srcPackage.isMacroPackage) {
                continue
            }
            if (let Some(reExports) <- pkgReExportMap.get(pkgDecl.srcPackage.fullPackageName)) {
                for (reExportPackageName in reExports) {
                    if (let Some(reExportPkgDecl) <- cjoManager.GetPackageDecl(reExportPackageName)) {
                        if (!reExportPkgDecl.srcPackage.isMacroPackage && !collected.contains(reExportPackageName)) {
                            packageDecls.add(reExportPkgDecl)
                            collected.add(reExportPackageName)
                        } else if (reExportPkgDecl.srcPackage.isMacroPackage && !collected.contains(reExportPackageName)) {
                            tmpQueue.add(reExportPkgDecl)
                            collected.add(reExportPackageName)
                        }
                    }
                }
            }
        }
        cacheDirectDependencyPackageDecls[fullPackageName] = clonePackageDecls(packageDecls)
        return packageDecls
    }

    public func GetAllDependencyPackageDecls(fullPackageName: String, includeMacroPkg: Bool): ArrayList<PackageDecl> {
        let cacheKey = fullPackageName + "|" + BoolToJson(includeMacroPkg)
        if (let Some(cached) <- cacheDependencyPackageDecls.get(cacheKey)) {
            return clonePackageDecls(cached)
        }
        let packageDecls = ArrayList<PackageDecl>()
        for (pkgName in GetAllDependencyPackageNames(fullPackageName, includeMacroPkg)) {
            if (let Some(pkgDecl) <- cjoManager.GetPackageDecl(pkgName)) {
                packageDecls.add(pkgDecl)
            }
        }
        cacheDependencyPackageDecls[cacheKey] = clonePackageDecls(packageDecls)
        return packageDecls
    }

    public func GetAllDependencyPackageNames(fullPackageName: String, includeMacroPkg: Bool): ArrayList<String> {
        let cacheKey = fullPackageName + "|" + BoolToJson(includeMacroPkg)
        if (let Some(cached) <- cacheDependencyPackageNames.get(cacheKey)) {
            return CloneStringArray(cached)
        }
        let packageNames = ArrayList<String>()
        let stack = ArrayList<String>()
        for (edgeName in GetEdges(fullPackageName).keys()) {
            stack.add(edgeName)
        }
        while (!stack.isEmpty()) {
            let pkgName = stack[stack.size - 1]
            stack.remove(at: stack.size - 1)
            if (packageNames.contains(pkgName)) {
                continue
            }
            for (edgeName in GetEdges(pkgName).keys()) {
                stack.add(edgeName)
            }
            if (includeMacroPkg || !cjoManager.IsMacroRelatedPackageName(pkgName)) {
                packageNames.add(pkgName)
            }
        }
        sortStringsInPlace(packageNames)
        cacheDependencyPackageNames[cacheKey] = CloneStringArray(packageNames)
        return packageNames
    }

    public func AddDependenciesForPackage(pkg: Package): Unit {
        if (dependencyMap.contains(pkg.fullPackageName)) {
            return
        }
        dependencyMap[pkg.fullPackageName] = HashMap<String, ArrayList<ImportSpec>>()
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                AddDependenciesForImport(pkg, importSpec)
            }
        }
    }

    public func Clear(): Unit {
        dependencyMap.clear()
        pkgReExportMap.clear()
        cacheDirectDependencyPackageDecls.clear()
        cacheDependencyPackageDecls.clear()
        cacheDependencyPackageNames.clear()
    }

    private func GetEdges(fullPackageName: String): HashMap<String, ArrayList<ImportSpec>> {
        if (let Some(edges) <- dependencyMap.get(fullPackageName)) {
            return edges
        }
        return HashMap<String, ArrayList<ImportSpec>>()
    }

    private func AddDependenciesForImport(pkg: Package, importSpec: ImportSpec): Unit {
        var fullPackageName = cjoManager.GetPackageNameByImport(importSpec)
        if (fullPackageName.isEmpty()) {
            let pair = cjoManager.GetPackageCjo(importSpec)
            fullPackageName = pair[0]
        }
        let packageOpt = cjoManager.GetPackage(fullPackageName)
        if (let None <- packageOpt) {
            return
        }
        let packageValue = packageOpt.getOrThrow()
        if (packageValue.fullPackageName == pkg.fullPackageName) {
            return
        }
        AddDependency(pkg.fullPackageName, packageValue.fullPackageName, importSpec)
        AddDependenciesForPackage(packageValue)
        let relation = GetPackageRelation(pkg.fullPackageName, fullPackageName)
        if (importSpec.IsReExport() && IsVisible(importSpec, relation)) {
            if (!pkgReExportMap.contains(pkg.fullPackageName)) {
                pkgReExportMap[pkg.fullPackageName] = HashSet<String>()
            }
            if (let Some(values) <- pkgReExportMap.get(pkg.fullPackageName)) {
                values.add(fullPackageName)
            }
        }
    }

    private func AddDependency(u: String, v: String, importSpec: ImportSpec): Unit {
        if (!dependencyMap.contains(u)) {
            dependencyMap[u] = HashMap<String, ArrayList<ImportSpec>>()
        }
        if (let Some(edges) <- dependencyMap.get(u)) {
            if (!edges.contains(v)) {
                edges[v] = ArrayList<ImportSpec>()
            }
            if (let Some(imports) <- edges.get(v)) {
                imports.add(importSpec)
            }
        }
        cacheDirectDependencyPackageDecls.clear()
        cacheDependencyPackageDecls.clear()
        cacheDependencyPackageNames.clear()
    }

    private func clonePackageDecls(values: ArrayList<PackageDecl>): ArrayList<PackageDecl> {
        let out = ArrayList<PackageDecl>()
        for (value in values) {
            out.add(value)
        }
        return out
    }

    private func sortStringsInPlace(values: ArrayList<String>): Unit {
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
}
