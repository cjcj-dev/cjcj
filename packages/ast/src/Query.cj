package cangjie_compiler::ast

import std.collection.*

public enum QueryKind {
    | ALWAYS
    | NAME
    | SCOPE
    | AST_KIND
    | AND
    | OR
    | NOT
}

private func QueryKindIndex(kind: QueryKind): Int64 {
    return match (kind) {
        case QueryKind.ALWAYS => 0
        case QueryKind.NAME => 1
        case QueryKind.SCOPE => 2
        case QueryKind.AST_KIND => 3
        case QueryKind.AND => 4
        case QueryKind.OR => 5
        case QueryKind.NOT => 6
    }
}

extend QueryKind <: Equatable<QueryKind> {
    public operator func ==(right: QueryKind): Bool {
        return QueryKindIndex(this) == QueryKindIndex(right)
    }

    public operator func !=(right: QueryKind): Bool {
        return !(this == right)
    }
}

public open class Query {
    public let kind: QueryKind
    public init(kind: QueryKind) {
        this.kind = kind
    }

    public open func Match(symbol: Symbol): Bool {
        return symbol.name == symbol.name
    }
}

public class NameQuery <: Query {
    public var value: String = ""
    public init(value: String) {
        super(QueryKind.NAME)
        this.value = value
    }

    public override func Match(symbol: Symbol): Bool {
        return symbol.name == value
    }
}

public class ScopeQuery <: Query {
    public var value: String = ""
    public init(value: String) {
        super(QueryKind.SCOPE)
        this.value = value
    }

    public override func Match(symbol: Symbol): Bool {
        return symbol.scopeName == value
    }
}

public class ASTKindQuery <: Query {
    public var value: ASTKind = ASTKind.NODE
    public init(value: ASTKind) {
        super(QueryKind.AST_KIND)
        this.value = value
    }

    public override func Match(symbol: Symbol): Bool {
        if (let Some(node) <- symbol.node) {
            return node.astKind == value
        }
        return false
    }
}

public class CompoundQuery <: Query {
    public let children: ArrayList<Query> = ArrayList<Query>()

    public init(kind: QueryKind) {
        super(kind)
    }

    public override func Match(symbol: Symbol): Bool {
        if (kind == QueryKind.AND) {
            for (child in children) {
                if (!child.Match(symbol)) {
                    return false
                }
            }
            return true
        }
        if (kind == QueryKind.OR) {
            for (child in children) {
                if (child.Match(symbol)) {
                    return true
                }
            }
            return false
        }
        if (kind == QueryKind.NOT && !children.isEmpty()) {
            return !children[0].Match(symbol)
        }
        return true
    }
}

public func ParseQuery(input: String): Query {
    // TODO(selfhost:AST): replace this name-only parser with the C++ Lucene-like query parser.
    if (input.isEmpty()) {
        return Query(QueryKind.ALWAYS)
    }
    return NameQuery(input)
}
