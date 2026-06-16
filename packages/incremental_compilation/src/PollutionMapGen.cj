package cangjie_compiler::incremental_compilation

import std.collection.*

public class PollutionMapGen {
    private let mangled2Decl: RawMangled2DeclMap
    private let sourcePopulations: SrcImportedDepMap
    private let graph: SemanticInfo
    private let packageDecl: IncrDecl
    private let resp: ChangePollutedMap = ChangePollutedMap()
    private let rest: TypeMap = TypeMap()

    public static func Get(packageDecl: IncrDecl, mangledName2AST: RawMangled2DeclMap,
        sourceImportedInfo: SrcImportedDepMap, usage: SemanticInfo, chirOpt: OptEffectStrMap,
        importManager: IncrImportManager): (ChangePollutedMap, TypeMap) {
        let gen = PollutionMapGen(packageDecl, mangledName2AST, sourceImportedInfo, usage)
        gen.Collect()
        gen.CollectCHIROpt(chirOpt)
        gen.CollectAlias(importManager)
        return (gen.resp, gen.rest)
    }

    private init(packageDecl: IncrDecl, mangledName2AST: RawMangled2DeclMap,
        sourcePopulations: SrcImportedDepMap, graph: SemanticInfo) {
        this.packageDecl = packageDecl
        this.mangled2Decl = mangledName2AST
        this.sourcePopulations = sourcePopulations
        this.graph = graph
    }

    private func Collect(): Unit {
        for ((decl, usage) in graph.usages) {
            CollectPopulation(decl, usage)
        }
        for ((src, dsts) in sourcePopulations) {
            CollectSourceImportedPopulation(src, dsts)
        }
        for ((mangle, relation) in graph.relations) {
            CollectRelation(mangle, relation)
        }
        for ((name, relation) in graph.builtInTypeRelations) {
            CollectBuiltinRelation(name, relation)
        }
    }

    private func CollectCHIROpt(chirOpt: OptEffectStrMap): Unit {
        for ((src, uses) in chirOpt) {
            if (!resp.directBody.contains(src)) {
                resp.directBody[src] = HashSet<IncrDecl>()
            }
            for (use in uses) {
                if (let Some(decl) <- mangled2Decl.get(use)) {
                    resp.directBody[src].add(decl)
                }
            }
        }
    }

    private func CollectRelation(mangle: String, relation: SemaRelation): Unit {
        for (ext in relation.extends) {
            rest.AddExtend(mangle, ext)
        }
        for (interf in relation.extendedInterfaces) {
            if (!rest.interfaceExtendTypes.contains(interf)) {
                rest.interfaceExtendTypes[interf] = HashSet<String>()
            }
            rest.interfaceExtendTypes[interf].add(mangle)
        }
        if (let Some(decl) <- mangled2Decl.get(mangle)) {
            for (typeName in relation.inherits) {
                if (let Some(parent) <- mangled2Decl.get(typeName)) {
                    rest.AddParent(parent, decl)
                }
            }
        }
    }

    private func CollectBuiltinRelation(name: String, relation: SemaRelation): Unit {
        for (ext in relation.extends) {
            rest.AddExtend(name, ext)
        }
        for (interf in relation.extendedInterfaces) {
            if (!rest.interfaceExtendTypes.contains(interf)) {
                rest.interfaceExtendTypes[interf] = HashSet<String>()
            }
            rest.interfaceExtendTypes[interf].add(name)
        }
    }

    private func GetUnqualifiedUsageScope(decl: IncrDecl): IncrDecl {
        var current = decl
        while (true) {
            if (let Some(parent) <- current.outerDecl) {
                current = parent
            } else {
                break
            }
        }
        if (current == decl && !decl.HasOuterDecl()) {
            return packageDecl
        }
        return current
    }

    private func CollectUsedNameInfo(decl: IncrDecl, usedName: String, usage: NameUsage, index: UseIndex): Unit {
        let pqUses = if (index == UseIndex.BODY) { resp.pqBody } else { resp.pqApi }
        for (qualifier in usage.packageQualifiers) {
            if (!pqUses.contains(usedName)) {
                pqUses[usedName] = HashMap<String, HashSet<IncrDecl>>()
            }
            if (!pqUses[usedName].contains(qualifier)) {
                pqUses[usedName][qualifier] = HashSet<IncrDecl>()
            }
            pqUses[usedName][qualifier].add(decl)
        }

        let qUses = if (index == UseIndex.BODY) { resp.qBody } else { resp.qApi }
        for (parent in usage.parentDecls) {
            let key = QualifiedUsage(parent, usedName)
            if (!qUses.contains(key)) {
                qUses[key] = HashSet<IncrDecl>()
            }
            qUses[key].add(decl)
        }

        let scope = GetUnqualifiedUsageScope(decl)
        if (usage.hasUnqualifiedUsageOfImported) {
            let imported = if (index == UseIndex.BODY) { resp.unqImportedBody } else { resp.unqImportedApi }
            addUnqualified(imported, usedName, scope, decl)
        }
        if (usage.hasUnqualifiedUsage || usage.hasUnqualifiedUsageOfImported) {
            let all = if (index == UseIndex.BODY) { resp.unqBody } else { resp.unqApi }
            addUnqualified(all, usedName, scope, decl)
        }
    }

    private func CollectUseInfo(decl: IncrDecl, info: UseInfo, index: UseIndex): Unit {
        let directUses = if (index == UseIndex.BODY) { resp.directBody } else { resp.directApi }
        for (use in info.usedDecls) {
            if (!directUses.contains(use)) {
                directUses[use] = HashSet<IncrDecl>()
            }
            directUses[use].add(decl)
        }
        for ((name, nameUsage) in info.usedNames) {
            CollectUsedNameInfo(decl, name, nameUsage, index)
        }
    }

    private func CollectPopulation(enclosingDecl: IncrDecl, usage: SemaUsage): Unit {
        CollectUseInfo(enclosingDecl, usage.apiUsages, UseIndex.API)
        CollectUseInfo(enclosingDecl, usage.bodyUsages, UseIndex.BODY)
        for (name in usage.boxedTypes) {
            if (!resp.boxUses.contains(name)) {
                resp.boxUses[name] = ArrayList<IncrDecl>()
            }
            resp.boxUses[name].add(enclosingDecl)
        }
    }

    private func CollectSourceImportedPopulation(src: IncrDecl, dsts: HashSet<IncrDecl>): Unit {
        if (!resp.directBody.contains(src.rawMangleName)) {
            resp.directBody[src.rawMangleName] = HashSet<IncrDecl>()
        }
        for (dst in dsts) {
            resp.directBody[src.rawMangleName].add(dst)
        }
    }

    private func CollectAlias(importManager: IncrImportManager): Unit {
        for (importInfo in importManager.GetSourceImports()) {
            if (!importInfo.isImportAlias && !importInfo.isImportSingle) {
                continue
            }
            let importedPackageName = importInfo.importedPackageName
            let accessibleName = importInfo.AccessibleName()
            if (accessibleName.isEmpty()) {
                continue
            }
            if (let Some(_) <- importManager.GetPackageDecl(importedPackageName)) {
                addPackageAlias(importedPackageName, accessibleName)
            } else {
                let declAliasName = importInfo.DeclAliasName()
                if (!declAliasName.isEmpty()) {
                    addDeclAlias(importInfo.prefixPath, importInfo.identifier, declAliasName)
                }
            }
        }
    }

    private func addPackageAlias(fullPackageName: String, aliasName: String): Unit {
        if (!resp.packageAliasMap.contains(fullPackageName)) {
            resp.packageAliasMap[fullPackageName] = HashSet<String>()
        }
        resp.packageAliasMap[fullPackageName].add(aliasName)
    }

    private func addDeclAlias(fullPackageName: String, identifier: String, aliasName: String): Unit {
        let key = DeclAliasKey(fullPackageName, identifier)
        if (!resp.declAliasMap.contains(key)) {
            resp.declAliasMap[key] = HashSet<String>()
        }
        resp.declAliasMap[key].add(aliasName)
    }

    private func addUnqualified(container: UnqualifiedName2Usages, usedName: String, scope: IncrDecl,
        decl: IncrDecl): Unit {
        if (!container.contains(usedName)) {
            container[usedName] = HashMap<IncrDecl, HashSet<IncrDecl>>()
        }
        if (!container[usedName].contains(scope)) {
            container[usedName][scope] = HashSet<IncrDecl>()
        }
        container[usedName][scope].add(decl)
    }
}
