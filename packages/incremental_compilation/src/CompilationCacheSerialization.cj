package cangjie_compiler::incremental_compilation

import std.collection.*
import std.fs.File
import std.sort.*

private let CACHE_WIRE_VERSION: String = "CJ-INCR-CACHE-1"

public class HashedASTWriter {
    private let bitcodeFilesName: ArrayList<String> = ArrayList<String>()
    private let compileArgs: ArrayList<String> = ArrayList<String>()
    private let varAndFunc: ArrayList<DeclDependency> = ArrayList<DeclDependency>()
    private let chirOptInfo: OptEffectStrMap = OptEffectStrMap()
    private let virtualFuncDep: VirtualWrapperDepMap = VirtualWrapperDepMap()
    private let varInitDep: VarInitDepMap = VarInitDepMap()
    private let ccOutFuncs: HashSet<String> = HashSet<String>()
    private var semaUsages: SemanticInfo = SemanticInfo()
    private let allAST: ASTCache = ASTCache()
    private let importedDecls: ASTCache = ASTCache()
    private let order: ArrayList<String> = ArrayList<String>()
    private var lambdaCounter: UInt64 = 0u64
    private var envClassCounter: UInt64 = 0u64
    private var stringLiteralCounter: UInt64 = 0u64
    private var specs: UInt64 = 0u64

    public init() {}

    public func SetImportSpecs(pkg: IncrPackage): Unit {
        specs = if (pkg.specsHash != 0u64) { pkg.specsHash } else { StableHash(pkg.fullPackageName) }
    }

    public func SetLambdaCounter(counter: UInt64): Unit {
        lambdaCounter = counter
    }

    public func SetEnvClassCounter(counter: UInt64): Unit {
        envClassCounter = counter
    }

    public func SetStringLiteralCounter(counter: UInt64): Unit {
        stringLiteralCounter = counter
    }

    public func SetCompileArgs(args: ArrayList<String>): Unit {
        compileArgs.clear()
        for (arg in args) {
            compileArgs.add(arg)
        }
    }

    public func SetVarAndFuncDependency(varAndFuncDep: ArrayList<DeclDependency>): Unit {
        varAndFunc.clear()
        for (dep in varAndFuncDep) {
            varAndFunc.add(dep)
        }
    }

    public func SetCHIROptInfo(optInfo: OptEffectStrMap): Unit {
        chirOptInfo.clear()
        for ((src, values) in optInfo) {
            chirOptInfo[src] = CloneStringSet(values)
        }
    }

    public func SetVirtualFuncDep(depMap: VirtualWrapperDepMap): Unit {
        virtualFuncDep.clear()
        for ((raw, wrapper) in depMap) {
            virtualFuncDep[raw] = wrapper
        }
    }

    public func SetVarInitDep(depMap: VarInitDepMap): Unit {
        varInitDep.clear()
        for ((raw, wrapper) in depMap) {
            varInitDep[raw] = wrapper
        }
    }

    public func SetCCOutFuncs(funcs: HashSet<String>): Unit {
        ccOutFuncs.clear()
        for (funcName in funcs) {
            ccOutFuncs.add(funcName)
        }
    }

    public func SetBitcodeFilesName(bitcodeFiles: ArrayList<String>): Unit {
        bitcodeFilesName.clear()
        for (file in bitcodeFiles) {
            bitcodeFilesName.add(file)
        }
    }

    public func SetSemanticInfo(info: SemanticInfo): Unit {
        semaUsages = info
    }

    public func WriteAllDecls(ast: ASTCache, imports: ASTCache, writeOrder: ArrayList<IncrDecl>): Unit {
        allAST.clear()
        importedDecls.clear()
        order.clear()
        for ((name, cache) in ast) {
            allAST[name] = cache.Clone()
        }
        for ((name, cache) in imports) {
            importedDecls[name] = cache.Clone()
        }
        for (decl in writeOrder) {
            if (!decl.rawMangleName.isEmpty() && allAST.contains(decl.rawMangleName)) {
                order.add(decl.rawMangleName)
            }
        }
    }

    public func AST2FB(pkgName: String): Array<UInt8> {
        // Encodes the same CachedASTFormat fields used by the C++ cache in a deterministic package-local wire format.
        let lines = ArrayList<String>()
        let header = ArrayList<String>()
        header.add("header")
        header.add(CACHE_WIRE_VERSION)
        header.add(pkgName)
        header.add(U64ToWire(specs))
        header.add(U64ToWire(lambdaCounter))
        header.add(U64ToWire(envClassCounter))
        header.add(U64ToWire(stringLiteralCounter))
        lines.add(JoinCacheFields(header))
        appendStringList(lines, "arg", compileArgs)
        appendStringList(lines, "bitcode", bitcodeFilesName)
        appendStringSet(lines, "ccout", ccOutFuncs)
        appendEffectMap(lines, "chir", chirOptInfo)
        appendStringMap(lines, "virtual", virtualFuncDep)
        appendStringMap(lines, "varinit", varInitDep)
        appendDependencies(lines)
        appendSemanticInfo(lines)
        appendAST(lines, "top", allAST, order)
        let importedOrder = ArrayList<String>()
        for ((name, _) in importedDecls) {
            importedOrder.add(name)
        }
        appendAST(lines, "import", importedDecls, SortedStringList(importedOrder))
        return JoinStrings(lines, "\n").toArray()
    }

    private func appendStringList(lines: ArrayList<String>, tag: String, values: ArrayList<String>): Unit {
        for (value in values) {
            let fields = ArrayList<String>()
            fields.add(tag)
            fields.add(value)
            lines.add(JoinCacheFields(fields))
        }
    }

    private func appendStringSet(lines: ArrayList<String>, tag: String, values: HashSet<String>): Unit {
        for (value in SortedStringSet(values)) {
            let fields = ArrayList<String>()
            fields.add(tag)
            fields.add(value)
            lines.add(JoinCacheFields(fields))
        }
    }

    private func appendStringMap(lines: ArrayList<String>, tag: String, values: HashMap<String, String>): Unit {
        let keys = ArrayList<String>()
        for ((key, _) in values) {
            keys.add(key)
        }
        for (key in SortedStringList(keys)) {
            let fields = ArrayList<String>()
            fields.add(tag)
            fields.add(key)
            fields.add(values[key])
            lines.add(JoinCacheFields(fields))
        }
    }

    private func appendEffectMap(lines: ArrayList<String>, tag: String, values: OptEffectStrMap): Unit {
        let keys = ArrayList<String>()
        for ((key, _) in values) {
            keys.add(key)
        }
        for (key in SortedStringList(keys)) {
            let fields = ArrayList<String>()
            fields.add(tag)
            fields.add(key)
            fields.add(StringSetToWire(values[key]))
            lines.add(JoinCacheFields(fields))
        }
    }

    private func appendDependencies(lines: ArrayList<String>): Unit {
        for (dep in varAndFunc) {
            let names = ArrayList<String>()
            for (value in dep.dependencies) {
                names.add(value.rawMangleName)
            }
            let fields = ArrayList<String>()
            fields.add("dep")
            fields.add(dep.decl.rawMangleName)
            fields.add(JoinCacheStringList(SortedStringList(names)))
            lines.add(JoinCacheFields(fields))
        }
    }

    private func appendSemanticInfo(lines: ArrayList<String>): Unit {
        for ((decl, usage) in semaUsages.usages) {
            let fields = ArrayList<String>()
            fields.add("usage")
            fields.add(decl.rawMangleName)
            fields.add(StringSetToWire(usage.apiUsages.usedDecls))
            fields.add(StringSetToWire(usage.bodyUsages.usedDecls))
            fields.add(StringSetToWire(usage.boxedTypes))
            lines.add(JoinCacheFields(fields))
            appendNameUsages(lines, decl.rawMangleName, "api", usage.apiUsages.usedNames)
            appendNameUsages(lines, decl.rawMangleName, "body", usage.bodyUsages.usedNames)
        }
        appendRelations(lines, "relation", semaUsages.relations)
        appendRelations(lines, "builtin-relation", semaUsages.builtInTypeRelations)
        for ((decl, related) in semaUsages.compilerAddedUsages) {
            let fields = ArrayList<String>()
            fields.add("compiler-added")
            fields.add(decl)
            fields.add(StringSetToWire(related))
            lines.add(JoinCacheFields(fields))
        }
    }

    private func appendNameUsages(lines: ArrayList<String>, decl: String, phase: String,
        names: HashMap<String, NameUsage>): Unit {
        for ((name, usage) in names) {
            let fields = ArrayList<String>()
            fields.add("nameusage")
            fields.add(decl)
            fields.add(phase)
            fields.add(name)
            fields.add(StringSetToWire(usage.parentDecls))
            fields.add(StringSetToWire(usage.packageQualifiers))
            fields.add(BoolToWire(usage.hasUnqualifiedUsage))
            fields.add(BoolToWire(usage.hasUnqualifiedUsageOfImported))
            lines.add(JoinCacheFields(fields))
        }
    }

    private func appendRelations(lines: ArrayList<String>, tag: String,
        relations: HashMap<String, SemaRelation>): Unit {
        for ((decl, relation) in relations) {
            let fields = ArrayList<String>()
            fields.add(tag)
            fields.add(decl)
            fields.add(StringSetToWire(relation.inherits))
            fields.add(StringSetToWire(relation.extends))
            fields.add(StringSetToWire(relation.extendedInterfaces))
            lines.add(JoinCacheFields(fields))
        }
    }

    private func appendAST(lines: ArrayList<String>, tag: String, ast: ASTCache, writeOrder: ArrayList<String>): Unit {
        for (mangle in writeOrder) {
            if (let Some(cache) <- ast.get(mangle)) {
                appendTopDecl(lines, tag, mangle, cache)
            }
        }
    }

    private func appendTopDecl(lines: ArrayList<String>, tag: String, mangle: String,
        cache: TopLevelDeclCache): Unit {
        let fields = commonCacheFields(tag, mangle, cache)
        fields.add(U64ToWire(cache.instVarHash))
        fields.add(U64ToWire(cache.virtHash))
        fields.add(JoinCacheStringList(cache.extends))
        lines.add(JoinCacheFields(fields))
        for (member in cache.members) {
            appendMemberDecl(lines, tag + "-member", mangle, member)
        }
    }

    private func appendMemberDecl(lines: ArrayList<String>, tag: String, parent: String,
        cache: MemberDeclCache): Unit {
        let fields = commonCacheFields(tag, cache.rawMangle, cache)
        fields.add(parent)
        lines.add(JoinCacheFields(fields))
        for (member in cache.members) {
            appendMemberDecl(lines, tag, cache.rawMangle, member)
        }
    }

    private func commonCacheFields(tag: String, mangle: String, cache: DeclCacheBase): ArrayList<String> {
        let fields = ArrayList<String>()
        fields.add(tag)
        fields.add(mangle)
        fields.add(U64ToWire(cache.sigHash))
        fields.add(U64ToWire(cache.srcUse))
        fields.add(U64ToWire(cache.bodyHash))
        fields.add(cache.astKind.toString())
        fields.add(BoolToWire(cache.isGV))
        fields.add(cache.gvid.file)
        fields.add(I64ToWire(cache.gvid.id))
        fields.add(cache.cgMangle)
        return fields
    }
}

public class HashedASTLoader {
    private let serializedData: Array<UInt8>
    private let fileMap: HashMap<String, ArrayList<(String, Int64)>> = HashMap<String, ArrayList<(String, Int64)>>()

    public init(astData: Array<UInt8>) {
        serializedData = astData
    }

    public func DeserializeData(mangledName2DeclMap: RawMangled2DeclMap): (Bool, CompilationCache) {
        let text = String.fromUtf8(serializedData)
        let lines = SplitCacheRawLines(text)
        if (lines.isEmpty()) {
            return (false, CompilationCache())
        }
        let first = SplitCacheFields(lines[0])
        if (first.size < 7 || first[0] != "header" || first[1] != CACHE_WIRE_VERSION) {
            return (false, CompilationCache())
        }
        let cached = CompilationCache()
        cached.specs = WireToU64(first[3])
        cached.lambdaCounter = WireToU64(first[4])
        cached.envClassCounter = WireToU64(first[5])
        cached.stringLiteralCounter = WireToU64(first[6])

        let topMemberOwners = HashMap<String, DeclCacheBase>()
        var idx: Int64 = 1
        while (idx < lines.size) {
            let fields = SplitCacheFields(lines[idx])
            if (!fields.isEmpty()) {
                loadLine(fields, cached, mangledName2DeclMap, topMemberOwners)
            }
            idx++
        }
        buildCachedFileMap(cached)
        return (true, cached)
    }

    private func loadLine(fields: ArrayList<String>, cached: CompilationCache,
        mangledName2DeclMap: RawMangled2DeclMap, owners: HashMap<String, DeclCacheBase>): Unit {
        let tag = fields[0]
        if (tag == "arg" && fields.size >= 2) {
            cached.compileArgs.add(fields[1])
        } else if (tag == "bitcode" && fields.size >= 2) {
            cached.bitcodeFilesName.add(fields[1])
        } else if (tag == "ccout" && fields.size >= 2) {
            cached.ccOutFuncs.add(fields[1])
        } else if (tag == "chir" && fields.size >= 3) {
            cached.chirOptInfo[fields[1]] = WireToStringSet(fields[2])
        } else if (tag == "virtual" && fields.size >= 3) {
            cached.virtualFuncDep[fields[1]] = fields[2]
        } else if (tag == "varinit" && fields.size >= 3) {
            cached.varInitDepMap[fields[1]] = fields[2]
        } else if (tag == "dep" && fields.size >= 3) {
            loadDependency(fields, cached, mangledName2DeclMap)
        } else if (tag == "usage" && fields.size >= 5) {
            loadUsage(fields, cached, mangledName2DeclMap)
        } else if (tag == "nameusage" && fields.size >= 8) {
            loadNameUsage(fields, cached, mangledName2DeclMap)
        } else if ((tag == "relation" || tag == "builtin-relation") && fields.size >= 5) {
            loadRelation(tag, fields, cached)
        } else if (tag == "compiler-added" && fields.size >= 3) {
            cached.semaInfo.compilerAddedUsages[fields[1]] = WireToStringSet(fields[2])
        } else if ((tag == "top" || tag == "import") && fields.size >= 13) {
            loadTop(tag, fields, cached, owners)
        } else if ((tag == "top-member" || tag == "import-member") && fields.size >= 11) {
            loadMember(fields, owners)
        }
    }

    private func loadDependency(fields: ArrayList<String>, cached: CompilationCache,
        mangledName2DeclMap: RawMangled2DeclMap): Unit {
        if (let Some(decl) <- mangledName2DeclMap.get(fields[1])) {
            let dep = DeclDependency(decl)
            for (name in SplitCacheStringList(fields[2])) {
                if (let Some(value) <- mangledName2DeclMap.get(name)) {
                    dep.dependencies.add(value)
                }
            }
            cached.varAndFuncDep.add(dep)
        }
    }

    private func loadUsage(fields: ArrayList<String>, cached: CompilationCache,
        mangledName2DeclMap: RawMangled2DeclMap): Unit {
        if (let Some(decl) <- mangledName2DeclMap.get(fields[1])) {
            if (!cached.semaInfo.usages.contains(decl)) {
                cached.semaInfo.usages[decl] = SemaUsage()
            }
            let usage = cached.semaInfo.usages[decl]
            for (name in WireToStringSet(fields[2])) {
                usage.apiUsages.usedDecls.add(name)
            }
            for (name in WireToStringSet(fields[3])) {
                usage.bodyUsages.usedDecls.add(name)
            }
            for (name in WireToStringSet(fields[4])) {
                usage.boxedTypes.add(name)
            }
        }
    }

    private func loadNameUsage(fields: ArrayList<String>, cached: CompilationCache,
        mangledName2DeclMap: RawMangled2DeclMap): Unit {
        if (let Some(decl) <- mangledName2DeclMap.get(fields[1])) {
            if (!cached.semaInfo.usages.contains(decl)) {
                cached.semaInfo.usages[decl] = SemaUsage()
            }
            let usage = cached.semaInfo.usages[decl]
            let target = if (fields[2] == "api") { usage.apiUsages } else { usage.bodyUsages }
            let nameUsage = NameUsage()
            for (name in WireToStringSet(fields[4])) {
                nameUsage.parentDecls.add(name)
            }
            for (name in WireToStringSet(fields[5])) {
                nameUsage.packageQualifiers.add(name)
            }
            nameUsage.hasUnqualifiedUsage = WireToBool(fields[6])
            nameUsage.hasUnqualifiedUsageOfImported = WireToBool(fields[7])
            target.usedNames[fields[3]] = nameUsage
        }
    }

    private func loadRelation(tag: String, fields: ArrayList<String>, cached: CompilationCache): Unit {
        let relation = SemaRelation()
        for (name in WireToStringSet(fields[2])) {
            relation.inherits.add(name)
        }
        for (name in WireToStringSet(fields[3])) {
            relation.extends.add(name)
        }
        for (name in WireToStringSet(fields[4])) {
            relation.extendedInterfaces.add(name)
        }
        if (tag == "relation") {
            cached.semaInfo.relations[fields[1]] = relation
        } else {
            cached.semaInfo.builtInTypeRelations[fields[1]] = relation
        }
    }

    private func loadTop(tag: String, fields: ArrayList<String>, cached: CompilationCache,
        owners: HashMap<String, DeclCacheBase>): Unit {
        let top = TopLevelDeclCache()
        fillCommon(fields, top)
        top.instVarHash = WireToU64(fields[10])
        top.virtHash = WireToU64(fields[11])
        for (ext in SplitCacheStringList(fields[12])) {
            top.extends.add(ext)
        }
        if (tag == "top") {
            cached.curPkgASTCache[fields[1]] = top
            collectFileMapForTop(fields[1], top)
        } else {
            cached.importedASTCache[fields[1]] = top
        }
        owners[fields[1]] = top
    }

    private func loadMember(fields: ArrayList<String>, owners: HashMap<String, DeclCacheBase>): Unit {
        let member = MemberDeclCache(fields[1])
        fillCommon(fields, member)
        let parent = fields[10]
        if (let Some(owner) <- owners.get(parent)) {
            owner.members.add(member)
        }
        owners[member.rawMangle] = member
        collectFileMapForMember(member)
    }

    private func fillCommon(fields: ArrayList<String>, cache: DeclCacheBase): Unit {
        cache.sigHash = WireToU64(fields[2])
        cache.srcUse = WireToU64(fields[3])
        cache.bodyHash = WireToU64(fields[4])
        cache.astKind = UInt8(WireToI64(fields[5]))
        cache.isGV = WireToBool(fields[6])
        cache.gvid = GlobalVarIndex(fields[7], WireToI64(fields[8]))
        cache.cgMangle = fields[9]
    }

    private func collectFileMapForTop(mangle: String, cache: TopLevelDeclCache): Unit {
        let kind = IncrDeclKindFromIndex(Int64(cache.astKind))
        if (isOOEAffectedKind(kind) && !(kind == IncrDeclKind.VAR_DECL && !cache.isGV)) {
            addFileMapEntry(cache.gvid.file, mangle, cache.gvid.id)
        }
    }

    private func collectFileMapForMember(member: MemberDeclCache): Unit {
        let kind = IncrDeclKindFromIndex(Int64(member.astKind))
        if (member.isGV || isOOEAffectedKind(kind)) {
            addFileMapEntry(member.gvid.file, member.rawMangle, member.gvid.id)
        }
    }

    private func isOOEAffectedKind(kind: IncrDeclKind): Bool {
        return kind == IncrDeclKind.VAR_DECL || kind == IncrDeclKind.VAR_WITH_PATTERN_DECL ||
            kind == IncrDeclKind.FUNC_DECL || kind == IncrDeclKind.MAIN_DECL ||
            kind == IncrDeclKind.MACRO_DECL || kind == IncrDeclKind.PRIMARY_CTOR_DECL
    }

    private func addFileMapEntry(file: String, mangle: String, id: Int64): Unit {
        if (file.isEmpty()) {
            return
        }
        if (!fileMap.contains(file)) {
            fileMap[file] = ArrayList<(String, Int64)>()
        }
        fileMap[file].add((mangle, id))
    }

    private func buildCachedFileMap(cached: CompilationCache): Unit {
        for ((file, values) in fileMap) {
            sortPairs(values)
            let names = ArrayList<String>()
            for (pair in values) {
                names.add(pair[0])
            }
            cached.fileMap[file] = names
        }
    }

    private func sortPairs(values: ArrayList<(String, Int64)>): Unit {
        sort(values, by: { left: (String, Int64), right: (String, Int64) =>
            if (left[1] < right[1]) {
                Ordering.LT
            } else if (left[1] > right[1]) {
                Ordering.GT
            } else {
                CompareStrings(left[0], right[0])
            }
        }, stable: true)
    }
}

public func WriteCache(pkg: IncrPackage, cachedInfo: CompilationCache, writeOrder: ArrayList<IncrDecl>,
    path: String): Bool {
    let writer = HashedASTWriter()
    writer.SetImportSpecs(pkg)
    writer.SetLambdaCounter(cachedInfo.lambdaCounter)
    writer.SetEnvClassCounter(cachedInfo.envClassCounter)
    writer.SetStringLiteralCounter(cachedInfo.stringLiteralCounter)
    writer.SetCompileArgs(cachedInfo.compileArgs)
    writer.SetVarAndFuncDependency(cachedInfo.varAndFuncDep)
    writer.SetCHIROptInfo(cachedInfo.chirOptInfo)
    writer.SetVirtualFuncDep(cachedInfo.virtualFuncDep)
    writer.SetVarInitDep(cachedInfo.varInitDepMap)
    writer.SetCCOutFuncs(cachedInfo.ccOutFuncs)
    writer.SetSemanticInfo(cachedInfo.semaInfo)
    writer.SetBitcodeFilesName(cachedInfo.bitcodeFilesName)
    writer.WriteAllDecls(cachedInfo.curPkgASTCache, cachedInfo.importedASTCache, writeOrder)
    try {
        File.writeTo(path, writer.AST2FB(pkg.fullPackageName))
        return true
    } catch (e: Exception) {
        return false
    }
}
