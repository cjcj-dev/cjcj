package cangjie_compiler::incremental_compilation

import std.collection.*
import std.fs.File
import std.fs.exists
import cangjie_compiler::option.GlobalOptions

public class IncreResult {
    public var kind: IncreKind = IncreKind.INVALID
    public let declsToRecompile: HashSet<IncrDecl> = HashSet<IncrDecl>()
    public let deleted: ArrayList<String> = ArrayList<String>()
    public let deletedMangleNames: ArrayList<String> = ArrayList<String>()
    public var cacheInfo: CompilationCache = CompilationCache()
    public var mangle2decl: RawMangled2DeclMap = RawMangled2DeclMap()
    public let reBoxedTypes: ArrayList<String> = ArrayList<String>()

    public init() {}

    public init(kind: IncreKind, cacheInfo: CompilationCache, mangle2decl: RawMangled2DeclMap) {
        this.kind = kind
        this.cacheInfo = cacheInfo
        this.mangle2decl = mangle2decl
    }

    public func Dump(): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        if (kind != IncreKind.INCR) {
            if (kind == IncreKind.ROLLBACK) {
                logger.LogLn("incremental compile result kind: rollback")
            } else if (kind == IncreKind.EMPTY_PKG) {
                logger.LogLn("incremental compile result kind: empty package")
            } else if (kind == IncreKind.NO_CHANGE) {
                logger.LogLn("incremental compile result kind: no change")
            } else {
                logger.LogLn("incremental compile result kind: invalid")
            }
            return
        }
        let delimiter = makeDelimiter()
        logger.LogLn(delimiter)
        logger.LogLn("incremental compilation triggered")
        logger.LogLn("begin dump incremental compile result:")
        DumpDeclsToRecompile(declsToRecompile)
        logger.LogLn(delimiter)
        DumpDeleted(deleted)
        logger.LogLn(delimiter)
    }
}

public class IncrementalScopeAnalysisArgs {
    public var rawMangleName2DeclMap: RawMangled2DeclMap = RawMangled2DeclMap()
    public var astCacheInfo: ASTCache = ASTCache()
    public var srcPackage: IncrPackage = IncrPackage()
    public var op: GlobalOptions = GlobalOptions()
    public var importer: IncrImportManager = IncrImportManager()
    public var cachedInfo: Option<CompilationCache> = None
    public var fileMap: FileMap = FileMap()
    public var directExtends: HashMap<String, ArrayList<DirectExtendEntry>> =
        HashMap<String, ArrayList<DirectExtendEntry>>()

    public init() {}
}

public func MergeCHIROptEffectMap(newMap: OptEffectStrMap, lastCachedMap: OptEffectStrMap,
    rawMangled2Decl: RawMangled2DeclMap): Unit {
    for ((src, affected) in newMap) {
        if (src.isEmpty() || affected.isEmpty()) {
            continue
        }
        if (!lastCachedMap.contains(src)) {
            lastCachedMap[src] = HashSet<String>()
        }
        for (name in affected) {
            if (!name.isEmpty() && name != src) {
                lastCachedMap[src].add(name)
            }
        }
    }
    PrintCHIROptEffectMap(lastCachedMap, rawMangled2Decl)
}

public func DeleteRemovedNodesInCHIROptEffectMap(removedDecls: ArrayList<String>, effectMap: OptEffectStrMap): Unit {
    let removed = HashSet<String>()
    for (name in removedDecls) {
        removed.add(name)
    }
    let keysToRemove = ArrayList<String>()
    for ((src, affected) in effectMap) {
        if (removed.contains(src)) {
            keysToRemove.add(src)
            continue
        }
        let valuesToRemove = ArrayList<String>()
        for (name in affected) {
            if (removed.contains(name)) {
                valuesToRemove.add(name)
            }
        }
        for (name in valuesToRemove) {
            affected.remove(name)
        }
    }
    for (key in keysToRemove) {
        effectMap.remove(key)
    }
}

public func DeleteRecompiledNodesInCHIROptEffectMap(recompiledNodes: HashSet<IncrDecl>,
    effectMap: OptEffectStrMap): Unit {
    let recompiled = HashSet<String>()
    for (decl in recompiledNodes) {
        let rawMangle = GetRecompiledCHIROptRawMangleName(decl)
        if (!rawMangle.isEmpty()) {
            recompiled.add(rawMangle)
        }
    }
    let keysToRemove = ArrayList<String>()
    for ((src, affected) in effectMap) {
        let valuesToRemove = ArrayList<String>()
        for (name in affected) {
            if (recompiled.contains(name)) {
                valuesToRemove.add(name)
            }
        }
        for (name in valuesToRemove) {
            affected.remove(name)
        }
        if (affected.isEmpty()) {
            keysToRemove.add(src)
        }
    }
    for (key in keysToRemove) {
        effectMap.remove(key)
    }
}

public func IncrementalScopeAnalysis(args: IncrementalScopeAnalysisArgs): IncreResult {
    let cachedAstPath = args.op.GenerateCachedPathName(args.srcPackage.fullPackageName, CACHED_AST_EXTENSION)
    let serializedPath = args.op.GenerateCachedPathName(args.srcPackage.fullPackageName, SERIALIZED_FILE_EXTENSION)
    var previousCacheOpt = args.cachedInfo
    if (let None <- previousCacheOpt) {
        previousCacheOpt = LoadCacheInfo(cachedAstPath, args.rawMangleName2DeclMap)
    }
    if (let None <- previousCacheOpt) {
        return TerminateAnalysisAndRollback(CompilationCache(), args,
            "load cached info failed, roll back to full compilation")
    }
    if (!exists(serializedPath)) {
        return TerminateAnalysisAndRollback(CompilationCache(), args,
            "load cached info failed, roll back to full compilation")
    }
    let previousCache = previousCacheOpt.getOrThrow()
    if (!ListsEqual(args.op.ToSerialized(), previousCache.compileArgs)) {
        return TerminateAnalysisAndRollback(previousCache, args,
            "compile args changed, roll back to full compilation")
    }
    let currentSpecs = if (args.srcPackage.specsHash != 0u64) {
        args.srcPackage.specsHash
    } else {
        StableHash(args.srcPackage.fullPackageName)
    }
    if (currentSpecs != previousCache.specs) {
        return TerminateAnalysisAndRollback(previousCache, args,
            "package or import specs changed, roll back to full compilation")
    }

    let imported = ImportPackageWalker.Get(args.srcPackage, args.importer)
    let diffArgs = ASTDiffArgs(previousCache, imported.importedASTCache, imported.importedMangled2Decl,
        args.rawMangleName2DeclMap, args.astCacheInfo, args.fileMap, args.op)
    let diffResult = ASTDiff(diffArgs)
    diffResult.changedDecls.Dump()

    if (!diffResult.changedDecls.aliases.isEmpty()) {
        return TerminateAnalysisAndRollback(previousCache, args,
            "type alias changed, roll back to full compilation")
    }

    let srcPkgDecl = args.importer.GetPackageDecl(args.srcPackage.fullPackageName) ??
        IncrDecl(args.srcPackage.fullPackageName, args.srcPackage.fullPackageName, IncrDeclKind.PACKAGE_DECL)
    let pollutionArgs = PollutionAnalyseArgs(diffResult.changedDecls, srcPkgDecl, imported.sourcePopulations,
        previousCache.semaInfo, previousCache.chirOptInfo, previousCache.fileMap, args.importer,
        diffResult.mangled2Decl, args.directExtends, imported.importRelations)
    let pollutionRes = PollutionAnalyzer.Get(pollutionArgs)
    if (IsCCOutFuncNeedToRecompileOrDelete(previousCache, pollutionRes)) {
        DumpDeclsToRecompile(pollutionRes.declsToRecompile)
        DumpDeleted(pollutionRes.deleted)
        return TerminateAnalysisAndRollback(previousCache, args,
            "closure convert out func recompile, roll back to full compilation")
    }

    if (pollutionRes.kind == IncreKind.INCR) {
        for (decl in pollutionRes.declsToRecompile) {
            decl.toBeCompiled = true
        }
    }
    let deletedMangleNames = GetCgManglesForDelete(previousCache, pollutionRes.deleted)
    previousCache.curPkgASTCache.clear()
    for ((name, cache) in args.astCacheInfo) {
        previousCache.curPkgASTCache[name] = cache.Clone()
    }
    previousCache.importedASTCache.clear()
    for ((name, cache) in imported.importedASTCache) {
        previousCache.importedASTCache[name] = cache.Clone()
    }

    let result = IncreResult()
    result.kind = pollutionRes.kind
    for (decl in pollutionRes.declsToRecompile) {
        result.declsToRecompile.add(decl)
    }
    for (name in pollutionRes.deleted) {
        result.deleted.add(name)
    }
    for (name in deletedMangleNames) {
        result.deletedMangleNames.add(name)
    }
    result.cacheInfo = previousCache
    result.mangle2decl = diffResult.mangled2Decl
    for (name in pollutionRes.reBoxedTypes) {
        result.reBoxedTypes.add(name)
    }
    return result
}

private class ImportPackageWalkerResult {
    public let importedASTCache: ASTCache = ASTCache()
    public let importedMangled2Decl: RawMangled2DeclMap = RawMangled2DeclMap()
    public let sourcePopulations: SrcImportedDepMap = SrcImportedDepMap()
    public let importRelations: TypeMap = TypeMap()

    public init() {}
}

private class ImportPackageWalker {
    public static func Get(sourcePackage: IncrPackage, importManager: IncrImportManager): ImportPackageWalkerResult {
        let result = ImportPackageWalkerResult()
        for (pkg in importManager.GetAllImportedPackages()) {
            if (pkg.fullPackageName == sourcePackage.fullPackageName) {
                continue
            }
            let walker = ImportPackageWalker()
            let decls = pkg.AllTopLevelDecls()
            for (decl in decls) {
                if (decl.rawMangleName.isEmpty()) {
                    decl.rawMangleName = MangleDecl(decl)
                }
                walker.UpdateMangleName(decl)
                walker.RegisterDeclAndMembers(decl, result.importedMangled2Decl)
            }
            for (decl in decls) {
                walker.CollectSourceImportedDependencies(decl, result)
            }
            for (decl in decls) {
                result.importedASTCache[decl.rawMangleName] = walker.VisitTopLevel(decl, result.importedMangled2Decl)
                walker.ResolveInheritedTypeDecls(decl, result.importedMangled2Decl)
                result.importRelations.CollectImportedDeclExtraRelation(decl)
            }
        }
        return result
    }

    private init() {}

    private func VisitTopLevel(decl: IncrDecl, map: RawMangled2DeclMap): TopLevelDeclCache {
        map[decl.rawMangleName] = decl
        let cache = TopLevelDeclCache()
        for (member in GetMembers(decl)) {
            if (!member.rawMangleName.isEmpty()) {
                cache.members.add(VisitMember(member, map))
            }
        }
        cache.instVarHash = decl.cacheHash.instVar
        cache.virtHash = decl.cacheHash.virt
        cache.sigHash = ComputeDeclSigHash(decl)
        cache.srcUse = ComputeDeclSrcUseHash(decl)
        cache.bodyHash = if (SkipImportedBodyHash(decl)) { 0u64 } else { ComputeImportedDeclBodyHash(decl) }
        cache.astKind = UInt8(IncrDeclKindIndex(decl.astKind))
        cache.cgMangle = if (decl.cgMangle.isEmpty()) { decl.mangledName } else { decl.cgMangle }
        return cache
    }

    private func VisitMember(decl: IncrDecl, map: RawMangled2DeclMap): MemberDeclCache {
        map[decl.rawMangleName] = decl
        let cache = MemberDeclCache(decl.rawMangleName)
        for (member in GetMembers(decl)) {
            if (!member.rawMangleName.isEmpty()) {
                cache.members.add(VisitMember(member, map))
            }
        }
        cache.sigHash = ComputeDeclSigHash(decl)
        cache.srcUse = ComputeDeclSrcUseHash(decl)
        cache.bodyHash = if (SkipImportedBodyHash(decl)) { 0u64 } else { ComputeImportedDeclBodyHash(decl) }
        cache.astKind = UInt8(IncrDeclKindIndex(decl.astKind))
        cache.cgMangle = if (decl.cgMangle.isEmpty()) { decl.mangledName } else { decl.cgMangle }
        return cache
    }

    private func UpdateMangleName(decl: IncrDecl): Unit {
        ReplaceTypeWithTyInMangleName(decl)
        for (member in GetMembers(decl)) {
            if (member.rawMangleName.isEmpty()) {
                member.rawMangleName = MangleDecl(member)
            }
            UpdateMangleName(member)
        }
    }

    private func RegisterDeclAndMembers(decl: IncrDecl, map: RawMangled2DeclMap): Unit {
        if (!decl.rawMangleName.isEmpty()) {
            map[decl.rawMangleName] = decl
        }
        for (member in GetMembers(decl)) {
            RegisterDeclAndMembers(member, map)
        }
    }

    private func ResolveInheritedTypeDecls(decl: IncrDecl, map: RawMangled2DeclMap): Unit {
        for (rawMangle in decl.inheritedTypeMangles) {
            if (let Some(parent) <- map.get(rawMangle)) {
                if (!decl.inheritedTypes.contains(parent)) {
                    decl.inheritedTypes.add(parent)
                }
            }
        }
        for (member in GetMembers(decl)) {
            ResolveInheritedTypeDecls(member, map)
        }
    }

    private func CollectSourceImportedDependencies(decl: IncrDecl, result: ImportPackageWalkerResult): Unit {
        if (HasImportedBodyDependencySource(decl)) {
            for (target in decl.sourceImportedTargets) {
                AddSourceImportedDependency(target, decl, result.sourcePopulations)
            }
            for (rawMangle in decl.sourceImportedTargetMangles) {
                if (let Some(target) <- result.importedMangled2Decl.get(rawMangle)) {
                    AddSourceImportedDependency(target, decl, result.sourcePopulations)
                }
            }
        }
        for (member in GetMembers(decl)) {
            CollectSourceImportedDependencies(member, result)
        }
    }

    private func AddSourceImportedDependency(usedDecl: IncrDecl, importingDecl: IncrDecl,
        deps: SrcImportedDepMap): Unit {
        if (!deps.contains(usedDecl)) {
            deps[usedDecl] = HashSet<IncrDecl>()
        }
        deps[usedDecl].add(importingDecl)
    }

    private func HasImportedBodyDependencySource(decl: IncrDecl): Bool {
        if (decl.astKind == IncrDeclKind.FUNC_DECL) {
            return decl.hasBody
        }
        if (decl.astKind == IncrDeclKind.VAR_DECL) {
            return decl.hasInitializer
        }
        return false
    }

    private func ReplaceTypeWithTyInMangleName(decl: IncrDecl): Unit {
        if ((decl.astKind != IncrDeclKind.FUNC_DECL && decl.astKind != IncrDeclKind.VAR_DECL) ||
            decl.TestAttr(IncrAttribute.CONSTRUCTOR) || decl.TestAttr(IncrAttribute.MACRO_FUNC) ||
            decl.rawMangleName.isEmpty()) {
            return
        }
        if (let Some(pos) <- decl.rawMangleName.lastIndexOf("$$")) {
            let suffix = if (decl.astKind == IncrDeclKind.FUNC_DECL && !decl.returnTypeName.isEmpty()) {
                decl.returnTypeName
            } else if (!decl.resolvedTypeName.isEmpty()) {
                decl.resolvedTypeName
            } else if (decl.hasExplicitType) {
                "typed"
            } else {
                ""
            }
            if (!suffix.isEmpty()) {
                decl.rawMangleName = decl.rawMangleName[0..pos + 2] + suffix
            }
        }
    }

    private func SkipImportedBodyHash(decl: IncrDecl): Bool {
        if (decl.IsConst()) {
            return false
        }
        if (decl.astKind == IncrDeclKind.VAR_DECL) {
            return !decl.hasInitializer
        }
        if (decl.astKind == IncrDeclKind.FUNC_DECL) {
            if (decl.hasBody) {
                return false
            }
            for (desugarDecl in decl.defaultParamDesugarDecls) {
                if (desugarDecl.hasBody) {
                    return false
                }
            }
            return true
        }
        return false
    }
}

private func TerminateAnalysisAndRollback(cache: CompilationCache, args: IncrementalScopeAnalysisArgs,
    msg: String): IncreResult {
    let imported = ImportPackageWalker.Get(args.srcPackage, args.importer)
    cache.curPkgASTCache.clear()
    for ((name, cacheEntry) in args.astCacheInfo) {
        cache.curPkgASTCache[name] = cacheEntry.Clone()
    }
    cache.importedASTCache.clear()
    for ((name, cacheEntry) in imported.importedASTCache) {
        cache.importedASTCache[name] = cacheEntry.Clone()
    }
    for ((name, decl) in args.rawMangleName2DeclMap) {
        imported.importedMangled2Decl[name] = decl
    }
    IncrementalCompilationLogger.GetInstance().LogLn(msg)
    return IncreResult(IncreKind.ROLLBACK, cache, imported.importedMangled2Decl)
}

private func IsCCOutFuncNeedToRecompileOrDelete(preCache: CompilationCache, pollutionRes: PollutionResult): Bool {
    if (preCache.ccOutFuncs.isEmpty()) {
        return false
    }
    for (rawMangle in pollutionRes.deleted) {
        if (preCache.ccOutFuncs.contains(rawMangle)) {
            IncrementalCompilationLogger.GetInstance().LogLn("closure convert out func recompile: " + rawMangle)
            return true
        }
    }
    for (decl in pollutionRes.declsToRecompile) {
        if (preCache.ccOutFuncs.contains(decl.rawMangleName)) {
            IncrementalCompilationLogger.GetInstance().LogLn("closure convert out func recompile: " +
                decl.rawMangleName)
            return true
        }
    }
    return false
}

private func BuildMangleMapForCachedInfo(memCache: MemberDeclCache, mangleMap: HashMap<String, String>): Unit {
    mangleMap[memCache.rawMangle] = memCache.cgMangle
    for (member in memCache.members) {
        BuildMangleMapForCachedInfo(member, mangleMap)
    }
}

private func BuildMangleMapForCachedInfo(rawMangle: String, topCache: TopLevelDeclCache,
    mangleMap: HashMap<String, String>): Unit {
    mangleMap[rawMangle] = topCache.cgMangle
    for (member in topCache.members) {
        BuildMangleMapForCachedInfo(member, mangleMap)
    }
}

private func GetCgManglesForDelete(cachedInfo: CompilationCache, deleted: ArrayList<String>): ArrayList<String> {
    let deletedMangleNames = ArrayList<String>()
    if (deleted.isEmpty()) {
        return deletedMangleNames
    }
    let mangleMap = HashMap<String, String>()
    for ((rawMangle, cache) in cachedInfo.curPkgASTCache) {
        BuildMangleMapForCachedInfo(rawMangle, cache, mangleMap)
    }
    for ((rawMangle, cache) in cachedInfo.importedASTCache) {
        BuildMangleMapForCachedInfo(rawMangle, cache, mangleMap)
    }
    for (name in deleted) {
        deletedMangleNames.add(mangleMap.get(name) ?? name)
    }
    return deletedMangleNames
}

private func LoadCacheInfo(path: String, mangledName2DeclMap: RawMangled2DeclMap): Option<CompilationCache> {
    if (path.isEmpty() || !exists(path)) {
        return None
    }
    try {
        let data = File.readFrom(path)
        let loader = HashedASTLoader(data)
        let loaded = loader.DeserializeData(mangledName2DeclMap)
        if (loaded[0]) {
            return Some(loaded[1])
        }
    } catch (e: Exception) {
        return None
    }
    return None
}

private func PrintCHIROptEffectMap(effectMap: OptEffectStrMap, rawMangled2Decl: RawMangled2DeclMap): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    if (!logger.IsEnable()) {
        return
    }
    logger.LogLn("[CHIR Effect Map] START")
    let keys = ArrayList<String>()
    for ((key, _) in effectMap) {
        keys.add(key)
    }
    for (key in SortedStringList(keys)) {
        var msg = OutputDeclInfo(rawMangled2Decl, key) + " -> "
        for (name in SortedStringSet(effectMap[key])) {
            msg += OutputDeclInfo(rawMangled2Decl, name) + ","
        }
        logger.LogLn(msg)
    }
    logger.LogLn("[CHIR Effect Map] END")
}

private func OutputDeclInfo(rawMangled2Decl: RawMangled2DeclMap, rawMangledName: String): String {
    if (let Some(decl) <- rawMangled2Decl.get(rawMangledName)) {
        return decl.DisplayName() + "(l:" + decl.begin.line.toString() + ", c:" +
            decl.begin.column.toString() + ")"
    }
    return rawMangledName
}

private func DumpDeclsToRecompile(declsToRecompile: HashSet<IncrDecl>): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    if (!logger.IsEnable() || declsToRecompile.isEmpty()) {
        return
    }
    logger.LogLn("changed decls to recompile: " + declsToRecompile.size.toString())
    for (decl in SortedDeclsBySource(declsToRecompile)) {
        logger.LogLn("the changed decl after Spreading is:" + decl.DisplayName() + " in file " +
            GetTrimmedPath(decl) + " in line " + decl.begin.line.toString() + " in column " +
            decl.begin.column.toString())
    }
}

private func DumpDeleted(deleted: ArrayList<String>): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    if (!logger.IsEnable() || deleted.isEmpty()) {
        return
    }
    logger.LogLn("deleted decls: " + deleted.size.toString())
    for (name in deleted) {
        logger.LogLn("the deleted decl is:" + name)
    }
}

private func makeDelimiter(): String {
    let builder = StringBuilder()
    var idx: Int64 = 0
    while (idx < DELIMITER_NUM) {
        builder.append("=")
        idx++
    }
    return builder.toString()
}
