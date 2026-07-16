package cjcj::incremental_compilation

import std.collection.*
import std.sort.*
import cjcj::ast.Decl
import cjcj::flatbuffers.{FlatBufferBuilder, FlatBufferOffset, FlatBufferString, Offset, Vector}
import cjcj::utils.CJC_ASSERT

private let NAME_INFO_CONDITION_SIZE: UInt32 = 2u32

func CreateNameUsages(builder: FlatBufferBuilder,
    nameUsages: HashMap<String, NameUsage>): ArrayList<FlatBufferOffset> {
    let names = ArrayList<String>()
    for ((name, _) in nameUsages) { names.add(name) }
    sort(names)
    let result = ArrayList<FlatBufferOffset>()
    for (name in names) {
        let usage = nameUsages[name]
        let conditions = ArrayList<Bool>()
        conditions.add(usage.hasUnqualifiedUsage)
        conditions.add(usage.hasUnqualifiedUsageOfImported)
        let parents = ArrayList<String>()
        for (parent in usage.parentDecls) { parents.add(parent) }
        sort(parents)
        let qualifiers = ArrayList<String>()
        for (qualifier in usage.packageQualifiers) { qualifiers.add(qualifier) }
        sort(qualifiers)
        result.add(CreateNameInfo(builder, builder.CreateSharedString(name),
            builder.CreateVectorBool(conditions), builder.CreateVectorOfStrings(parents),
            builder.CreateVectorOfStrings(qualifiers)))
    }
    return result
}

func CreateUseInfos(builder: FlatBufferBuilder, usage: UseInfo): FlatBufferOffset {
    let usedDecls = ArrayList<String>()
    for (decl in usage.usedDecls) { usedDecls.add(decl) }
    sort(usedDecls)
    return CreateUseInfo(builder, builder.CreateVectorOfStrings(usedDecls),
        builder.CreateVectorOffsets(CreateNameUsages(builder, usage.usedNames)))
}

func CreateUsages(builder: FlatBufferBuilder,
    unorderedUsageMap: HashMap<Decl, SemaUsage>): ArrayList<FlatBufferOffset> {
    let orderedUsages = HashMap<String, SemaUsage>()
    let orderedNames = ArrayList<String>()
    for ((decl, usage) in unorderedUsageMap) {
        if (!orderedUsages.contains(decl.rawMangleName)) {
            orderedUsages[decl.rawMangleName] = usage
            orderedNames.add(decl.rawMangleName)
        }
    }
    sort(orderedNames)
    let result = ArrayList<FlatBufferOffset>()
    for (rawMangleName in orderedNames) {
        let usage = orderedUsages[rawMangleName]
        let boxedTypes = ArrayList<String>()
        for (boxedType in usage.boxedTypes) { boxedTypes.add(boxedType) }
        sort(boxedTypes)
        result.add(CreateUsage(builder, builder.CreateSharedString(rawMangleName),
            CreateUseInfos(builder, usage.apiUsages), CreateUseInfos(builder, usage.bodyUsages),
            builder.CreateVectorOfStrings(boxedTypes)))
    }
    return result
}

func CreateAddedRelations(builder: FlatBufferBuilder,
    relations: HashMap<RawMangledName, HashSet<RawMangledName>>): ArrayList<FlatBufferOffset> {
    let result = ArrayList<FlatBufferOffset>()
    for ((declMangle, relation) in relations) {
        let related = ArrayList<String>()
        for (mangle in relation) { related.add(mangle) }
        sort(related)
        result.add(CreateCompilerAddedUsage(builder, builder.CreateSharedString(declMangle),
            builder.CreateVectorOfStrings(related)))
    }
    return result
}

func CreateRelations(builder: FlatBufferBuilder,
    relations: HashMap<RawMangledName, SemaRelation>): ArrayList<FlatBufferOffset> {
    let orderedNames = ArrayList<String>()
    for ((declMangle, _) in relations) { orderedNames.add(declMangle) }
    sort(orderedNames)
    let result = ArrayList<FlatBufferOffset>()
    for (declMangle in orderedNames) {
        let relation = relations[declMangle]
        let inherited = ArrayList<String>()
        for (mangle in relation.inherits) { inherited.add(mangle) }
        sort(inherited)
        let extends = ArrayList<String>()
        for (mangle in relation.extends) { extends.add(mangle) }
        sort(extends)
        let extendInterfaces = ArrayList<String>()
        for (mangle in relation.extendedInterfaces) { extendInterfaces.add(mangle) }
        sort(extendInterfaces)
        result.add(CreateRelation(builder, builder.CreateSharedString(declMangle),
            builder.CreateVectorOfStrings(inherited), builder.CreateVectorOfStrings(extends),
            builder.CreateVectorOfStrings(extendInterfaces)))
    }
    return result
}

func GetSetStrings(data: Option<Vector<Offset<Any>>>): HashSet<String> {
    let result = HashSet<String>()
    if (let Some(values) <- data) {
        var idx: UInt32 = 0u32
        while (idx < values.size()) {
            result.add(FlatBufferString(values.data, (values.Get(idx) as Int64).getOrThrow()).str())
            idx++
        }
    }
    return result
}

func GetNameUsage(info: Option<CachedASTFormat_NameInfo>): NameUsage {
    if (let None <- info) { return NameUsage() }
    let nameInfo = info.getOrThrow()
    let usage = NameUsage()
    for (parent in GetSetStrings(nameInfo.parentDecls())) { usage.parentDecls.add(parent) }
    for (qualifier in GetSetStrings(nameInfo.qualifiers())) { usage.packageQualifiers.add(qualifier) }
    let conditions = nameInfo.conditions().getOrThrow()
    CJC_ASSERT(conditions.size() == NAME_INFO_CONDITION_SIZE)
    usage.hasUnqualifiedUsage = (conditions.Get(0u32) as Bool).getOrThrow()
    usage.hasUnqualifiedUsageOfImported = (conditions.Get(1u32) as Bool).getOrThrow()
    return usage
}

func GetUseInfo(usage: Option<CachedASTFormat_UseInfo>): UseInfo {
    if (let None <- usage) { return UseInfo() }
    let cachedUsage = usage.getOrThrow()
    let result = UseInfo()
    for (decl in GetSetStrings(cachedUsage.usedDecls())) { result.usedDecls.add(decl) }
    if (let Some(usedNames) <- cachedUsage.usedNames()) {
        var idx: UInt32 = 0u32
        while (idx < usedNames.size()) {
            let nameInfo = CachedASTFormat_NameInfo(usedNames.data,
                (usedNames.Get(idx) as Int64).getOrThrow())
            result.usedNames[nameInfo.name().getOrThrow().str()] = GetNameUsage(Some(nameInfo))
            idx++
        }
    }
    return result
}
