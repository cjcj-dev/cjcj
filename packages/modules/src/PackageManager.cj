package cangjie_compiler::modules

import std.collection.*

public class PackageInfo {
    public var fullPackageName: String
    public let deps: ArrayList<PackageInfo> = ArrayList<PackageInfo>()

    public init(fullPackageName: String) {
        this.fullPackageName = fullPackageName
    }
}

private class TarjanContext {
    public let indices: HashMap<String, Int64> = HashMap<String, Int64>()
    public let lowlinks: HashMap<String, Int64> = HashMap<String, Int64>()
    public let onStack: HashSet<String> = HashSet<String>()

    public init() {}
}

public class PackageManager {
    private let importManager: ImportManager
    private let orderedPackageInfos: ArrayList<ArrayList<PackageInfo>> = ArrayList<ArrayList<PackageInfo>>()

    public let packageToOtherSccMap: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    public let packageInfoMap: HashMap<String, PackageInfo> = HashMap<String, PackageInfo>()

    public init(importManager: ImportManager) {
        this.importManager = importManager
    }

    public func ResolveDependence(pkgs: ArrayList<Package>): Bool {
        packageInfoMap.clear()
        orderedPackageInfos.clear()
        packageToOtherSccMap.clear()
        CollectDeps(pkgs)
        let ctx = TarjanContext()
        let stack = ArrayList<PackageInfo>()
        var index: Int64 = 0
        while (ctx.indices.size < packageInfoMap.size) {
            var progressed = false
            for (name in packageInfoMap.keys()) {
                if (!ctx.indices.contains(name)) {
                    if (let Some(info) <- packageInfoMap.get(name)) {
                        TarjanForSCC(ctx, stack, index, info)
                        index = ctx.indices.size
                        progressed = true
                    }
                }
            }
            if (!progressed) {
                break
            }
        }
        let sortPackageMap = HashMap<String, Package>()
        for (pkg in pkgs) {
            sortPackageMap[pkg.fullPackageName] = pkg
        }
        var ret = true
        var pkgIndex: Int64 = 0
        for (component in orderedPackageInfos) {
            ret = ret && component.size == 1
            for (pkgInfo in component) {
                if (let Some(pkg) <- sortPackageMap.get(pkgInfo.fullPackageName)) {
                    pkgs[pkgIndex] = pkg
                    pkgIndex++
                }
            }
        }
        return ret
    }

    public func GetBuildOrders(): ArrayList<ArrayList<PackageInfo>> {
        let out = ArrayList<ArrayList<PackageInfo>>()
        for (component in orderedPackageInfos) {
            let copied = ArrayList<PackageInfo>()
            for (info in component) {
                copied.add(info)
            }
            out.add(copied)
        }
        return out
    }

    private func CollectDeps(pkgs: ArrayList<Package>): Unit {
        for (pkg in pkgs) {
            packageInfoMap[pkg.fullPackageName] = PackageInfo(pkg.fullPackageName)
        }
        for (pkg in pkgs) {
            if (let Some(pkgInfo) <- packageInfoMap.get(pkg.fullPackageName)) {
                for (file in pkg.files) {
                    CollectDepsInFile(file, pkgInfo, pkg)
                }
            }
        }
    }

    private func CollectDepsInFile(file: File, pkgInfo: PackageInfo, pkg: Package): Unit {
        for (importSpec in file.imports) {
            var fullPkgName = importManager.GetCjoManager().GetPackageNameByImport(importSpec)
            let pdOpt = importManager.GetCjoManager().GetPackageDecl(fullPkgName)
            if (let None <- pdOpt) {
                continue
            }
            let importPkg = pdOpt.getOrThrow().srcPackage
            if (importPkg.TestAttr(Attribute.TOOL_ADD)) {
                continue
            }
            fullPkgName = importPkg.fullPackageName
            if (let Some(found) <- packageInfoMap.get(fullPkgName)) {
                addUniqueInfo(pkgInfo.deps, found)
            } else {
                if (!packageToOtherSccMap.contains(pkg.fullPackageName)) {
                    packageToOtherSccMap[pkg.fullPackageName] = HashSet<String>()
                }
                if (let Some(values) <- packageToOtherSccMap.get(pkg.fullPackageName)) {
                    values.add(importPkg.fullPackageName)
                }
            }
        }
    }

    private func TarjanForSCC(ctx: TarjanContext, stack: ArrayList<PackageInfo>, index: Int64, u: PackageInfo): Unit {
        let nextIndex = index + 1
        ctx.indices[u.fullPackageName] = nextIndex
        ctx.lowlinks[u.fullPackageName] = nextIndex
        stack.add(u)
        ctx.onStack.add(u.fullPackageName)

        for (w in u.deps) {
            if (!ctx.indices.contains(w.fullPackageName)) {
                TarjanForSCC(ctx, stack, ctx.indices.size, w)
                let currentLow = ctx.lowlinks.get(u.fullPackageName).getOrThrow()
                let childLow = ctx.lowlinks.get(w.fullPackageName).getOrThrow()
                ctx.lowlinks[u.fullPackageName] = if (currentLow < childLow) { currentLow } else { childLow }
            } else if (ctx.onStack.contains(w.fullPackageName)) {
                let currentLow = ctx.lowlinks.get(u.fullPackageName).getOrThrow()
                let childIndex = ctx.indices.get(w.fullPackageName).getOrThrow()
                ctx.lowlinks[u.fullPackageName] = if (currentLow < childIndex) { currentLow } else { childIndex }
            }
        }
        if (ctx.lowlinks.get(u.fullPackageName).getOrThrow() == ctx.indices.get(u.fullPackageName).getOrThrow()) {
            let infos = ArrayList<PackageInfo>()
            while (!stack.isEmpty()) {
                let v = stack[stack.size - 1]
                stack.remove(at: stack.size - 1)
                ctx.onStack.remove(v.fullPackageName)
                infos.add(v)
                if (v.fullPackageName == u.fullPackageName) {
                    break
                }
            }
            orderedPackageInfos.add(infos)
        }
    }

    private func addUniqueInfo(values: ArrayList<PackageInfo>, value: PackageInfo): Unit {
        for (item in values) {
            if (item.fullPackageName == value.fullPackageName) {
                return
            }
        }
        values.add(value)
    }
}
