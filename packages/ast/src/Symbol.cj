package cangjie_compiler::ast

import std.collection.*

public class Symbol {
    public var name: String = ""
    public var node: Option<Node> = None
    public var scopeName: String = ""
    public var invertedIndexBeenDeleted: Bool = false
    public let children: ArrayList<Symbol> = ArrayList<Symbol>()

    public init() {}

    public init(name: String, node!: Option<Node> = None) {
        this.name = name
        this.node = node
    }
}

public class SymbolApi {
    public init() {}

    public static func GetName(symbol: Option<Symbol>): String {
        if (let Some(value) <- symbol) {
            return value.name
        }
        return ""
    }
}
