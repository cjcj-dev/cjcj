package cangjie_compiler::incremental_compilation

import std.collection.*
import std.sort.*
import cangjie_compiler::option.GlobalOptions

public let DELIMITER_NUM: Int64 = 60

public class CommonChange {
    public var decl: IncrDecl
    public var sig: Bool = false
    public var srcUse: Bool = false
    public var body: Bool = false

    public init(decl: IncrDecl) {
        this.decl = decl
    }

    public init(decl: IncrDecl, sig: Bool, srcUse: Bool, body: Bool) {
        this.decl = decl
        this.sig = sig
        this.srcUse = srcUse
        this.body = body
    }

    public func HasChange(): Bool {
        return sig || srcUse || body
    }

    public func ToString(): String {
        let builder = StringBuilder()
        builder.append(decl.rawMangleName + ": ")
        if (!HasChange()) {
            builder.append("no change\n")
            return builder.toString()
        }
        if (sig) { builder.append("sig ") }
        if (srcUse) { builder.append("srcuse ") }
        if (body) { builder.append("body ") }
        builder.append("\n")
        return builder.toString()
    }
}

public class TypeChange {
    public var instVar: Bool = false
    public var virtFun: Bool = false
    public var sig: Bool = false
    public var srcUse: Bool = false
    public var body: Bool = false
    public var order: Bool = false
    public let changed: ArrayList<CommonChange> = ArrayList<CommonChange>()
    public let added: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    public let del: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func HasChange(): Bool {
        return instVar || virtFun || sig || srcUse || body || order || !changed.isEmpty() ||
            !added.isEmpty() || !del.isEmpty()
    }

    public func ToString(): String {
        if (!HasChange()) {
            return "no change\n"
        }
        let builder = StringBuilder()
        if (instVar) { builder.append("memory ") }
        if (virtFun) { builder.append("virtual ") }
        if (sig) { builder.append("sig ") }
        if (srcUse) { builder.append("srcuse ") }
        if (body) { builder.append("body ") }
        builder.append("\n")
        if (!added.isEmpty()) {
            builder.append("    added members " + added.size.toString() + ": ")
            for (decl in added) {
                builder.append(decl.rawMangleName + " ")
            }
            builder.append("\n")
        }
        if (!del.isEmpty()) {
            builder.append("    deleted members " + del.size.toString() + ": ")
            for (name in del) {
                builder.append(name + " ")
            }
            builder.append("\n")
        }
        if (!changed.isEmpty()) {
            builder.append("    changed members " + changed.size.toString() + ":\n")
            for (change in changed) {
                builder.append("         " + change.ToString())
            }
        }
        return builder.toString()
    }
}

public class ModifiedDecls {
    public let added: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    public let deletes: ArrayList<String> = ArrayList<String>()
    public var importChanged: Bool = false
    public var args: Bool = false
    public let types: HashMap<IncrDecl, TypeChange> = HashMap<IncrDecl, TypeChange>()
    public let commons: HashMap<IncrDecl, CommonChange> = HashMap<IncrDecl, CommonChange>()
    public let aliases: ArrayList<IncrDecl> = ArrayList<IncrDecl>()
    public let deletedTypeAlias: ArrayList<String> = ArrayList<String>()
    public let orderChanges: ArrayList<IncrDecl> = ArrayList<IncrDecl>()

    public init() {}

    public func HasChange(): Bool {
        return !added.isEmpty() || !deletedTypeAlias.isEmpty() || !deletes.isEmpty() || !types.isEmpty() ||
            !commons.isEmpty() || !orderChanges.isEmpty() || !aliases.isEmpty()
    }

    public func Dump(): Unit {
        let logger = IncrementalCompilationLogger.GetInstance()
        if (!logger.IsEnable()) {
            return
        }
        if (!HasChange()) {
            logger.LogLn("no raw modified decls")
            return
        }
        let builder = StringBuilder()
        appendDelimiter(builder)
        builder.append("\nbegin dump raw modified decls:\n")
        let sortedAdded = ArrayList<IncrDecl>()
        for (decl in added) {
            sortedAdded.add(decl)
        }
        sort(sortedAdded, by: { left: IncrDecl, right: IncrDecl =>
            CompareDeclSource(left, right)
        }, stable: true)
        for (decl in sortedAdded) {
            builder.append("added ")
            if (!decl.identifier.isEmpty()) {
                builder.append(decl.identifier + " ")
            }
            builder.append(decl.rawMangleName + " at " + decl.begin.line.toString() + "," +
                decl.begin.column.toString() + "\n")
        }
        for (name in SortedStringList(deletedTypeAlias)) {
            builder.append("deleted " + name + "\n")
        }
        for (name in SortedStringList(deletes)) {
            builder.append("deleted " + name + "\n")
        }
        let typePairs = ArrayList<(IncrDecl, TypeChange)>()
        for ((decl, change) in types) {
            typePairs.add((decl, change))
        }
        sort(typePairs, by: { left: (IncrDecl, TypeChange), right: (IncrDecl, TypeChange) =>
            CompareDeclSource(left[0], right[0])
        }, stable: true)
        for (pair in typePairs) {
            if (pair[1].HasChange()) {
                builder.append(PrintDecl(pair[0]) + ": " + pair[1].ToString())
            }
        }
        let commonPairs = ArrayList<(IncrDecl, CommonChange)>()
        for ((decl, change) in commons) {
            commonPairs.add((decl, change))
        }
        sort(commonPairs, by: { left: (IncrDecl, CommonChange), right: (IncrDecl, CommonChange) =>
            CompareDeclSource(left[0], right[0])
        }, stable: true)
        for (pair in commonPairs) {
            if (pair[1].HasChange()) {
                builder.append(pair[1].ToString())
            }
        }
        if (!orderChanges.isEmpty()) {
            builder.append(orderChanges.size.toString() + " order changed decl(s).\n")
        }
        for (decl in orderChanges) {
            builder.append("order change " + decl.rawMangleName + "\n")
        }
        appendDelimiter(builder)
        logger.LogLn(builder.toString())
    }

    private func appendDelimiter(builder: StringBuilder): Unit {
        var idx: Int64 = 0
        while (idx < DELIMITER_NUM) {
            builder.append("=")
            idx++
        }
    }
}

public class ASTDiffArgs {
    public var prevCache: CompilationCache
    public var curImports: ASTCache
    public var importedMangled2Decl: RawMangled2DeclMap
    public var rawMangleName2DeclMap: RawMangled2DeclMap
    public var astCacheInfo: ASTCache
    public var curFileMap: FileMap
    public var op: GlobalOptions

    public init(prevCache: CompilationCache, curImports: ASTCache, importedMangled2Decl: RawMangled2DeclMap,
        rawMangleName2DeclMap: RawMangled2DeclMap, astCacheInfo: ASTCache, curFileMap: FileMap,
        op: GlobalOptions) {
        this.prevCache = prevCache
        this.curImports = curImports
        this.importedMangled2Decl = importedMangled2Decl
        this.rawMangleName2DeclMap = rawMangleName2DeclMap
        this.astCacheInfo = astCacheInfo
        this.curFileMap = curFileMap
        this.op = op
    }
}

public class ASTDiffResult {
    public var changedDecls: ModifiedDecls
    public var mangled2Decl: RawMangled2DeclMap

    public init(changedDecls: ModifiedDecls, mangled2Decl: RawMangled2DeclMap) {
        this.changedDecls = changedDecls
        this.mangled2Decl = mangled2Decl
    }
}

private class OrderDiffCompare {
    private let mangled2Decl: RawMangled2DeclMap
    private let exclude: HashSet<String>
    public let orderChanges: ArrayList<IncrDecl> = ArrayList<IncrDecl>()

    public init(mangled2Decl: RawMangled2DeclMap, cachedFileMap: CachedFileMap, curFileMap: FileMap,
        modified: ModifiedDecls) {
        this.mangled2Decl = mangled2Decl
        this.exclude = GetAddedDecls(modified)
        for ((file, oldOrder) in cachedFileMap) {
            if (let Some(curOrder) <- curFileMap.get(file)) {
                for (decl in CompareOrders(oldOrder, curOrder)) {
                    orderChanges.add(decl)
                }
            }
        }
        let emptyOld = ArrayList<String>()
        for ((file, curOrder) in curFileMap) {
            if (!cachedFileMap.contains(file)) {
                for (decl in CompareOrders(emptyOld, curOrder)) {
                    orderChanges.add(decl)
                }
            }
        }
    }

    private static func GetAddedDecls(modified: ModifiedDecls): HashSet<String> {
        let result = HashSet<String>()
        for (decl in modified.added) {
            if (decl.IsImported()) {
                continue
            }
            if (IsOOEAffectedDecl(decl)) {
                result.add(decl.rawMangleName)
                continue
            }
            for (member in GetMembers(decl)) {
                if (IsOOEAffectedDecl(member)) {
                    result.add(member.rawMangleName)
                    continue
                }
                for (nested in GetMembers(member)) {
                    if (IsOOEAffectedDecl(nested)) {
                        result.add(decl.rawMangleName)
                    }
                }
            }
        }
        for ((decl, _) in modified.types) {
            if (decl.IsImported()) {
                continue
            }
            for (member in GetMembers(decl)) {
                if (IsOOEAffectedDecl(member)) {
                    result.add(member.rawMangleName)
                    continue
                }
                for (nested in GetMembers(member)) {
                    if (IsOOEAffectedDecl(nested)) {
                        result.add(decl.rawMangleName)
                    }
                }
            }
        }
        return result
    }

    private func BuildGvidMap(cur: ArrayList<IncrDecl>): HashMap<String, Int64> {
        let out = HashMap<String, Int64>()
        for (decl in cur) {
            out[decl.rawMangleName] = decl.cacheHash.gvid
        }
        return out
    }

    private func BuildMaxids(oldOrder: ArrayList<String>, gvidMap: HashMap<String, Int64>): ArrayList<Int64> {
        let maxids = ArrayList<Int64>()
        maxids.add(0)
        var last: Int64 = 0
        for (mangle in oldOrder) {
            if (let Some(currentId) <- gvidMap.get(mangle)) {
                let maxid = if (currentId > last) { currentId } else { last }
                maxids.add(maxid)
                if (let Some(decl) <- mangled2Decl.get(mangle)) {
                    if (IsOrderAffectingGlobal(decl)) {
                        last = maxid
                    }
                }
            }
        }
        return maxids
    }

    private func CompareOrders(oldOrder: ArrayList<String>, curOrder: ArrayList<IncrDecl>): ArrayList<IncrDecl> {
        let result = HashSet<IncrDecl>()
        let gvidMap = BuildGvidMap(curOrder)
        let maxids = BuildMaxids(oldOrder, gvidMap)
        var rid: Int64 = 0
        var idx: Int64 = 0
        while (idx < oldOrder.size) {
            let name = oldOrder[idx]
            if (let Some(currentId) <- gvidMap.get(name)) {
                rid++
                if (rid < maxids.size && currentId < maxids[rid]) {
                    if (let Some(decl) <- mangled2Decl.get(name)) {
                        result.add(decl)
                    }
                }
            }
            idx++
        }

        let oldNames = HashSet<String>()
        for (name in oldOrder) {
            oldNames.add(name)
        }
        var curIdx = curOrder.size
        while (curIdx > 0) {
            curIdx--
            let decl = curOrder[curIdx]
            if (exclude.contains(decl.rawMangleName) || oldNames.contains(decl.rawMangleName)) {
                continue
            }
            result.add(decl)
            if (IsOrderAffectingGlobal(decl)) {
                var prefix: Int64 = 0
                while (prefix < curIdx) {
                    result.add(curOrder[prefix])
                    prefix++
                }
                break
            }
        }
        return SortedDeclsBySource(result)
    }
}

private class ASTDiffImpl {
    private let srcInfo: (Bool, Bool)
    public let ret: ModifiedDecls = ModifiedDecls()
    public var mangled2Decl: RawMangled2DeclMap = RawMangled2DeclMap()

    public init(srcInfo: (Bool, Bool)) {
        this.srcInfo = srcInfo
    }

    public func CompareCurPkgASTCache(cached: ASTCache, cur: ASTCache, cachedFileMap: CachedFileMap,
        curFileMap: FileMap): Unit {
        CompareCommonDecls(cached, cur)
        let orderDiff = OrderDiffCompare(mangled2Decl, cachedFileMap, curFileMap, ret)
        for (decl in orderDiff.orderChanges) {
            ret.orderChanges.add(decl)
        }
    }

    public func CompareImportedASTCache(cached: ASTCache, cur: ASTCache): Unit {
        CompareCommonDecls(cached, cur)
    }

    private func CompareCommonDecls(cached: ASTCache, cur: ASTCache): Unit {
        for ((mangled, topDecl) in cached) {
            if (let Some(curDecl) <- cur.get(mangled)) {
                CompareTopLevelDecl(topDecl, curDecl, mangled)
            } else {
                CollectDeletedTopLevelDecl(mangled, topDecl)
            }
        }
        for ((mangled, _) in cur) {
            if (!cached.contains(mangled)) {
                if (let Some(decl) <- mangled2Decl.get(mangled)) {
                    ret.added.add(decl)
                }
            }
        }
    }

    private func CollectDeletedTopLevelDecl(mangled: String, topDecl: TopLevelDeclCache): Unit {
        if (topDecl.astKind == UInt8(IncrDeclKindIndex(IncrDeclKind.TYPE_ALIAS_DECL))) {
            ret.deletedTypeAlias.add(mangled)
        } else {
            ret.deletes.add(mangled)
        }
        for (member in topDecl.members) {
            ret.deletes.add(member.rawMangle)
        }
    }

    private func CompareMemberDecl(typeChange: TypeChange, cached: MemberDeclCache, cur: MemberDeclCache): Unit {
        if (let Some(decl) <- mangled2Decl.get(cur.rawMangle)) {
            let change = CommonChange(decl, cached.sigHash != cur.sigHash, cached.srcUse != cur.srcUse,
                cached.bodyHash != cur.bodyHash)
            if (change.HasChange()) {
                typeChange.changed.add(change)
            }
        }
        CompareMembers(typeChange, cached.members, cur.members)
    }

    private func CompareMembers(typeChange: TypeChange, cached: ArrayList<MemberDeclCache>,
        cur: ArrayList<MemberDeclCache>): Unit {
        let sortedCached = ArrayList<MemberDeclCache>()
        let sortedCur = ArrayList<MemberDeclCache>()
        for (member in cached) { sortedCached.add(member) }
        for (member in cur) { sortedCur.add(member) }
        sort(sortedCached, by: { left: MemberDeclCache, right: MemberDeclCache =>
            CompareStrings(left.rawMangle, right.rawMangle)
        }, stable: true)
        sort(sortedCur, by: { left: MemberDeclCache, right: MemberDeclCache =>
            CompareStrings(left.rawMangle, right.rawMangle)
        }, stable: true)
        var cachedIdx: Int64 = 0
        var curIdx: Int64 = 0
        while (cachedIdx < sortedCached.size && curIdx < sortedCur.size) {
            let cachedMember = sortedCached[cachedIdx]
            let curMember = sortedCur[curIdx]
            if (cachedMember.rawMangle < curMember.rawMangle) {
                typeChange.del.add(cachedMember.rawMangle)
                for (child in cachedMember.members) {
                    typeChange.del.add(child.rawMangle)
                }
                cachedIdx++
            } else if (cachedMember.rawMangle > curMember.rawMangle) {
                if (let Some(decl) <- mangled2Decl.get(curMember.rawMangle)) {
                    typeChange.added.add(decl)
                }
                curIdx++
            } else {
                CompareMemberDecl(typeChange, cachedMember, curMember)
                cachedIdx++
                curIdx++
            }
        }
        while (cachedIdx < sortedCached.size) {
            let cachedMember = sortedCached[cachedIdx]
            typeChange.del.add(cachedMember.rawMangle)
            for (child in cachedMember.members) {
                typeChange.del.add(child.rawMangle)
            }
            cachedIdx++
        }
        while (curIdx < sortedCur.size) {
            let curMember = sortedCur[curIdx]
            if (let Some(decl) <- mangled2Decl.get(curMember.rawMangle)) {
                typeChange.added.add(decl)
            }
            curIdx++
        }
    }

    private func CompareTypeDecl(cached: TopLevelDeclCache, cur: TopLevelDeclCache): TypeChange {
        let change = TypeChange()
        change.instVar = cached.instVarHash != cur.instVarHash
        change.virtFun = cached.virtHash != cur.virtHash
        change.sig = cached.sigHash != cur.sigHash
        change.srcUse = cached.srcUse != cur.srcUse
        change.body = cached.bodyHash != cur.bodyHash
        CompareMembers(change, cached.members, cur.members)
        return change
    }

    private func CommonCompare(cached: TopLevelDeclCache, cur: TopLevelDeclCache, decl: IncrDecl): CommonChange {
        return CommonChange(decl, cached.sigHash != cur.sigHash, cached.srcUse != cur.srcUse,
            cached.bodyHash != cur.bodyHash)
    }

    private func CompareTopLevelDecl(cachedDecl: TopLevelDeclCache, curDecl: TopLevelDeclCache,
        mangled: String): Unit {
        if (let Some(decl) <- mangled2Decl.get(mangled)) {
            match (decl.astKind) {
                case IncrDeclKind.TYPE_ALIAS_DECL =>
                    if (cachedDecl.sigHash != curDecl.sigHash) {
                        ret.aliases.add(decl)
                    }
                case IncrDeclKind.FUNC_DECL | IncrDeclKind.MACRO_DECL | IncrDeclKind.MAIN_DECL |
                    IncrDeclKind.VAR_DECL | IncrDeclKind.VAR_WITH_PATTERN_DECL =>
                    let change = CommonCompare(cachedDecl, curDecl, decl)
                    if (change.HasChange()) {
                        ret.commons[decl] = change
                    }
                case _ =>
                    let typeChange = CompareTypeDecl(cachedDecl, curDecl)
                    if (typeChange.HasChange()) {
                        ret.types[decl] = typeChange
                    }
            }
        }
    }
}

public func ASTDiff(args: ASTDiffArgs): ASTDiffResult {
    let impl = ASTDiffImpl((args.op.enableCompileDebug, args.op.displayLineInfo))
    for ((name, decl) in args.rawMangleName2DeclMap) {
        args.importedMangled2Decl[name] = decl
    }
    impl.mangled2Decl = args.importedMangled2Decl
    impl.CompareCurPkgASTCache(args.prevCache.curPkgASTCache, args.astCacheInfo, args.prevCache.fileMap,
        args.curFileMap)
    impl.CompareImportedASTCache(args.prevCache.importedASTCache, args.curImports)
    return ASTDiffResult(impl.ret, impl.mangled2Decl)
}
