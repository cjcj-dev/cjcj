package cjcj::ast

import cjcj::utils.{CJC_ASSERT, FileUtil}
import std.collection.*

public class TrieNode {
    public var c: String = ""
    public var value: String = ""
    public var prefix: String = ""
    public var depth: UInt32 = 0u32
    public var parent: Option<TrieNode> = None
    public let next: HashMap<String, TrieNode> = HashMap<String, TrieNode>()
    public let suffixes: HashSet<String> = HashSet<String>()
    public let ids: TreeSet<Ptr<Symbol>> = TreeSet<Ptr<Symbol>>()
    public init() {}

    public init(c: String) {
        this.c = c
    }
}

public class Trie {
    public var root: TrieNode = TrieNode("R")

    public init() {}

    public func Reset(): Unit {
        root = TrieNode("R")
    }

    public func Reset(value: String): Unit {
        Reset()
        Insert(value)
    }

    public func Insert(value: String): Unit {
        var node = root
        var prefix = ""
        var idx: Int64 = 0
        for (byte in value.toArray()) {
            let key = String.fromUtf8([byte])
            prefix += key
            if (!node.next.contains(key)) {
                let child = TrieNode(key)
                child.prefix = prefix
                child.depth = node.depth + 1u32
                child.parent = node
                node.next[key] = child
            }
            if (let Some(child) <- node.next.get(key)) {
                node = child
                if (idx + 1 < value.size) {
                    node.suffixes.add(value[(idx + 1)..])
                }
            }
            idx++
        }
        node.value = value
    }

    public func Insert(value: String, symbol: Symbol): Unit {
        var node = root
        var prefix = ""
        var idx: Int64 = 0
        for (byte in value.toArray()) {
            let key = String.fromUtf8([byte])
            prefix += key
            if (!node.next.contains(key)) {
                let child = TrieNode(key)
                child.prefix = prefix
                child.depth = node.depth + 1u32
                child.parent = node
                node.next[key] = child
            }
            if (let Some(child) <- node.next.get(key)) {
                node = child
                node.ids.add(Ptr<Symbol>(symbol))
                if (idx + 1 < value.size) {
                    node.suffixes.add(value[(idx + 1)..])
                }
            }
            idx++
        }
        node.value = value
    }

    public func Delete(value: String, symbol: Symbol): Unit {
        var node = root
        for (byte in value.toArray()) {
            let key = String.fromUtf8([byte])
            if (let Some(child) <- node.next.get(key)) {
                child.ids.remove(Ptr<Symbol>(symbol))
                node = child
            } else {
                return
            }
        }
    }

    public func PrefixMatch(prefix: String): ArrayList<String> {
        let out = ArrayList<String>()
        let prefixRoot = GetPrefixRootNode(prefix)
        if (let None <- prefixRoot) {
            return out
        }
        collect(prefixRoot.getOrThrow(), out)
        return out
    }

    public func GetPrefixRootNode(prefix: String): Option<TrieNode> {
        var node = root
        for (byte in prefix.toArray()) {
            let key = String.fromUtf8([byte])
            if (let Some(child) <- node.next.get(key)) {
                node = child
            } else {
                return None
            }
        }
        return node
    }

    public func SuffixMatch(suffix: String): ArrayList<String> {
        let out = ArrayList<String>()
        collectSuffix(root, suffix, out)
        return out
    }

    private func collect(node: TrieNode, out: ArrayList<String>): Unit {
        if (!node.value.isEmpty()) {
            out.add(node.value)
        }
        for ((_, child) in node.next) {
            collect(child, out)
        }
    }

    private func collectSuffix(node: TrieNode, suffix: String, out: ArrayList<String>): Unit {
        if (node.suffixes.contains(suffix)) {
            out.add(node.prefix + suffix)
        }
        for ((_, child) in node.next) {
            collectSuffix(child, suffix, out)
        }
    }

}

public class PosSearchApi {
    public static var MAX_DIGITS_FILE: Int64 = 4
    public static var MAX_DIGITS_LINE: Int64 = 5
    public static var MAX_DIGITS_COLUMN: Int64 = 5
    public static let MAX_LINE: Int64 = 1000000
    public static let MAX_COLUMN: Int64 = 10000

    public init() {}

    public static func UpdatePosLimit(fileId: UInt64, line: Int64, column: Int64): Unit {
        let fileDigits = countDigitsUInt(fileId)
        let lineDigits = countDigitsInt(line)
        let columnDigits = countDigitsInt(column)
        if (fileDigits > MAX_DIGITS_FILE) {
            MAX_DIGITS_FILE = fileDigits
        }
        if (lineDigits > MAX_DIGITS_LINE) {
            MAX_DIGITS_LINE = lineDigits
        }
        if (columnDigits > MAX_DIGITS_COLUMN) {
            MAX_DIGITS_COLUMN = columnDigits
        }
    }

    public static func GetMaxDigitsPostion(): Int64 {
        return MAX_DIGITS_FILE + MAX_DIGITS_LINE + MAX_DIGITS_COLUMN
    }

    public static func PosToStr(pos: Position): String {
        return fillZeroUInt(pos.fileID, MAX_DIGITS_FILE) +
            fillZeroInt(pos.line, MAX_DIGITS_LINE) +
            fillZeroInt(pos.column, MAX_DIGITS_COLUMN)
    }

    public static func FindCommonRootInPosTrie(posTrie: Trie, pos: Position): TrieNode {
        return FindCommonRootInPosTrie(posTrie, PosToStr(pos))
    }

    public static func FindCommonRootInPosTrie(posTrie: Trie, pos: String): TrieNode {
        var node = posTrie.root
        for (byte in pos.toArray()) {
            let key = String.fromUtf8([byte])
            if (let Some(child) <- node.next.get(key)) {
                node = child
            } else {
                return node
            }
        }
        return node
    }

    public static func GetIDsWithinPosXByRange(posTrie: Trie, startPos: Position, endPos: Position,
        isLeftClose!: Bool = true, isRightClose!: Bool = false): TreeSet<Ptr<Symbol>> {
        let out = TreeSet<Ptr<Symbol>>()
        if (endPos <= startPos) {
            return out
        }
        let left = GetIDsGreaterThanPos(posTrie, startPos, isClose: isLeftClose)
        let right = GetIDsLessThanPos(posTrie, endPos, isClose: isRightClose)
        for (symbol in left) {
            if (right.contains(symbol)) {
                out.add(symbol)
            }
        }
        return out
    }

    public static func GetIDsGreaterThanPos(posTrie: Trie, pos: Position,
        isClose!: Bool = true): TreeSet<Ptr<Symbol>> {
        let posStr = PosToStr(pos)
        var node = FindCommonRootInPosTrie(posTrie, posStr)
        let out = TreeSet<Ptr<Symbol>>()
        var close = isClose
        while (Int64(node.depth) > MAX_DIGITS_FILE) {
            if (Int64(node.depth) == GetMaxDigitsPostion()) {
                if (let Some(parent) <- node.parent) {
                    node = parent
                    continue
                }
                break
            }
            let target = digitAt(posStr, node.depth)
            for ((key, child) in node.next) {
                let selected = if (close) { !(key < target) } else { target < key }
                if (selected) {
                    for (symbol in child.ids) {
                        out.add(symbol)
                    }
                }
            }
            close = false
            if (let Some(parent) <- node.parent) {
                node = parent
            } else {
                break
            }
        }
        return out
    }

    public static func GetIDsLessThanPos(posTrie: Trie, pos: Position,
        isClose!: Bool = true): TreeSet<Ptr<Symbol>> {
        let posStr = PosToStr(pos)
        var node = FindCommonRootInPosTrie(posTrie, posStr)
        let out = TreeSet<Ptr<Symbol>>()
        let close = Box<Bool>(isClose)
        while (Int64(node.depth) > MAX_DIGITS_FILE) {
            if (Int64(node.depth) == GetMaxDigitsPostion()) {
                CJC_ASSERT(node.next.isEmpty())
                if (let Some(parent) <- node.parent) {
                    node = parent
                    continue
                }
                break
            }
            GetIDsLessThanPosOfDepth(node, posStr, out, close)
            if (let Some(parent) <- node.parent) {
                node = parent
            } else {
                break
            }
        }
        return out
    }

    public static func GetIDsLessThanPosOfDepth(
        n: TrieNode, posStr: String, ids: TreeSet<Ptr<Symbol>>, isClose: Box<Bool>): Unit {
        let target = digitAt(posStr, n.depth)
        var endIter = ""
        var foundEndIter = false
        for ((key, _) in n.next) {
            if (!(key < target) && (!foundEndIter || key < endIter)) {
                endIter = key
                foundEndIter = true
            }
        }
        var includeEndIter = false
        if (foundEndIter) {
            if (isClose.value) {
                if (endIter == target) {
                    includeEndIter = true
                }
                isClose.value = false
            }
        }
        for ((key, child) in n.next) {
            if (!foundEndIter || key < endIter || (includeEndIter && key == endIter)) {
                for (symbol in child.ids) {
                    ids.add(symbol)
                }
            }
        }
    }

    private static func digitAt(value: String, depth: UInt32): String {
        let idx = Int64(depth)
        if (idx < 0 || idx >= value.size) {
            return ""
        }
        return value[idx..(idx + 1)]
    }

    private static func fillZeroUInt(value: UInt64, width: Int64): String {
        var out = "${value}"
        while (out.size < width) {
            out = "0" + out
        }
        return out
    }

    private static func fillZeroInt(value: Int64, width: Int64): String {
        var out = "${value}"
        while (out.size < width) {
            out = "0" + out
        }
        return out
    }

    private static func countDigitsUInt(value: UInt64): Int64 {
        return "${value}".size
    }

    private static func countDigitsInt(value: Int64): Int64 {
        return "${value}".size
    }
}

public class Sort {
    public init() {}

    public static func PosAsc(left: Symbol, right: Symbol): Bool {
        if (let Some(leftNode) <- left.node) {
            if (let Some(rightNode) <- right.node) {
                if (leftNode.begin.fileID < rightNode.begin.fileID) {
                    return true
                }
                if (leftNode.begin.fileID > rightNode.begin.fileID) {
                    return false
                }
                if (leftNode.begin < rightNode.begin) {
                    return true
                }
                if (rightNode.begin < leftNode.begin) {
                    return false
                }
                if (leftNode.end == rightNode.end) {
                    return ASTKindIndex(left.astKind) < ASTKindIndex(right.astKind)
                }
                return rightNode.end < leftNode.end
            }
            return false
        }
        if (let Some(_) <- right.node) {
            return true
        }
        if (left.hashID != right.hashID) {
            return left.hashID < right.hashID
        }
        if (left.name != right.name) {
            return left.name < right.name
        }
        return left.scopeName < right.scopeName
    }

    public static func PosDesc(left: Symbol, right: Symbol): Bool {
        return Sort.PosAsc(right, left)
    }
}

public enum SearchOrder {
    | POS_ASC
    | POS_DESC
}

private func SearchOrderIndex(order: SearchOrder): Int64 {
    return match (order) {
        case SearchOrder.POS_ASC => 0
        case SearchOrder.POS_DESC => 1
    }
}

extend SearchOrder <: Equatable<SearchOrder> {
    public operator func ==(right: SearchOrder): Bool {
        return SearchOrderIndex(this) == SearchOrderIndex(right)
    }

    public operator func !=(right: SearchOrder): Bool {
        return !(this == right)
    }
}

public class Searcher {
    private let cache: HashMap<String, ArrayList<Symbol>> = HashMap<String, ArrayList<Symbol>>()

    public init() {}

    public func Search(ctx: ASTContext, query: String, order!: SearchOrder = SearchOrder.POS_DESC): ArrayList<Symbol> {
        let parsed = ParseQuery(query)
        return Search(ctx, parsed, order: order)
    }

    public func Search(ctx: ASTContext, query: String, fileHashes: HashSet<UInt64>,
        order!: SearchOrder = SearchOrder.POS_DESC): ArrayList<Symbol> {
        let parsed = ParseQuery(query)
        parsed.AddFileHashes(fileHashes)
        return Search(ctx, parsed, order: order)
    }

    public func Search(ctx: ASTContext, query: String, fileHashes: ArrayList<UInt64>,
        order!: SearchOrder = SearchOrder.POS_DESC): ArrayList<Symbol> {
        let parsed = ParseQuery(query)
        for (fileHash in fileHashes) {
            parsed.AddFileHash(fileHash)
        }
        return Search(ctx, parsed, order: order)
    }

    public func Search(ctx: ASTContext, query: Query, order!: SearchOrder = SearchOrder.POS_DESC): ArrayList<Symbol> {
        let key = NormalizeQuery(query, order: order)
        let cached = FindInSearchCache(query, key)
        if (cached[1]) {
            return cached[0]
        }
        let ids = PerformSearch(ctx, query)
        let out = FilterAndSortSearchResult(ids, query, order: order)
        cache[key] = out
        return out
    }

    public func InvalidateCache(): Unit {
        cache.clear()
    }

    public func InvalidateCacheBut(query: String): Unit {
        let keysToRemove = ArrayList<String>()
        for ((key, _) in cache) {
            if (!key.contains(query)) {
                keysToRemove.add(key)
            }
        }
        for (key in keysToRemove) {
            cache.remove(key)
        }
    }

    public func SetCache(newCache: HashMap<String, ArrayList<Symbol>>): Unit {
        cache.clear()
        for ((key, values) in newCache) {
            cache[key] = values
        }
    }

    public func GetCache(): HashMap<String, ArrayList<Symbol>> {
        let out = HashMap<String, ArrayList<Symbol>>()
        for ((key, values) in cache) {
            out[key] = values
        }
        return out
    }

    public func GetScopeNamesByPrefix(ctx: ASTContext, prefix: String): ArrayList<String> {
        if (!ctx.invertedIndex.scopeNameIndexes.isEmpty()) {
            return ctx.invertedIndex.scopeNameTrie.PrefixMatch(prefix)
        }
        let out = ArrayList<String>()
        for (symbol in ctx.symbolTable) {
            if (!symbol.invertedIndexBeenDeleted && symbol.scopeName.startsWith(prefix)) {
                AddUniqueString(out, symbol.scopeName)
            }
        }
        return out
    }

    private func NormalizeQuery(query: Query, order!: SearchOrder = SearchOrder.POS_DESC): String {
        var normalized = query.PrettyPrint()
        for (fileHash in query.fileHashes) {
            normalized += "|fileHash:" + FileUtil.GetShortHash(fileHash)
        }
        if (order == SearchOrder.POS_ASC) {
            normalized += "|sort:asc"
        } else {
            normalized += "|sort:desc"
        }
        return normalized
    }

    // Mirrors AST/Searcher.cpp:307-328 Searcher::FindInSearchCache.
    private func FindInSearchCache(query: Query, normalizedQuery: String): (ArrayList<Symbol>, Bool) {
        let results = ArrayList<Symbol>()
        if (let Some(values) <- cache.get(normalizedQuery)) {
            if (!query.HasFileHashFilter()) {
                return (values, true)
            }
            for (symbol in values) {
                if (InFiles(query, symbol)) {
                    results.add(symbol)
                }
            }
            return (results, true)
        }
        return (results, false)
    }

    private func FilterAndSortSearchResult(ids: TreeSet<Ptr<Symbol>>, query: Query,
        order!: SearchOrder = SearchOrder.POS_DESC): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        for (id in ids) {
            let symbol = id.value
            if (!symbol.invertedIndexBeenDeleted && InFiles(query, symbol)) {
                insertByPosition(out, symbol, order: order)
            }
        }
        return out
    }

    private func InFiles(query: Query, symbol: Symbol): Bool {
        return !query.HasFileHashFilter() || query.fileHashes.contains(symbol.hashID.hash64)
    }

    private func PerformSearch(ctx: ASTContext, query: Query): TreeSet<Ptr<Symbol>> {
        if (let Some(compound) <- (query as CompoundQuery)) {
            if (compound.children.isEmpty()) {
                return AllLiveSymbols(ctx)
            }
            if (compound.kind == QueryKind.AND) {
                var out = PerformSearch(ctx, compound.children[0])
                var idx: Int64 = 1
                while (idx < compound.children.size) {
                    out = Intersection(out, PerformSearch(ctx, compound.children[idx]))
                    idx++
                }
                return out
            }
            if (compound.kind == QueryKind.OR) {
                var out = TreeSet<Ptr<Symbol>>()
                for (child in compound.children) {
                    out = Union(out, PerformSearch(ctx, child))
                }
                return out
            }
            if (compound.kind == QueryKind.NOT) {
                if (compound.children.size == 1) {
                    return Difference(AllLiveSymbols(ctx), PerformSearch(ctx, compound.children[0]))
                }
                return Difference(PerformSearch(ctx, compound.children[0]), PerformSearch(ctx, compound.children[1]))
            }
            return FilterByMatcher(ctx, compound)
        }
        return GetIDs(ctx, query)
    }

    // Mirrors AST/Searcher.cpp:634-656 Searcher::GetIDs.
    private func GetIDs(ctx: ASTContext, query: Query): TreeSet<Ptr<Symbol>> {
        if (let Some(nameQuery) <- (query as NameQuery)) {
            return GetIDsByName(ctx, nameQuery)
        }
        if (let Some(scopeQuery) <- (query as ScopeQuery)) {
            return GetIDsByScopeName(ctx, scopeQuery)
        }
        if (let Some(kindQuery) <- (query as ASTKindQuery)) {
            return GetIDsByASTKind(ctx, kindQuery)
        }
        if (let Some(levelQuery) <- (query as ScopeLevelQuery)) {
            return GetIDsByScopeLevel(ctx, levelQuery)
        }
        if (let Some(positionQuery) <- (query as PositionQuery)) {
            return GetIDsByPos(ctx, positionQuery)
        }
        return FilterByMatcher(ctx, query)
    }

    private func GetIDsByName(ctx: ASTContext, query: NameQuery): TreeSet<Ptr<Symbol>> {
        if (ctx.invertedIndex.nameIndexes.isEmpty()) {
            return FilterByMatcher(ctx, query)
        }
        if (query.value.isEmpty()) {
            return ValuesFromStringIndex(ctx.invertedIndex.nameIndexes)
        }
        if (query.matchKind == MatchKind.PRECISE) {
            return SymbolsForKey(ctx.invertedIndex.nameIndexes, query.value)
        }
        if (query.matchKind == MatchKind.PREFIX) {
            return GetIDsByNamePrefix(ctx, query.value)
        }
        return GetIDsByNameSuffix(ctx, query.value)
    }

    // Mirrors AST/Searcher.cpp:384-392 Searcher::GetIDsByNamePrefix.
    private func GetIDsByNamePrefix(ctx: ASTContext, prefix: String): TreeSet<Ptr<Symbol>> {
        return SymbolsForKeys(ctx.invertedIndex.nameIndexes, ctx.invertedIndex.nameTrie.PrefixMatch(prefix))
    }

    // Mirrors AST/Searcher.cpp:394-402 Searcher::GetIDsByNameSuffix.
    private func GetIDsByNameSuffix(ctx: ASTContext, suffix: String): TreeSet<Ptr<Symbol>> {
        return SymbolsForKeys(ctx.invertedIndex.nameIndexes, ctx.invertedIndex.nameTrie.SuffixMatch(suffix))
    }

    private func GetIDsByScopeName(ctx: ASTContext, query: ScopeQuery): TreeSet<Ptr<Symbol>> {
        if (ctx.invertedIndex.scopeNameIndexes.isEmpty()) {
            return FilterByMatcher(ctx, query)
        }
        if (query.matchKind == MatchKind.SUFFIX) {
            return TreeSet<Ptr<Symbol>>()
        }
        if (query.value.isEmpty()) {
            return ValuesFromStringIndex(ctx.invertedIndex.scopeNameIndexes)
        }
        if (query.matchKind == MatchKind.PRECISE) {
            return SymbolsForKey(ctx.invertedIndex.scopeNameIndexes, query.value)
        }
        var out = TreeSet<Ptr<Symbol>>()
        for (scopeName in ctx.invertedIndex.scopeNameTrie.PrefixMatch(query.value)) {
            out = Union(out, SymbolsForKey(ctx.invertedIndex.scopeNameIndexes, scopeName))
        }
        return out
    }

    private func GetIDsByScopeLevel(ctx: ASTContext, query: ScopeLevelQuery): TreeSet<Ptr<Symbol>> {
        if (ctx.invertedIndex.scopeLevelIndexes.isEmpty()) {
            return FilterByMatcher(ctx, query)
        }
        var out = TreeSet<Ptr<Symbol>>()
        if (query.comparator == PositionCompare.EQ) {
            if (let Some(values) <- ctx.invertedIndex.scopeLevelIndexes.get(query.level)) {
                out = Union(out, values)
            }
            return out
        }
        if (query.comparator == PositionCompare.LT || query.comparator == PositionCompare.LE) {
            var currentLevel: UInt32 = 0u32
            while (currentLevel < query.level || (query.comparator == PositionCompare.LE && currentLevel == query.level)) {
                if (let Some(values) <- ctx.invertedIndex.scopeLevelIndexes.get(currentLevel)) {
                    out = Union(out, values)
                }
                if (currentLevel == UInt32.Max) {
                    break
                }
                currentLevel++
            }
        }
        return out
    }

    private func GetIDsByASTKind(ctx: ASTContext, query: ASTKindQuery): TreeSet<Ptr<Symbol>> {
        if (ctx.invertedIndex.astKindIndexes.isEmpty()) {
            return FilterByMatcher(ctx, query)
        }
        if (query.matchKind == MatchKind.PREFIX) {
            return TreeSet<Ptr<Symbol>>()
        }
        if (query.valueText.isEmpty()) {
            return ValuesFromStringIndex(ctx.invertedIndex.astKindIndexes)
        }
        if (query.matchKind == MatchKind.PRECISE) {
            return SymbolsForKey(ctx.invertedIndex.astKindIndexes, query.valueText)
        }
        return SymbolsForKeys(ctx.invertedIndex.astKindIndexes, GetAstKindsBySuffix(ctx, query.valueText))
    }

    // Mirrors AST/Searcher.cpp:450-453 Searcher::GetAstKindsBySuffix.
    private func GetAstKindsBySuffix(ctx: ASTContext, suffix: String): ArrayList<String> {
        return ctx.invertedIndex.astKindTrie.SuffixMatch(suffix)
    }

    private func GetIDsByPos(ctx: ASTContext, query: PositionQuery): TreeSet<Ptr<Symbol>> {
        if (ctx.invertedIndex.posBeginTrie.root.next.isEmpty() || ctx.invertedIndex.posEndTrie.root.next.isEmpty()) {
            return FilterByMatcher(ctx, query)
        }
        if (query.comparator == PositionCompare.EQ) {
            return GetIDsByPosEQ(ctx, query.pos)
        }
        if (query.comparator == PositionCompare.LT) {
            return GetIDsByPosLT(ctx, query.pos)
        }
        if (query.comparator == PositionCompare.LE) {
            return GetIDsByPosLT(ctx, query.pos, contain: true)
        }
        if (query.comparator == PositionCompare.GT) {
            return GetIDsByPosGT(ctx, query.pos)
        }
        return GetIDsByPosGT(ctx, query.pos, contain: true)
    }

    private func GetIDsByPosEQ(ctx: ASTContext, pos: Position, isLeftClose!: Bool = true,
        isRightClose!: Bool = true): TreeSet<Ptr<Symbol>> {
        let beginIDs = PosSearchApi.GetIDsLessThanPos(ctx.invertedIndex.posBeginTrie, pos, isClose: isLeftClose)
        let endIDs = PosSearchApi.GetIDsGreaterThanPos(ctx.invertedIndex.posEndTrie, pos, isClose: isRightClose)
        if (!endIDs.isEmpty()) {
            return Intersection(beginIDs, endIDs)
        }
        if (beginIDs.isEmpty()) {
            return TreeSet<Ptr<Symbol>>()
        }
        let out = TreeSet<Ptr<Symbol>>()
        var remaining: Int64 = -1
        var initialized = false
        for (symbol in beginIDs) {
            if (!initialized) {
                remaining = Int64(symbol.value.scopeLevel)
                initialized = true
            }
            if (remaining >= 0) {
                out.add(symbol)
                remaining--
            } else {
                break
            }
        }
        return out
    }

    private func GetIDsByPosLT(ctx: ASTContext, pos: Position,
        contain!: Bool = false): TreeSet<Ptr<Symbol>> {
        let out = PosSearchApi.GetIDsLessThanPos(ctx.invertedIndex.posEndTrie, pos, isClose: false)
        if (contain) {
            return Union(out, GetIDsByPosEQ(ctx, pos))
        }
        return out
    }

    private func GetIDsByPosGT(ctx: ASTContext, pos: Position,
        contain!: Bool = false): TreeSet<Ptr<Symbol>> {
        let out = PosSearchApi.GetIDsGreaterThanPos(ctx.invertedIndex.posBeginTrie, pos, isClose: false)
        if (contain) {
            return Union(out, GetIDsByPosEQ(ctx, pos))
        }
        return out
    }

    private func SymbolsForKeys(map: HashMap<String, TreeSet<Ptr<Symbol>>>,
        keys: ArrayList<String>): TreeSet<Ptr<Symbol>> {
        var out = TreeSet<Ptr<Symbol>>()
        for (key in keys) {
            out = Union(out, SymbolsForKey(map, key))
        }
        return out
    }

    private func SymbolsForKey(map: HashMap<String, TreeSet<Ptr<Symbol>>>,
        key: String): TreeSet<Ptr<Symbol>> {
        let out = TreeSet<Ptr<Symbol>>()
        if (let Some(values) <- map.get(key)) {
            for (value in values) {
                out.add(value)
            }
        }
        return out
    }

    private func ValuesFromStringIndex(
        map: HashMap<String, TreeSet<Ptr<Symbol>>>): TreeSet<Ptr<Symbol>> {
        let out = TreeSet<Ptr<Symbol>>()
        for ((_, values) in map) {
            for (value in values) {
                out.add(value)
            }
        }
        return out
    }

    private func FilterByMatcher(ctx: ASTContext, query: Query): TreeSet<Ptr<Symbol>> {
        let out = TreeSet<Ptr<Symbol>>()
        for (symbol in ctx.symbolTable) {
            if (!symbol.invertedIndexBeenDeleted && query.Match(symbol)) {
                out.add(Ptr<Symbol>(symbol))
            }
        }
        return out
    }

    private func AllLiveSymbols(ctx: ASTContext): TreeSet<Ptr<Symbol>> {
        let out = TreeSet<Ptr<Symbol>>()
        for (symbol in ctx.symbolTable) {
            if (!symbol.invertedIndexBeenDeleted) {
                out.add(Ptr<Symbol>(symbol))
            }
        }
        return out
    }

    private func Intersection(left: TreeSet<Ptr<Symbol>>,
        right: TreeSet<Ptr<Symbol>>): TreeSet<Ptr<Symbol>> {
        let out = TreeSet<Ptr<Symbol>>()
        for (item in right) {
            if (left.contains(item)) {
                out.add(item)
            }
        }
        return out
    }

    private func Union(left: TreeSet<Ptr<Symbol>>,
        right: TreeSet<Ptr<Symbol>>): TreeSet<Ptr<Symbol>> {
        let out = TreeSet<Ptr<Symbol>>()
        for (item in left) {
            out.add(item)
        }
        for (item in right) {
            out.add(item)
        }
        return out
    }

    private func Difference(left: TreeSet<Ptr<Symbol>>,
        right: TreeSet<Ptr<Symbol>>): TreeSet<Ptr<Symbol>> {
        let out = TreeSet<Ptr<Symbol>>()
        for (item in left) {
            if (!right.contains(item)) {
                out.add(item)
            }
        }
        return out
    }

    private func AddUniqueString(out: ArrayList<String>, value: String): Unit {
        for (item in out) {
            if (item == value) {
                return
            }
        }
        out.add(value)
    }

    private func symbolBefore(left: Symbol, right: Symbol, order: SearchOrder): Bool {
        if (order == SearchOrder.POS_ASC) {
            return Sort.PosAsc(left, right)
        }
        return Sort.PosDesc(left, right)
    }

    private func insertByPosition(out: ArrayList<Symbol>, symbol: Symbol,
        order!: SearchOrder = SearchOrder.POS_DESC): Unit {
        var idx: Int64 = 0
        while (idx < out.size) {
            if (symbolBefore(symbol, out[idx], order)) {
                out.add(symbol, at: idx)
                return
            }
            idx++
        }
        out.add(symbol)
    }
}
