package cangjie_compiler::parse

import std.collection.*

public open class Pattern <: Node {
    public var ctxExpr: Option<Expr> = None
    public init() { super(ASTKind.PATTERN) }
    public init(kind: ASTKind) { super(kind) }
}

public class InvalidPattern <: Pattern {
    public init(pos: Position) {
        super(ASTKind.INVALID_PATTERN)
        begin = pos
        end = pos
        isBroken = true
    }
}

public class WildcardPattern <: Pattern {
    public init(pos: Position) {
        super(ASTKind.WILDCARD_PATTERN)
        begin = pos
        end = pos + 1
    }
}

public class VarPattern <: Pattern {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public var isVar: Bool = false

    public init(identifier: SrcIdentifier, isVar: Bool) {
        super(ASTKind.VAR_PATTERN)
        this.identifier = identifier
        this.isVar = isVar
        begin = identifier.Begin()
        end = identifier.End()
    }
}

public class ConstPattern <: Pattern {
    public var literal: Option<Expr> = None

    public init() { super(ASTKind.CONST_PATTERN) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(expr) <- literal) { out.add(expr) }
        return out
    }
}

public class TuplePattern <: Pattern {
    public let patterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() { super(ASTKind.TUPLE_PATTERN) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (pattern in patterns) { out.add(pattern) }
        return out
    }
}

public class EnumPattern <: Pattern {
    public var constructor: SrcIdentifier = SrcIdentifier()
    public let patterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() { super(ASTKind.ENUM_PATTERN) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (pattern in patterns) { out.add(pattern) }
        return out
    }
}

public class VarOrEnumPattern <: Pattern {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public init(identifier: SrcIdentifier) {
        super(ASTKind.VAR_OR_ENUM_PATTERN)
        this.identifier = identifier
        begin = identifier.Begin()
        end = identifier.End()
    }
}

public class TypePattern <: Pattern {
    public var pattern: Option<Pattern> = None
    public var colonPos: Position = INVALID_POSITION
    public var typeNode: Option<Type> = None

    public init() { super(ASTKind.TYPE_PATTERN) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(pat) <- pattern) { out.add(pat) }
        if (let Some(ty) <- typeNode) { out.add(ty) }
        return out
    }
}

public open class TypeListPattern <: Pattern {
    public var pattern: Option<Pattern> = None
    public var patternPos: Position = INVALID_POSITION
    public var colonPos: Position = INVALID_POSITION
    public let types: ArrayList<Type> = ArrayList<Type>()
    public let bitOrPosVector: ArrayList<Position> = ArrayList<Position>()

    public init(kind: ASTKind) { super(kind) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(pat) <- pattern) { out.add(pat) }
        for (ty in types) { out.add(ty) }
        return out
    }
}

public class ExceptTypePattern <: TypeListPattern {
    public init() { super(ASTKind.EXCEPT_TYPE_PATTERN) }
}

public class CommandTypePattern <: TypeListPattern {
    public init() { super(ASTKind.COMMAND_TYPE_PATTERN) }
}
