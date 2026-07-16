package cjcj::incremental_compilation

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::modules.SemaImportManager
import cjcj::option.GlobalOptions
import cjcj::parse.{ASTHasher, GetTrimmedPath}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, CJC_NULLPTR_CHECK, FileUtil, IncrementalCompilationLogger, NotIn, TO_ANY}

private class DumpInfo {
    public let identifier: String
    public let fileName: String
    public let lineNum: Int64
    public let columnNum: Int64

    public init(identifier: String, fileName: String, lineNum: Int64, columnNum: Int64) {
        this.identifier = identifier
        this.fileName = fileName
        this.lineNum = lineNum
        this.columnNum = columnNum
    }
}

public func DumpDeclsToRecompile(declsToRecompile: HashSet<Decl>): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    if (!logger.IsEnable()) { return }
    if (!declsToRecompile.isEmpty()) {
        logger.LogLn("changed decls to recompile: " + declsToRecompile.size.toString())
        let infos = ArrayList<DumpInfo>()
        for (decl in declsToRecompile) {
            if (decl.identifier.Empty()) {
                if (decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
                    infos.add(DumpInfo("VarWithPatternDecl", GetTrimmedPath(decl.curFile), decl.begin.line,
                        decl.begin.column))
                } else if (decl.astKind == ASTKind.EXTEND_DECL) {
                    infos.add(DumpInfo("ExtendDecl", GetTrimmedPath(decl.curFile), decl.begin.line,
                        decl.begin.column))
                } else {
                    CJC_ABORT()
                }
            } else {
                infos.add(DumpInfo(decl.identifier.Val(), GetTrimmedPath(decl.curFile),
                    decl.identifier.Begin().line, decl.identifier.Begin().column))
            }
        }
        sort(infos, by: { left: DumpInfo, right: DumpInfo =>
            if (left.fileName != right.fileName) {
                if (left.fileName < right.fileName) { Ordering.LT } else { Ordering.GT }
            } else if (left.lineNum != right.lineNum) {
                if (left.lineNum < right.lineNum) { Ordering.LT } else { Ordering.GT }
            } else if (left.columnNum != right.columnNum) {
                if (left.columnNum < right.columnNum) { Ordering.LT } else { Ordering.GT }
            } else if (left.identifier < right.identifier) {
                Ordering.LT
            } else if (left.identifier > right.identifier) {
                Ordering.GT
            } else {
                Ordering.EQ
            }
        }, stable: true)
        for (info in infos) {
            logger.LogLn("the changed decl after Spreading is:" + info.identifier + " in file " + info.fileName +
                " in line " + info.lineNum.toString() + " in column " + info.columnNum.toString())
        }
    }
}

public func DumpDeleted(deleted: ArrayList<RawMangledName>): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    if (!logger.IsEnable()) { return }
    if (!deleted.isEmpty()) {
        logger.LogLn("deleted decls: " + deleted.size.toString())
        for (mangle in deleted) { logger.LogLn("the deleted decl is:" + mangle) }
    }
}

public class IncreResult {
    public var kind: IncreKind = IncreKind.INVALID
    public let declsToRecompile: HashSet<Decl> = HashSet<Decl>()
    public let deleted: ArrayList<RawMangledName> = ArrayList<RawMangledName>()
    public let deletedMangleNames: ArrayList<String> = ArrayList<String>()
    public var cacheInfo: CompilationCache = CompilationCache()
    public var mangle2decl: RawMangled2DeclMap = RawMangled2DeclMap()
    public let reBoxedTypes: ArrayList<RawMangledName> = ArrayList<RawMangledName>()

    public init() {}

    public func Dump(): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) { return }
        if (kind != IncreKind.INCR) {
            if (kind == IncreKind.ROLLBACK) {
                logger.LogLn("incremental compile result kind: rollback")
                return
            }
            if (kind == IncreKind.EMPTY_PKG) {
                logger.LogLn("incremental compile result kind: empty package")
                return
            }
            if (kind == IncreKind.NO_CHANGE) {
                logger.LogLn("incremental compile result kind: no change")
                return
            }
            CJC_ABORT()
            return
        }
        let delimiterBuilder = StringBuilder()
        for (_ in 0..DELIMITER_NUM) { delimiterBuilder.append("=") }
        let delimiter = delimiterBuilder.toString()
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
    public var rawMangleName2DeclMap: RawMangled2DeclMap
    public var astCacheInfo: ASTCache
    public var srcPackage: Package
    public var op: GlobalOptions
    public var importer: SemaImportManager
    public var cachedInfo: CompilationCache
    public var fileMap: FileMap
    public var directExtends: HashMap<RawMangledName, ArrayList<(ExtendDecl, Int64)>>

    public init(rawMangleName2DeclMap: RawMangled2DeclMap, astCacheInfo: ASTCache, srcPackage: Package,
        op: GlobalOptions, importer: SemaImportManager, cachedInfo: CompilationCache, fileMap: FileMap,
        directExtends: HashMap<RawMangledName, ArrayList<(ExtendDecl, Int64)>>) {
        this.rawMangleName2DeclMap = rawMangleName2DeclMap
        this.astCacheInfo = astCacheInfo
        this.srcPackage = srcPackage
        this.op = op
        this.importer = importer
        this.cachedInfo = cachedInfo
        this.fileMap = fileMap
        this.directExtends = directExtends
    }
}

private func GetName(decl: Decl): String {
    return if (decl.astKind == ASTKind.EXTEND_DECL) { "extend" } else { decl.identifier.Val() }
}

private func OutputDeclInfo(rawMangled2Decl: RawMangled2DeclMap, rawMangledName: String): String {
    if (let None <- rawMangled2Decl.get(rawMangledName)) { return rawMangledName }
    let decl = rawMangled2Decl[rawMangledName]
    return GetName(decl) + "(l:" + decl.begin.line.toString() + ", c:" + decl.begin.column.toString() + ")"
}

private func PrintCHIROptEffectMap(effectMap: OptEffectStrMap, rawMangled2Decl: RawMangled2DeclMap): Unit {
    let logger = IncrementalCompilationLogger.GetInstance()
    if (!logger.IsEnable()) { return }
    logger.LogLn("[CHIR Effect Map] START")
    let keys = ArrayList<String>()
    for ((key, _) in effectMap) { keys.add(key) }
    sort(keys)
    for (key in keys) {
        let values = ArrayList<String>()
        for (value in effectMap[key]) { values.add(value) }
        sort(values)
        var msg = OutputDeclInfo(rawMangled2Decl, key) + " -> "
        for (value in values) { msg += OutputDeclInfo(rawMangled2Decl, value) + "," }
        logger.LogLn(msg)
    }
    logger.LogLn("[CHIR Effect Map] END")
}

public func MergeCHIROptEffectMap(newMap: OptEffectStrMap, lastCachedMap: OptEffectStrMap,
    rawMangled2Decl: RawMangled2DeclMap): Unit {
    for ((src, affected) in newMap) {
        CJC_ASSERT(!src.isEmpty())
        CJC_ASSERT(!affected.contains(src))
        if (affected.isEmpty()) { continue }
        if (!lastCachedMap.contains(src)) { lastCachedMap[src] = HashSet<RawMangledName>() }
        for (mangle in affected) {
            CJC_ASSERT(!mangle.isEmpty())
            lastCachedMap[src].add(mangle)
        }
    }
    PrintCHIROptEffectMap(lastCachedMap, rawMangled2Decl)
}

public func DeleteRemovedNodesInCHIROptEffectMap(removedDecls: ArrayList<String>, effectMap: OptEffectStrMap): Unit {
    let keysToRemove = ArrayList<String>()
    for ((src, affected) in effectMap) {
        if (removedDecls.contains(src)) {
            keysToRemove.add(src)
            continue
        }
        let valuesToRemove = ArrayList<String>()
        for (mangle in affected) {
            if (removedDecls.contains(mangle)) { valuesToRemove.add(mangle) }
        }
        for (mangle in valuesToRemove) { affected.remove(mangle) }
    }
    for (src in keysToRemove) { effectMap.remove(src) }
}

public func DeleteRecompiledNodesInCHIROptEffectMap(recompiledNodes: HashSet<Decl>,
    effectMap: OptEffectStrMap): Unit {
    let recompiledMangledName = HashSet<String>()
    for (decl in recompiledNodes) {
        if (let Some(mainDecl) <- (decl as MainDecl)) {
            recompiledMangledName.add(mainDecl.desugarDecl.getOrThrow().rawMangleName)
        } else {
            recompiledMangledName.add(decl.rawMangleName)
        }
    }
    let keysToRemove = ArrayList<String>()
    for ((src, affected) in effectMap) {
        let valuesToRemove = ArrayList<String>()
        for (mangle in affected) {
            if (recompiledMangledName.contains(mangle)) { valuesToRemove.add(mangle) }
        }
        for (mangle in valuesToRemove) { affected.remove(mangle) }
        if (affected.isEmpty()) { keysToRemove.add(src) }
    }
    for (src in keysToRemove) { effectMap.remove(src) }
}

private func LoadCacheInfo(path: String, mangledName2DeclMap: RawMangled2DeclMap): Option<CompilationCache> {
    let (success, data, _) = FileUtil.ReadBinaryFileToBuffer(path)
    if (!success) { return None }
    let loader = HashedASTLoader(data)
    let result = loader.DeserializeData(mangledName2DeclMap)
    if (!result[0]) { return None }
    return Some(result[1])
}

private class ImportPackageWalker {
    private let map: RawMangled2DeclMap
    private let srcImportedDeps: SrcImportedDepMap

    private init(map: RawMangled2DeclMap, srcImportedDeps: SrcImportedDepMap) {
        this.map = map
        this.srcImportedDeps = srcImportedDeps
    }

    public static func Get(sourcePackage: Package, importManager: SemaImportManager):
        (ASTCache, RawMangled2DeclMap, SrcImportedDepMap, TypeMap) {
        let ret = ASTCache()
        let retMap = RawMangled2DeclMap()
        let srcImportedDeclDeps = SrcImportedDepMap()
        let relations = TypeMap()
        let collectedDecls = ArrayList<Decl>()
        let walker = ImportPackageWalker(retMap, srcImportedDeclDeps)
        for (packageDecl in importManager.GetAllImportedPackages(false)) {
            if (refEq(packageDecl.srcPackage, sourcePackage)) { continue }
            for (decl in GetAllDecls(packageDecl)) {
                if (decl.rawMangleName.isEmpty()) { continue }
                walker.UpdateMangleNameAndCollectDep(decl)
                retMap[decl.rawMangleName] = decl
                collectedDecls.add(decl)
            }
        }
        for (decl in collectedDecls) {
            let declCache = walker.VisitTopLevel(decl)
            ret[decl.rawMangleName] = declCache
            relations.CollectImportedDeclExtraRelation(decl)
        }
        return (ret, retMap, srcImportedDeclDeps, relations)
    }

    private static func GetAllDecls(packageDecl: PackageDecl): ArrayList<Decl> {
        let result = ArrayList<Decl>()
        for (file in packageDecl.srcPackage.files) {
            for (decl in file.decls) { result.add(decl) }
            for (decl in file.exportedInternalDecls) { result.add(decl) }
        }
        return result
    }

    private static func ReplaceTypeWithTyInMangleName(decl: Decl): Unit {
        if (NotIn(decl.astKind, [ASTKind.FUNC_DECL, ASTKind.VAR_DECL]) ||
            decl.TestAnyAttr(Attribute.CONSTRUCTOR, Attribute.MACRO_FUNC) || !Ty.IsTyCorrect(decl.GetTy()) ||
            decl.rawMangleName == TO_ANY) {
            return
        }
        let pos = decl.rawMangleName.lastIndexOf("$$")
        CJC_ASSERT(pos.isSome())
        decl.rawMangleName = decl.rawMangleName[0..pos.getOrThrow() + 2]
        if (decl.astKind == ASTKind.FUNC_DECL) {
            let funcTy = (decl.GetTy().getOrThrow() as FuncTy).getOrThrow()
            decl.rawMangleName += funcTy.retTy.String()
        } else {
            decl.rawMangleName += decl.GetTy().getOrThrow().String()
        }
    }

    private func SkipImportedBodyHash(decl: Decl): Bool {
        if (decl.IsConst()) { return false }
        if (let Some(varDecl) <- (decl as VarDecl)) {
            if (let None <- varDecl.initializer) { return true }
        }
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            CJC_ASSERT(funcDecl.funcBody.isSome())
            if (funcDecl.funcBody.getOrThrow().body.isSome()) { return false }
            for (param in funcDecl.funcBody.getOrThrow().paramLists[0].params) {
                if (let Some(desugarDecl) <- param.desugarDecl) {
                    if (desugarDecl.funcBody.isSome() && desugarDecl.funcBody.getOrThrow().body.isSome()) {
                        return false
                    }
                }
            }
            return true
        }
        return false
    }

    private func VisitTopLevel(decl: Decl): TopLevelDeclCache {
        map[decl.rawMangleName] = decl
        let result = TopLevelDeclCache()
        for (member in GetMembers(decl)) {
            if (member.rawMangleName.isEmpty()) { continue }
            result.members.add(VisitMember(member))
        }
        result.instVarHash = decl.hash.instVar
        result.virtHash = decl.hash.virt
        result.sigHash = decl.hash.sig
        result.srcUse = decl.hash.srcUse
        result.bodyHash = if (SkipImportedBodyHash(decl)) { 0u64 } else { ASTHasher.ImportedDeclBodyHash(decl) }
        return result
    }

    private func VisitMember(decl: Decl): MemberDeclCache {
        map[decl.rawMangleName] = decl
        let result = MemberDeclCache()
        for (member in GetMembers(decl)) {
            if (member.rawMangleName.isEmpty()) { continue }
            result.members.add(VisitMember(member))
        }
        result.rawMangle = decl.rawMangleName
        result.sigHash = decl.hash.sig
        result.srcUse = decl.hash.srcUse
        result.bodyHash = if (SkipImportedBodyHash(decl)) { 0u64 } else { ASTHasher.ImportedDeclBodyHash(decl) }
        return result
    }

    private func UpdateMangleNameAndCollectDep(decl: Decl): Unit {
        ReplaceTypeWithTyInMangleName(decl)
        if (let Some(funcDecl) <- (decl as FuncDecl)) {
            if (funcDecl.funcBody.isSome() && funcDecl.funcBody.getOrThrow().body.isSome()) {
                CollectSrcImportedDep(decl, funcDecl.funcBody.getOrThrow().body.getOrThrow())
            }
        } else if (let Some(varDecl) <- (decl as VarDecl)) {
            if (let Some(initializer) <- varDecl.initializer) { CollectSrcImportedDep(decl, initializer) }
        }
        for (member in GetMembers(decl)) {
            if (member.rawMangleName.isEmpty()) { continue }
            UpdateMangleNameAndCollectDep(member)
        }
    }

    private func CollectSrcImportedDep(decl: Decl, bodyExpr: Expr): Unit {
        Walker(bodyExpr, visitPre: { node: Node =>
            if (let Some(usedDecl) <- node.GetTarget()) {
                if (!srcImportedDeps.contains(usedDecl)) { srcImportedDeps[usedDecl] = HashSet<Decl>() }
                srcImportedDeps[usedDecl].add(decl)
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()
    }
}

private func TerminateAnalysisAndRollback(cache: CompilationCache, args: IncrementalScopeAnalysisArgs,
    msg: String): IncreResult {
    let imported = ImportPackageWalker.Get(args.srcPackage, args.importer)
    cache.curPkgASTCache.clear()
    for ((mangle, declCache) in args.astCacheInfo) { cache.curPkgASTCache[mangle] = declCache }
    cache.importedASTCache.clear()
    for ((mangle, declCache) in imported[0]) { cache.importedASTCache[mangle] = declCache }
    for ((mangle, decl) in args.rawMangleName2DeclMap) { imported[1][mangle] = decl }
    IncrementalCompilationLogger.GetInstance().LogLn(msg)
    let result = IncreResult()
    result.kind = IncreKind.ROLLBACK
    result.cacheInfo = cache
    result.mangle2decl = imported[1]
    return result
}

private func IsCCOutFuncNeedToRecompileOrDelete(preCache: CompilationCache,
    pollutionRes: PollutionResult): Bool {
    if (preCache.ccOutFuncs.isEmpty()) { return false }
    for (rawMangle in pollutionRes.deleted) {
        if (preCache.ccOutFuncs.contains(rawMangle)) {
            IncrementalCompilationLogger.GetInstance().LogLn("closure convert out func recompile: " + rawMangle)
            return true
        }
    }
    for (decl in pollutionRes.declsToRecompile) {
        if (preCache.ccOutFuncs.contains(decl.rawMangleName)) {
            IncrementalCompilationLogger.GetInstance().LogLn(
                "closure convert out func recompile: " + decl.rawMangleName)
            return true
        }
    }
    return false
}

private func BuildMangleMapForCachedInfo(memCache: MemberDeclCache,
    mangleMap: HashMap<RawMangledName, String>): Unit {
    mangleMap[memCache.rawMangle] = memCache.cgMangle
    for (member in memCache.members) { BuildMangleMapForCachedInfo(member, mangleMap) }
}

private func BuildMangleMapForCachedInfo(rawMangle: String, topCache: TopLevelDeclCache,
    mangleMap: HashMap<RawMangledName, String>): Unit {
    mangleMap[rawMangle] = topCache.cgMangle
    for (member in topCache.members) { BuildMangleMapForCachedInfo(member, mangleMap) }
}

private func GetCgManglesForDelete(cachedInfo: CompilationCache,
    deleted: ArrayList<RawMangledName>): ArrayList<String> {
    if (deleted.isEmpty()) { return ArrayList<String>() }
    let mangleMap = HashMap<RawMangledName, String>()
    for ((rawMangle, cache) in cachedInfo.curPkgASTCache) {
        BuildMangleMapForCachedInfo(rawMangle, cache, mangleMap)
    }
    for ((rawMangle, cache) in cachedInfo.importedASTCache) {
        BuildMangleMapForCachedInfo(rawMangle, cache, mangleMap)
    }
    let deletedMangleNames = ArrayList<String>()
    for (mangle in deleted) {
        if (let Some(cgMangle) <- mangleMap.get(mangle)) {
            deletedMangleNames.add(cgMangle)
        } else {
            CJC_ABORT()
        }
    }
    return deletedMangleNames
}

public func IncrementalScopeAnalysis(args: IncrementalScopeAnalysisArgs): IncreResult {
    let cachePath = args.op.GenerateCachedPathName(args.srcPackage.fullPackageName, CACHED_AST_EXTENSION)
    let loadingResult = LoadCacheInfo(cachePath, args.rawMangleName2DeclMap)
    let cjoPath = args.op.GenerateCachedPathName(args.srcPackage.fullPackageName, SERIALIZED_FILE_EXTENSION)
    if (loadingResult.isNone() || !FileUtil.FileExist(cjoPath)) {
        return TerminateAnalysisAndRollback(CompilationCache(), args,
            "load cached info failed, roll back to full compilation")
    }
    let previousCache = loadingResult.getOrThrow()
    let serializedArgs = args.op.ToSerialized()
    var compilationArgsChange = serializedArgs.size != previousCache.compileArgs.size
    if (!compilationArgsChange) {
        var idx: Int64 = 0
        while (idx < serializedArgs.size) {
            if (serializedArgs[idx] != previousCache.compileArgs[idx]) {
                compilationArgsChange = true
                break
            }
            idx++
        }
    }
    if (compilationArgsChange) {
        return TerminateAnalysisAndRollback(previousCache, args,
            "compile args changed, roll back to full compilation")
    }
    if (ASTHasher.HashSpecs(args.srcPackage) != previousCache.specs) {
        return TerminateAnalysisAndRollback(previousCache, args,
            "package or import specs changed, roll back to full compilation")
    }
    let imported = ImportPackageWalker.Get(args.srcPackage, args.importer)
    let diffResult = ASTDiff(ASTDiffArgs(previousCache, imported[0], imported[1], args.rawMangleName2DeclMap,
        args.astCacheInfo, args.fileMap, args.op))
    diffResult.changedDecls.Dump()
    if (!diffResult.changedDecls.aliases.isEmpty()) {
        return TerminateAnalysisAndRollback(previousCache, args,
            "type alias changed, roll back to full compilation")
    }
    let srcPkgDecl = args.importer.GetPackageDecl(args.srcPackage.fullPackageName)
    CJC_NULLPTR_CHECK(srcPkgDecl)
    let pollutionRes = PollutionAnalyzer.Get(PollutionAnalyseArgs(diffResult.changedDecls,
        srcPkgDecl.getOrThrow(), imported[2], previousCache.semaInfo, previousCache.chirOptInfo,
        previousCache.fileMap, args.importer, diffResult.mangled2Decl, args.directExtends, imported[3]))
    if (IsCCOutFuncNeedToRecompileOrDelete(previousCache, pollutionRes)) {
        DumpDeclsToRecompile(pollutionRes.declsToRecompile)
        DumpDeleted(pollutionRes.deleted)
        return TerminateAnalysisAndRollback(previousCache, args,
            "closure convert out func recompile, roll back to full compilation")
    }
    if (pollutionRes.kind == IncreKind.INCR) {
        for (decl in pollutionRes.declsToRecompile) { decl.toBeCompiled = true }
    }
    let deletedMangleNames = GetCgManglesForDelete(previousCache, pollutionRes.deleted)
    previousCache.curPkgASTCache.clear()
    for ((mangle, declCache) in args.astCacheInfo) { previousCache.curPkgASTCache[mangle] = declCache }
    previousCache.importedASTCache.clear()
    for ((mangle, declCache) in imported[0]) { previousCache.importedASTCache[mangle] = declCache }
    let result = IncreResult()
    result.kind = pollutionRes.kind
    for (decl in pollutionRes.declsToRecompile) { result.declsToRecompile.add(decl) }
    for (mangle in pollutionRes.deleted) { result.deleted.add(mangle) }
    for (mangle in deletedMangleNames) { result.deletedMangleNames.add(mangle) }
    result.cacheInfo = previousCache
    result.mangle2decl = diffResult.mangled2Decl
    for (mangle in pollutionRes.reBoxedTypes) { result.reBoxedTypes.add(mangle) }
    return result
}
