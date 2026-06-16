package cangjie_compiler::incremental_compilation

import std.collection.*

public func CopySemanticInfo(source: SemanticInfo): SemanticInfo {
    let out = SemanticInfo()
    for ((decl, usage) in source.usages) {
        let usageCopy = SemaUsage()
        copyUseInfo(usage.apiUsages, usageCopy.apiUsages)
        copyUseInfo(usage.bodyUsages, usageCopy.bodyUsages)
        for (name in usage.boxedTypes) {
            usageCopy.boxedTypes.add(name)
        }
        out.usages[decl] = usageCopy
    }
    for ((name, relation) in source.relations) {
        out.relations[name] = copyRelation(relation)
    }
    for ((name, relation) in source.builtInTypeRelations) {
        out.builtInTypeRelations[name] = copyRelation(relation)
    }
    for ((name, related) in source.compilerAddedUsages) {
        out.compilerAddedUsages[name] = CloneStringSet(related)
    }
    return out
}

private func copyUseInfo(source: UseInfo, target: UseInfo): Unit {
    for (name in source.usedDecls) {
        target.usedDecls.add(name)
    }
    for ((name, usage) in source.usedNames) {
        let usageCopy = NameUsage()
        for (parent in usage.parentDecls) {
            usageCopy.parentDecls.add(parent)
        }
        for (qualifier in usage.packageQualifiers) {
            usageCopy.packageQualifiers.add(qualifier)
        }
        usageCopy.hasUnqualifiedUsage = usage.hasUnqualifiedUsage
        usageCopy.hasUnqualifiedUsageOfImported = usage.hasUnqualifiedUsageOfImported
        target.usedNames[name] = usageCopy
    }
}

private func copyRelation(source: SemaRelation): SemaRelation {
    let relation = SemaRelation()
    for (name in source.inherits) {
        relation.inherits.add(name)
    }
    for (name in source.extends) {
        relation.extends.add(name)
    }
    for (name in source.extendedInterfaces) {
        relation.extendedInterfaces.add(name)
    }
    return relation
}
