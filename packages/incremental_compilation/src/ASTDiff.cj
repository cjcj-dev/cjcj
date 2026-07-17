package cjcj::incremental_compilation

import std.collection.*
import std.sort.*
import cjcj::ast.*
import cjcj::option.GlobalOptions
import cjcj::utils.{CJC_ASSERT, CJC_NULLPTR_CHECK, IncrementalCompilationLogger}

public let DELIMITER_NUM: Int64 = 60

public class CommonChange {
    public var decl: Decl
    public var sig: Bool = false
    public var srcUse: Bool = false
    public var body: Bool = false

    public init(decl: Decl) {
        this.decl = decl
    }

    public init(decl: Decl, sig: Bool, srcUse: Bool, body: Bool) {
        this.decl = decl
        this.sig = sig
        this.srcUse = srcUse
        this.body = body
    }

    public func HasChange(): Bool {
        return sig || srcUse || body
    }

    public func ToString(): String {
        let out = StringBuilder()
        out.append(decl.rawMangleName + ": ")
        if (!HasChange()) {
            out.append("no change\n")
            return out.toString()
        }
        if (sig) { out.append("sig ") }
        if (srcUse) { out.append("srcuse ") }
        if (body) { out.append("body ") }
        out.append("\n")
        return out.toString()
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
    public let added: ArrayList<Decl> = ArrayList<Decl>()
    public let del: ArrayList<RawMangledName> = ArrayList<RawMangledName>()

    public init() {}

    public func HasChange(): Bool {
        return instVar || virtFun || sig || srcUse || body || order || !changed.isEmpty() || !added.isEmpty() ||
            !del.isEmpty()
    }

    public func ToString(): String {
        if (!HasChange()) {
            return "no change\n"
        }
        let out = StringBuilder()
        if (instVar) { out.append("memory ") }
        if (virtFun) { out.append("virtual ") }
        if (sig) { out.append("sig ") }
        if (srcUse) { out.append("srcuse ") }
        if (body) { out.append("body ") }
        out.append("\n")
        if (!added.isEmpty()) {
            out.append("    added members " + added.size.toString() + ": ")
            for (decl in added) { out.append(decl.rawMangleName + " ") }
            out.append("\n")
        }
        if (!del.isEmpty()) {
            out.append("    deleted members " + del.size.toString() + ": ")
            for (mangle in del) { out.append(mangle + " ") }
            out.append("\n")
        }
        if (!changed.isEmpty()) {
            out.append("    changed members " + changed.size.toString() + ":\n")
            for (change in changed) { out.append("         " + change.ToString()) }
        }
        return out.toString()
    }
}

public class ModifiedDecls {
    public let added: ArrayList<Decl> = ArrayList<Decl>()
    public let deletes: ArrayList<RawMangledName> = ArrayList<RawMangledName>()
    public var importChanged: Bool = false
    public var args: Bool = false
    public let types: HashMap<Decl, TypeChange> = HashMap<Decl, TypeChange>()
    public let commons: HashMap<Decl, CommonChange> = HashMap<Decl, CommonChange>()
    public let aliases: ArrayList<TypeAliasDecl> = ArrayList<TypeAliasDecl>()
    public let deletedTypeAlias: ArrayList<RawMangledName> = ArrayList<RawMangledName>()
    public let orderChanges: ArrayList<Decl> = ArrayList<Decl>()

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
        let out = StringBuilder()
        var delimiter: Int64 = 0
        while (delimiter < DELIMITER_NUM) {
            out.append("=")
            delimiter++
        }
        out.append("\nbegin dump raw modified decls:\n")
        let sortedAdded = ArrayList<Decl>()
        for (decl in added) { sortedAdded.add(decl) }
        sort(sortedAdded, by: { left: Decl, right: Decl =>
            if (left.begin < right.begin) { Ordering.LT } else if (right.begin < left.begin) { Ordering.GT } else {
                Ordering.EQ
            }
        }, stable: true)
        for (decl in sortedAdded) {
            CJC_NULLPTR_CHECK(Some(decl))
            out.append("added ")
            if (!decl.identifier.Empty()) {
                out.append(decl.identifier.Val() + " ")
            }
            out.append(decl.rawMangleName + " at " + decl.identifier.Begin().line.toString() + "," +
                decl.identifier.Begin().column.toString() + "\n")
        }
        let sortedDeletedTypeAlias = ArrayList<RawMangledName>()
        for (mangle in deletedTypeAlias) { sortedDeletedTypeAlias.add(mangle) }
        sort(sortedDeletedTypeAlias)
        for (mangle in sortedDeletedTypeAlias) { out.append("deleted " + mangle + "\n") }
        let sortedDeletes = ArrayList<RawMangledName>()
        for (mangle in deletes) { sortedDeletes.add(mangle) }
        sort(sortedDeletes)
        for (mangle in sortedDeletes) { out.append("deleted " + mangle + "\n") }
        let sortedTypes = ArrayList<(Decl, TypeChange)>()
        for ((decl, change) in types) { sortedTypes.add((decl, change)) }
        sort(sortedTypes, by: { left: (Decl, TypeChange), right: (Decl, TypeChange) =>
            if (left[0].begin < right[0].begin) { Ordering.LT } else if (right[0].begin < left[0].begin) {
                Ordering.GT
            } else { Ordering.EQ }
        }, stable: true)
        for (entry in sortedTypes) {
            if (entry[1].HasChange()) {
                out.append(PrintDecl(entry[0]) + ": " + entry[1].ToString())
            }
        }
        let sortedCommons = ArrayList<(Decl, CommonChange)>()
        for ((decl, change) in commons) { sortedCommons.add((decl, change)) }
        sort(sortedCommons, by: { left: (Decl, CommonChange), right: (Decl, CommonChange) =>
            if (left[0].begin < right[0].begin) { Ordering.LT } else if (right[0].begin < left[0].begin) {
                Ordering.GT
            } else { Ordering.EQ }
        }, stable: true)
        for (entry in sortedCommons) {
            if (entry[1].HasChange()) { out.append(entry[1].ToString()) }
        }
        if (!orderChanges.isEmpty()) {
            out.append(orderChanges.size.toString() + " order changed decl(s).\n")
        }
        let sortedOrderChanges = ArrayList<Decl>()
        for (decl in orderChanges) { sortedOrderChanges.add(decl) }
        sort(sortedOrderChanges, by: { left: Decl, right: Decl =>
            if (left.begin < right.begin) { Ordering.LT } else if (right.begin < left.begin) { Ordering.GT } else {
                Ordering.EQ
            }
        }, stable: true)
        for (decl in sortedOrderChanges) { out.append("order change " + decl.rawMangleName + "\n") }
        delimiter = 0
        while (delimiter < DELIMITER_NUM) {
            out.append("=")
            delimiter++
        }
        logger.LogLn(out.toString())
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
    private let md: RawMangled2DeclMap
    private let exc: HashSet<RawMangledName>
    public let orderChanges: ArrayList<Decl> = ArrayList<Decl>()

    public init(mangled2Decl: RawMangled2DeclMap, cachedFileMap: CachedFileMap, curFileMap: FileMap,
        modified: ModifiedDecls) {
        md = mangled2Decl
        exc = GetAddedDecls(modified)
        for ((file, oldOrder) in cachedFileMap) {
            if (let Some(curOrder) <- curFileMap.get(file)) {
                for (decl in CompareOrders(oldOrder, curOrder)) { orderChanges.add(decl) }
            }
        }
        let empty = ArrayList<RawMangledName>()
        for ((file, curOrder) in curFileMap) {
            if (!cachedFileMap.contains(file)) {
                for (decl in CompareOrders(empty, curOrder)) { orderChanges.add(decl) }
            }
        }
    }

    private static func GetAddedDecls(modified: ModifiedDecls): HashSet<RawMangledName> {
        let result = HashSet<RawMangledName>()
        for (decl in modified.added) {
            if (IsImported(decl)) { continue }
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
                    if (IsOOEAffectedDecl(nested)) { result.add(decl.rawMangleName) }
                }
            }
        }
        for ((decl, _) in modified.types) {
            if (IsImported(decl)) { continue }
            for (member in GetMembers(decl)) {
                if (IsOOEAffectedDecl(member)) {
                    result.add(member.rawMangleName)
                    continue
                }
                for (nested in GetMembers(member)) {
                    if (IsOOEAffectedDecl(nested)) { result.add(decl.rawMangleName) }
                }
            }
        }
        return result
    }

    private static func IsGV(decl: Decl): Bool {
        return IsGlobalOrStaticVar(decl) || decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL
    }

    private static func BuildGvidMap(cur: ArrayList<Decl>): HashMap<RawMangledName, Int64> {
        let result = HashMap<RawMangledName, Int64>()
        for (decl in cur) { result[decl.rawMangleName] = decl.hash.gvid }
        return result
    }

    private func BuildMaxids(old: ArrayList<RawMangledName>, gvidMap: HashMap<RawMangledName, Int64>): ArrayList<Int64> {
        let maxids = ArrayList<Int64>()
        maxids.add(0)
        var last: Int64 = 0
        for (mangle in old) {
            if (let Some(currentGvid) <- gvidMap.get(mangle)) {
                let maxid = if (currentGvid > last) { currentGvid } else { last }
                maxids.add(maxid)
                CJC_ASSERT(md.contains(mangle))
                let decl = md[mangle]
                if (IsGV(decl)) { last = maxid }
            }
        }
        return maxids
    }

    private func FindRecompileDeclsFromOrder(old: ArrayList<RawMangledName>,
        gvidMap: HashMap<RawMangledName, Int64>, maxids: ArrayList<Int64>, result: HashSet<Decl>): Unit {
        var rid: Int64 = 0
        var idx: Int64 = 0
        while (idx < old.size) {
            if (let Some(currentGvid) <- gvidMap.get(old[idx])) {
                rid++
                if (currentGvid < maxids[rid]) { result.add(md[old[idx]]) }
            }
            idx++
        }
    }

    private func FindRecompileDeclsFromFileMove(cur: ArrayList<Decl>, oldNames: HashSet<RawMangledName>,
        exclude: HashSet<RawMangledName>, result: HashSet<Decl>): Unit {
        var idx = cur.size
        while (idx > 0) {
            idx--
            if (exclude.contains(cur[idx].rawMangleName)) { continue }
            if (oldNames.contains(cur[idx].rawMangleName)) { continue }
            result.add(cur[idx])
            if (IsGV(cur[idx])) {
                var preceding: Int64 = 0
                while (preceding < idx) {
                    result.add(cur[preceding])
                    preceding++
                }
                break
            }
        }
    }

    private func CompareOrders(old: ArrayList<RawMangledName>, cur: ArrayList<Decl>): ArrayList<Decl> {
        let gvidMap = BuildGvidMap(cur)
        let maxids = BuildMaxids(old, gvidMap)
        let result = HashSet<Decl>()
        FindRecompileDeclsFromOrder(old, gvidMap, maxids, result)
        let oldNames = HashSet<RawMangledName>()
        for (mangle in old) { oldNames.add(mangle) }
        FindRecompileDeclsFromFileMove(cur, oldNames, exc, result)
        let ordered = ArrayList<Decl>()
        for (decl in result) { ordered.add(decl) }
        return ordered
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
        let compare = OrderDiffCompare(mangled2Decl, cachedFileMap, curFileMap, ret)
        for (decl in compare.orderChanges) { ret.orderChanges.add(decl) }
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
                CJC_ASSERT(mangled2Decl.contains(mangled))
                CollectAddedTopLevelDecl(mangled2Decl[mangled])
            }
        }
    }

    private func CollectSourcePackage(pkg: Package): (ASTCache, HashSet<Decl>) {
        let calculator = ASTCacheCalculator(pkg, srcInfo)
        calculator.Walk()
        mangled2Decl = calculator.mangled2Decl
        return (calculator.ret, calculator.duplicatedMangleNames)
    }

    private func CollectAddedTopLevelDecl(decl: Decl): Unit {
        ret.added.add(decl)
    }

    private func CollectDeletedTopLevelDecl(mangled: RawMangledName, topDecl: TopLevelDeclCache): Unit {
        if (topDecl.astKind == UInt8(ASTKindIndex(ASTKind.TYPE_ALIAS_DECL))) {
            ret.deletedTypeAlias.add(mangled)
        } else {
            ret.deletes.add(mangled)
        }
        for (member in topDecl.members) { ret.deletes.add(member.rawMangle) }
    }

    private func CompareMemberDecl(typeChange: TypeChange, cached: MemberDeclCache, cur: MemberDeclCache): Unit {
        let change = CommonChange(mangled2Decl[cur.rawMangle], cached.sigHash != cur.sigHash,
            cached.srcUse != cur.srcUse, cached.bodyHash != cur.bodyHash)
        if (change.HasChange()) { typeChange.changed.add(change) }
        CompareMembers(typeChange, cached.members, cur.members)
    }

    private func CompareMembers(typeChange: TypeChange, cached: ArrayList<MemberDeclCache>,
        cur: ArrayList<MemberDeclCache>): Unit {
        let sortedCache = ArrayList<MemberDeclCache>()
        for (member in cached) { sortedCache.add(member) }
        sort(sortedCache, by: { left: MemberDeclCache, right: MemberDeclCache =>
            if (left.rawMangle < right.rawMangle) { Ordering.LT } else if (left.rawMangle > right.rawMangle) {
                Ordering.GT
            } else { Ordering.EQ }
        }, stable: true)
        let sortedCur = ArrayList<MemberDeclCache>()
        for (member in cur) { sortedCur.add(member) }
        sort(sortedCur, by: { left: MemberDeclCache, right: MemberDeclCache =>
            if (left.rawMangle < right.rawMangle) { Ordering.LT } else if (left.rawMangle > right.rawMangle) {
                Ordering.GT
            } else { Ordering.EQ }
        }, stable: true)
        var cachedIdx: Int64 = 0
        var curIdx: Int64 = 0
        while (cachedIdx < sortedCache.size && curIdx < sortedCur.size) {
            if (sortedCache[cachedIdx].rawMangle < sortedCur[curIdx].rawMangle) {
                typeChange.del.add(sortedCache[cachedIdx].rawMangle)
                for (child in sortedCache[cachedIdx].members) { typeChange.del.add(child.rawMangle) }
                cachedIdx++
                continue
            }
            if (sortedCache[cachedIdx].rawMangle > sortedCur[curIdx].rawMangle) {
                typeChange.added.add(mangled2Decl[sortedCur[curIdx].rawMangle])
                curIdx++
                continue
            }
            CompareMemberDecl(typeChange, sortedCache[cachedIdx], sortedCur[curIdx])
            cachedIdx++
            curIdx++
        }
        while (cachedIdx < sortedCache.size) {
            typeChange.del.add(sortedCache[cachedIdx].rawMangle)
            for (child in sortedCache[cachedIdx].members) { typeChange.del.add(child.rawMangle) }
            cachedIdx++
        }
        while (curIdx < sortedCur.size) {
            typeChange.added.add(mangled2Decl[sortedCur[curIdx].rawMangle])
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

    private static func CommonCompare(left: TopLevelDeclCache, right: TopLevelDeclCache,
        decl: Decl): CommonChange {
        return CommonChange(decl, left.sigHash != right.sigHash, left.srcUse != right.srcUse,
            left.bodyHash != right.bodyHash)
    }

    private func CompareTopLevelDecl(cachedDecl: TopLevelDeclCache, curDecl: TopLevelDeclCache,
        mangled: RawMangledName): Unit {
        let decl = mangled2Decl[mangled]
        if (decl.astKind == ASTKind.TYPE_ALIAS_DECL) {
            if (cachedDecl.sigHash != curDecl.sigHash) {
                ret.aliases.add((decl as TypeAliasDecl).getOrThrow())
            }
        } else if (decl.astKind == ASTKind.FUNC_DECL || decl.astKind == ASTKind.MACRO_DECL ||
            decl.astKind == ASTKind.MAIN_DECL || decl.astKind == ASTKind.VAR_DECL ||
            decl.astKind == ASTKind.VAR_WITH_PATTERN_DECL) {
            let change = CommonCompare(cachedDecl, curDecl, decl)
            if (change.HasChange()) { ret.commons[decl] = change }
        } else {
            let change = CompareTypeDecl(cachedDecl, curDecl)
            if (change.HasChange()) { ret.types[(decl as InheritableDecl).getOrThrow()] = change }
        }
    }
}

public func ASTDiff(args: ASTDiffArgs): ASTDiffResult {
    let impl = ASTDiffImpl((args.op.enableCompileDebug, args.op.displayLineInfo))
    for ((mangled, decl) in args.rawMangleName2DeclMap) {
        if (!args.importedMangled2Decl.contains(mangled)) {
            args.importedMangled2Decl[mangled] = decl
        }
    }
    impl.mangled2Decl = args.importedMangled2Decl
    impl.CompareCurPkgASTCache(args.prevCache.curPkgASTCache, args.astCacheInfo, args.prevCache.fileMap,
        args.curFileMap)
    impl.CompareImportedASTCache(args.prevCache.importedASTCache, args.curImports)
    return ASTDiffResult(impl.ret, impl.mangled2Decl)
}
