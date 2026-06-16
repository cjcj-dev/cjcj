package cangjie_compiler::ast

import std.collection.*

public class TrieNode {
    public var c: String = ""
    public var value: String = ""
    public var prefix: String = ""
    public var depth: UInt32 = 0u32
    public var parent: Option<TrieNode> = None
    public let next: HashMap<String, TrieNode> = HashMap<String, TrieNode>()
    public let suffixes: HashSet<String> = HashSet<String>()
    public let ids: ArrayList<Symbol> = ArrayList<Symbol>()
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
        Insert(value, Symbol(value))
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
                addUniqueSymbol(node.ids, symbol)
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
                removeSymbol(child.ids, symbol)
                node = child
            } else {
                return
            }
        }
    }

    public func PrefixMatch(prefix: String): ArrayList<String> {
        let out = ArrayList<String>()
        if (prefix.isEmpty()) {
            collect(root, out)
            return out
        }
        var node = root
        for (byte in prefix.toArray()) {
            let key = String.fromUtf8([byte])
            if (let Some(child) <- node.next.get(key)) {
                node = child
            } else {
                return out
            }
        }
        collect(node, out)
        return out
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

    private func addUniqueSymbol(values: ArrayList<Symbol>, symbol: Symbol): Unit {
        for (value in values) {
            if (SameSymbol(value, symbol)) {
                return
            }
        }
        values.add(symbol)
    }

    private func removeSymbol(values: ArrayList<Symbol>, symbol: Symbol): Unit {
        var idx: Int64 = 0
        while (idx < values.size) {
            if (SameSymbol(values[idx], symbol)) {
                values.remove(at: idx)
            } else {
                idx++
            }
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

    public static func GetIDsWithinPosXByRange(posTrie: Trie, startPos: Position, endPos: Position,
        isLeftClose!: Bool = true, isRightClose!: Bool = false): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        collectPositionSymbols(posTrie.root, out, startPos, endPos, isLeftClose, isRightClose)
        return out
    }

    public static func GetIDsGreaterThanPos(posTrie: Trie, pos: Position, isClose!: Bool = true): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        collectGreaterSymbols(posTrie.root, out, pos, isClose)
        return out
    }

    public static func GetIDsLessThanPos(posTrie: Trie, pos: Position, isClose!: Bool = true): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        collectLessSymbols(posTrie.root, out, pos, isClose)
        return out
    }

    private static func collectPositionSymbols(node: TrieNode, out: ArrayList<Symbol>, startPos: Position,
        endPos: Position, isLeftClose: Bool, isRightClose: Bool): Unit {
        for (symbol in node.ids) {
            if (let Some(symbolNode) <- symbol.node) {
                let begin = symbolNode.begin
                let leftOk = if (isLeftClose) { startPos <= begin } else { startPos < begin }
                let rightOk = if (isRightClose) { begin <= endPos } else { begin < endPos }
                if (leftOk && rightOk) {
                    addUniqueSymbol(out, symbol)
                }
            }
        }
        for ((_, child) in node.next) {
            collectPositionSymbols(child, out, startPos, endPos, isLeftClose, isRightClose)
        }
    }

    private static func collectGreaterSymbols(node: TrieNode, out: ArrayList<Symbol>, pos: Position,
        isClose: Bool): Unit {
        for (symbol in node.ids) {
            if (let Some(symbolNode) <- symbol.node) {
                let begin = symbolNode.begin
                if ((isClose && pos <= begin) || (!isClose && pos < begin)) {
                    addUniqueSymbol(out, symbol)
                }
            }
        }
        for ((_, child) in node.next) {
            collectGreaterSymbols(child, out, pos, isClose)
        }
    }

    private static func collectLessSymbols(node: TrieNode, out: ArrayList<Symbol>, pos: Position,
        isClose: Bool): Unit {
        for (symbol in node.ids) {
            if (let Some(symbolNode) <- symbol.node) {
                let begin = symbolNode.begin
                if ((isClose && begin <= pos) || (!isClose && begin < pos)) {
                    addUniqueSymbol(out, symbol)
                }
            }
        }
        for ((_, child) in node.next) {
            collectLessSymbols(child, out, pos, isClose)
        }
    }

    private static func addUniqueSymbol(values: ArrayList<Symbol>, symbol: Symbol): Unit {
        for (value in values) {
            if (SameSymbol(value, symbol)) {
                return
            }
        }
        values.add(symbol)
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

public class Searcher {
    private let cache: HashMap<String, ArrayList<Symbol>> = HashMap<String, ArrayList<Symbol>>()

    public init() {}

    public func Search(ctx: ASTContext, query: String): ArrayList<Symbol> {
        let parsed = ParseQuery(query)
        let key = parsed.PrettyPrint()
        if (let Some(values) <- cache.get(key)) {
            return values
        }
        let out = Search(ctx, parsed)
        cache[key] = out
        return out
    }

    public func Search(ctx: ASTContext, query: Query): ArrayList<Symbol> {
        let ids = PerformSearch(ctx, query)
        let out = ArrayList<Symbol>()
        for (symbol in ids) {
            if (!symbol.invertedIndexBeenDeleted) {
                insertByPosition(out, symbol)
            }
        }
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

    private func PerformSearch(ctx: ASTContext, query: Query): ArrayList<Symbol> {
        if (let Some(compound) <- (query as CompoundQuery)) {
            return PerformCompoundSearch(ctx, compound)
        }
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
            return GetIDsByScopeLevel(ctx, levelQuery.level)
        }
        return FilterByMatcher(ctx, query)
    }

    private func PerformCompoundSearch(ctx: ASTContext, query: CompoundQuery): ArrayList<Symbol> {
        if (query.children.isEmpty()) {
            return AllLiveSymbols(ctx)
        }
        if (query.kind == QueryKind.AND) {
            var out = PerformSearch(ctx, query.children[0])
            var idx: Int64 = 1
            while (idx < query.children.size) {
                out = Intersection(out, PerformSearch(ctx, query.children[idx]))
                idx++
            }
            return out
        }
        if (query.kind == QueryKind.OR) {
            let out = ArrayList<Symbol>()
            for (child in query.children) {
                AddAllUnique(out, PerformSearch(ctx, child))
            }
            return out
        }
        if (query.kind == QueryKind.NOT) {
            if (query.children.size == 1) {
                return Difference(AllLiveSymbols(ctx), PerformSearch(ctx, query.children[0]))
            }
            return Difference(PerformSearch(ctx, query.children[0]), PerformSearch(ctx, query.children[1]))
        }
        return FilterByMatcher(ctx, query)
    }

    private func GetIDsByName(ctx: ASTContext, query: NameQuery): ArrayList<Symbol> {
        if (ctx.invertedIndex.nameIndexes.isEmpty()) {
            return FilterByMatcher(ctx, query)
        }
        if (query.value.isEmpty()) {
            return ValuesFromStringIndex(ctx.invertedIndex.nameIndexes)
        }
        if (query.matchKind == MatchKind.PRECISE) {
            return SymbolsForKey(ctx.invertedIndex.nameIndexes, query.value)
        }
        let names = if (query.matchKind == MatchKind.PREFIX) {
            ctx.invertedIndex.nameTrie.PrefixMatch(query.value)
        } else {
            ctx.invertedIndex.nameTrie.SuffixMatch(query.value)
        }
        return SymbolsForKeys(ctx.invertedIndex.nameIndexes, names)
    }

    private func GetIDsByScopeName(ctx: ASTContext, query: ScopeQuery): ArrayList<Symbol> {
        if (ctx.invertedIndex.scopeNameIndexes.isEmpty()) {
            return FilterByMatcher(ctx, query)
        }
        if (query.matchKind == MatchKind.SUFFIX) {
            return ArrayList<Symbol>()
        }
        if (query.value.isEmpty()) {
            return ValuesFromStringIndex(ctx.invertedIndex.scopeNameIndexes)
        }
        if (query.matchKind == MatchKind.PRECISE) {
            return SymbolsForKey(ctx.invertedIndex.scopeNameIndexes, query.value)
        }
        let out = ArrayList<Symbol>()
        for (scopeName in ctx.invertedIndex.scopeNameTrie.PrefixMatch(query.value)) {
            AddAllUnique(out, SymbolsForKey(ctx.invertedIndex.scopeNameIndexes, GetScopeNameWithoutTail(scopeName)))
        }
        return out
    }

    private func GetIDsByScopeLevel(ctx: ASTContext, level: UInt32): ArrayList<Symbol> {
        if (ctx.invertedIndex.scopeLevelIndexes.isEmpty()) {
            return FilterByMatcher(ctx, ScopeLevelQuery(level))
        }
        let out = ArrayList<Symbol>()
        if (let Some(values) <- ctx.invertedIndex.scopeLevelIndexes.get(level)) {
            AddAllUnique(out, values)
        }
        return out
    }

    private func GetIDsByASTKind(ctx: ASTContext, query: ASTKindQuery): ArrayList<Symbol> {
        if (ctx.invertedIndex.astKindIndexes.isEmpty()) {
            return FilterByMatcher(ctx, query)
        }
        if (query.matchKind == MatchKind.PREFIX) {
            return ArrayList<Symbol>()
        }
        if (query.valueText.isEmpty()) {
            return ValuesFromStringIndex(ctx.invertedIndex.astKindIndexes)
        }
        if (query.matchKind == MatchKind.PRECISE) {
            return SymbolsForKey(ctx.invertedIndex.astKindIndexes, query.valueText)
        }
        return SymbolsForKeys(ctx.invertedIndex.astKindIndexes, ctx.invertedIndex.astKindTrie.SuffixMatch(query.valueText))
    }

    private func SymbolsForKeys(map: HashMap<String, ArrayList<Symbol>>, keys: ArrayList<String>): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        for (key in keys) {
            AddAllUnique(out, SymbolsForKey(map, key))
        }
        return out
    }

    private func SymbolsForKey(map: HashMap<String, ArrayList<Symbol>>, key: String): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        if (let Some(values) <- map.get(key)) {
            AddAllUnique(out, values)
        }
        return out
    }

    private func ValuesFromStringIndex(map: HashMap<String, ArrayList<Symbol>>): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        for ((_, values) in map) {
            AddAllUnique(out, values)
        }
        return out
    }

    private func FilterByMatcher(ctx: ASTContext, query: Query): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        for (symbol in ctx.symbolTable) {
            if (!symbol.invertedIndexBeenDeleted && query.Match(symbol)) {
                AddUnique(out, symbol)
            }
        }
        return out
    }

    private func AllLiveSymbols(ctx: ASTContext): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        for (symbol in ctx.symbolTable) {
            if (!symbol.invertedIndexBeenDeleted) {
                AddUnique(out, symbol)
            }
        }
        return out
    }

    private func Intersection(left: ArrayList<Symbol>, right: ArrayList<Symbol>): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        for (item in left) {
            if (ContainsSymbol(right, item)) {
                AddUnique(out, item)
            }
        }
        return out
    }

    private func Difference(left: ArrayList<Symbol>, right: ArrayList<Symbol>): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        for (item in left) {
            if (!ContainsSymbol(right, item)) {
                AddUnique(out, item)
            }
        }
        return out
    }

    private func AddAllUnique(out: ArrayList<Symbol>, values: ArrayList<Symbol>): Unit {
        for (value in values) {
            AddUnique(out, value)
        }
    }

    private func AddUnique(out: ArrayList<Symbol>, symbol: Symbol): Unit {
        if (symbol.invertedIndexBeenDeleted) {
            return
        }
        if (!ContainsSymbol(out, symbol)) {
            out.add(symbol)
        }
    }

    private func ContainsSymbol(values: ArrayList<Symbol>, symbol: Symbol): Bool {
        for (value in values) {
            if (SameSymbol(value, symbol)) {
                return true
            }
        }
        return false
    }

    private func AddUniqueString(out: ArrayList<String>, value: String): Unit {
        for (item in out) {
            if (item == value) {
                return
            }
        }
        out.add(value)
    }

    private func insertByPosition(out: ArrayList<Symbol>, symbol: Symbol): Unit {
        var idx: Int64 = 0
        while (idx < out.size) {
            if (Sort.PosDesc(symbol, out[idx])) {
                out.add(symbol, at: idx)
                return
            }
            idx++
        }
        out.add(symbol)
    }
}
