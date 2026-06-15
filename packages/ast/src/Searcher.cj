package cangjie_compiler::ast

import std.collection.*

public class TrieNode {
    public var value: String = ""
    public var prefix: String = ""
    public var depth: UInt32 = 0u32
    public let next: HashMap<String, TrieNode> = HashMap<String, TrieNode>()
    public let suffixes: HashSet<String> = HashSet<String>()
    public init() {}
}

public class Trie {
    public var root: TrieNode = TrieNode()

    public init() {}

    public func Insert(value: String): Unit {
        var node = root
        var prefix = ""
        for (byte in value.toArray()) {
            let key = String.fromUtf8([byte])
            prefix += key
            if (!node.next.contains(key)) {
                let child = TrieNode()
                child.prefix = prefix
                child.depth = node.depth + 1u32
                node.next[key] = child
            }
            if (let Some(child) <- node.next.get(key)) {
                node = child
            }
        }
        node.value = value
        var idx: Int64 = 0
        while (idx < value.size) {
            node.suffixes.add(value[idx..])
            idx++
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

    private func collect(node: TrieNode, out: ArrayList<String>): Unit {
        if (!node.value.isEmpty()) {
            out.add(node.value)
        }
        for ((_, child) in node.next) {
            collect(child, out)
        }
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
        // TODO(selfhost:AST): port the full QueryParser grammar and boolean query evaluation from C++ Query.cpp.
        if (let Some(values) <- cache.get(query)) {
            return values
        }
        let out = ArrayList<Symbol>()
        for (symbol in ctx.symbolTable) {
            if (query.isEmpty() || symbol.name.contains(query) || symbol.scopeName.contains(query)) {
                out.add(symbol)
            }
        }
        cache[query] = out
        return out
    }

    public func Search(ctx: ASTContext, query: Query): ArrayList<Symbol> {
        let out = ArrayList<Symbol>()
        for (symbol in ctx.symbolTable) {
            if (query.Match(symbol)) {
                out.add(symbol)
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
                out.add(symbol.scopeName)
            }
        }
        return out
    }
}
