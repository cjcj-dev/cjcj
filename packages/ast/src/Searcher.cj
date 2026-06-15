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
                return leftNode.begin < rightNode.begin
            }
        }
        return left.name < right.name
    }

    public static func PosDesc(left: Symbol, right: Symbol): Bool {
        return !Sort.PosAsc(left, right)
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
        let out = ArrayList<Symbol>()
        for (symbol in ctx.symbolTable) {
            if (query.Match(symbol)) {
                insertByPosition(out, symbol)
            }
        }
        return out
    }

    public func InvalidateCache(): Unit {
        cache.clear()
    }

    public func InvalidateCacheBut(query: String): Unit {
        let keep = cache.get(query)
        cache.clear()
        if (let Some(values) <- keep) {
            cache[query] = values
        }
    }

    public func GetScopeNamesByPrefix(ctx: ASTContext, prefix: String): ArrayList<String> {
        let out = ArrayList<String>()
        for (symbol in ctx.symbolTable) {
            if (symbol.scopeName.startsWith(prefix)) {
                addUniqueString(out, symbol.scopeName)
            }
        }
        return out
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

    private func addUniqueString(out: ArrayList<String>, value: String): Unit {
        for (item in out) {
            if (item == value) {
                return
            }
        }
        out.add(value)
    }
}
