package cjcj::incremental_compilation

import std.collection.*
import cjcj::ast.*
import cjcj::modules.SemaImportManager

public class PollutionMapGen {
    private let mangled2Decl: RawMangled2DeclMap
    private let sourcePopulations: SrcImportedDepMap
    private let graph: SemanticInfo
    private let pdecl: PackageDecl
    private let resp: ChangePollutedMap = ChangePollutedMap()
    private let rest: TypeMap = TypeMap()

    public static func Get(packageDecl: PackageDecl, mangledName2AST: RawMangled2DeclMap,
        sourceImportedInfo: SrcImportedDepMap, usage: SemanticInfo, chirOpt: OptEffectStrMap,
        importManager: SemaImportManager): (ChangePollutedMap, TypeMap) {
        let instance = PollutionMapGen(packageDecl, mangledName2AST, sourceImportedInfo, usage)
        instance.Collect()
        instance.CollectCHIROpt(chirOpt)
        instance.CollectAlias(importManager, packageDecl.srcPackage)
        return (instance.resp, instance.rest)
    }

    private init(packageDecl: PackageDecl, mangledName2AST: RawMangled2DeclMap,
        sourcePopulations: SrcImportedDepMap, graph: SemanticInfo) {
        pdecl = packageDecl
        mangled2Decl = mangledName2AST
        this.sourcePopulations = sourcePopulations
        this.graph = graph
    }

    private func Collect(): Unit {
        for ((decl, usage) in graph.usages) { CollectPopulation(decl, usage) }
        for ((src, dsts) in sourcePopulations) { CollectSourceImportedPopulation(src, dsts) }
        for ((mangle, relation) in graph.relations) { CollectRelation(mangle, relation) }
        for ((name, relation) in graph.builtInTypeRelations) { CollectBuiltinRelation(name, relation) }
    }

    private func CollectCHIROpt(chirOpt: OptEffectStrMap): Unit {
        for ((src, uses) in chirOpt) {
            if (!resp.directUses.body.contains(src)) {
                resp.directUses.body[src] = HashSet<Decl>()
            }
            for (use in uses) {
                if (let Some(decl) <- mangled2Decl.get(use)) { resp.directUses.body[src].add(decl) }
            }
        }
    }

    private func CollectRelation(mangle: RawMangledName, relation: SemaRelation): Unit {
        for (extendName in relation.extends) { rest.AddExtend(mangle, extendName) }
        for (interfaceName in relation.extendedInterfaces) {
            if (!rest.interfaceExtendTypes.contains(interfaceName)) {
                rest.interfaceExtendTypes[interfaceName] = HashSet<RawMangledName>()
            }
            rest.interfaceExtendTypes[interfaceName].add(mangle)
        }
        if (let Some(decl) <- mangled2Decl.get(mangle)) {
            for (typeName in relation.inherits) {
                if (let Some(parent) <- mangled2Decl.get(typeName)) { rest.AddParent(parent, decl) }
            }
        }
    }

    private func CollectBuiltinRelation(name: String, relation: SemaRelation): Unit {
        for (extendName in relation.extends) { rest.AddExtend(name, extendName) }
        for (interfaceName in relation.extendedInterfaces) {
            if (!rest.interfaceExtendTypes.contains(interfaceName)) {
                rest.interfaceExtendTypes[interfaceName] = HashSet<RawMangledName>()
            }
            rest.interfaceExtendTypes[interfaceName].add(name)
        }
    }

    private func GetUnqualifiedUsageScope(decl: Decl): Decl {
        if (let None <- decl.outerDecl) {
            return pdecl
        }
        var outer = decl.outerDecl.getOrThrow()
        while (outer.outerDecl.isSome()) { outer = outer.outerDecl.getOrThrow() }
        return outer
    }

    private func CollectUsedNameInfo(decl: Decl, usedName: String, usage: NameUsage, index: Idx): Unit {
        for (qualifier in usage.packageQualifiers) {
            if (!resp.pqUses[index].contains(usedName)) {
                resp.pqUses[index][usedName] = HashMap<String, HashSet<Decl>>()
            }
            if (!resp.pqUses[index][usedName].contains(qualifier)) {
                resp.pqUses[index][usedName][qualifier] = HashSet<Decl>()
            }
            resp.pqUses[index][usedName][qualifier].add(decl)
        }
        for (parent in usage.parentDecls) {
            let key = QualifiedUsage(parent, usedName)
            if (!resp.qUses[index].contains(key)) { resp.qUses[index][key] = HashSet<Decl>() }
            resp.qUses[index][key].add(decl)
        }
        let scope = GetUnqualifiedUsageScope(decl)
        if (usage.hasUnqualifiedUsageOfImported) {
            if (!resp.unqUsesOfImported[index].contains(usedName)) {
                resp.unqUsesOfImported[index][usedName] = HashMap<Decl, HashSet<Decl>>()
            }
            if (!resp.unqUsesOfImported[index][usedName].contains(scope)) {
                resp.unqUsesOfImported[index][usedName][scope] = HashSet<Decl>()
            }
            resp.unqUsesOfImported[index][usedName][scope].add(decl)
        }
        if (usage.hasUnqualifiedUsage || usage.hasUnqualifiedUsageOfImported) {
            if (!resp.unqUses[index].contains(usedName)) {
                resp.unqUses[index][usedName] = HashMap<Decl, HashSet<Decl>>()
            }
            if (!resp.unqUses[index][usedName].contains(scope)) {
                resp.unqUses[index][usedName][scope] = HashSet<Decl>()
            }
            resp.unqUses[index][usedName][scope].add(decl)
        }
    }

    private func CollectUseInfo(decl: Decl, info: UseInfo, index: Idx): Unit {
        for (usedDecl in info.usedDecls) {
            if (!resp.directUses[index].contains(usedDecl)) {
                resp.directUses[index][usedDecl] = HashSet<Decl>()
            }
            resp.directUses[index][usedDecl].add(decl)
        }
        for ((name, usage) in info.usedNames) { CollectUsedNameInfo(decl, name, usage, index) }
    }

    private func CollectPopulation(enclosingDecl: Decl, usage: SemaUsage): Unit {
        CollectUseInfo(enclosingDecl, usage.apiUsages, Idx.API)
        CollectUseInfo(enclosingDecl, usage.bodyUsages, Idx.BODY)
        for (name in usage.boxedTypes) {
            if (!resp.boxUses.contains(name)) { resp.boxUses[name] = ArrayList<Decl>() }
            resp.boxUses[name].add(enclosingDecl)
        }
    }

    private func CollectSourceImportedPopulation(src: Decl, dsts: HashSet<Decl>): Unit {
        if (!resp.directUses.body.contains(src.rawMangleName)) {
            resp.directUses.body[src.rawMangleName] = HashSet<Decl>()
        }
        for (dst in dsts) { resp.directUses.body[src.rawMangleName].add(dst) }
    }

    private func CollectAlias(importManager: SemaImportManager, pkg: Package): Unit {
        for (file in pkg.files) {
            for (importSpec in file.imports) {
                if (!importSpec.IsImportAlias() && !importSpec.IsImportSingle()) { continue }
                let content = importSpec.content
                let prefix = content.GetPrefixPath()
                let mayBeName = content.GetImportedPackageName()
                let name = if (importSpec.IsImportAlias()) { content.aliasName } else { content.identifier }
                if (importManager.GetPackageDecl(mayBeName).isSome()) {
                    if (!resp.packageAliasMap.contains(mayBeName)) {
                        resp.packageAliasMap[mayBeName] = HashSet<String>()
                    }
                    resp.packageAliasMap[mayBeName].add(name.Val())
                } else {
                    if (!resp.declAliasMap.contains(prefix)) {
                        resp.declAliasMap[prefix] = HashMap<String, HashSet<String>>()
                    }
                    if (!resp.declAliasMap[prefix].contains(content.identifier.Val())) {
                        resp.declAliasMap[prefix][content.identifier.Val()] = HashSet<String>()
                    }
                    resp.declAliasMap[prefix][content.identifier.Val()].add(content.aliasName.Val())
                }
            }
        }
    }
}
