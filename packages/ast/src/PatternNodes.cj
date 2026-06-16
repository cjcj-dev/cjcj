package cangjie_compiler::ast

import std.collection.*

private func joinPatternStrings(values: ArrayList<Pattern>, delimiter: String): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, delimiter)
}

private func joinPatternTypeStrings(values: ArrayList<Type>, delimiter: String): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, delimiter)
}

public open class Pattern <: Node {
    public var ctxExpr: Option<Expr> = None

    public init(kind: ASTKind) {
        super(kind)
    }
}

public class InvalidPattern <: Pattern {
    public init() {
        super(ASTKind.INVALID_PATTERN)
        EnableAttr(Attribute.IS_BROKEN)
    }

    public init(pos: Position) {
        super(ASTKind.INVALID_PATTERN)
        EnableAttr(Attribute.IS_BROKEN)
        begin = pos
        end = pos
    }

    public override func ToString(): String {
        return "<invalid>"
    }
}

public class ConstPattern <: Pattern {
    public var literal: Option<Expr> = None
    public var operatorCallExpr: Option<CallExpr> = None

    public init() {
        super(ASTKind.CONST_PATTERN)
    }

    public override func ToString(): String {
        if (let Some(value) <- literal) {
            return value.ToString()
        }
        return ""
    }
}

public class WildcardPattern <: Pattern {
    public init() {
        super(ASTKind.WILDCARD_PATTERN)
    }

    public init(begin: Position) {
        super(ASTKind.WILDCARD_PATTERN)
        this.begin = begin
        end = begin + Len(TokenKind.WILDCARD)
    }

    public override func ToString(): String {
        return "_"
    }
}

public class VarPattern <: Pattern {
    public var varDecl: Option<VarDecl> = None
    public var desugarExpr: Option<Expr> = None

    public init() {
        super(ASTKind.VAR_PATTERN)
    }

    public init(ident: SrcIdentifier, nodePos!: Position = INVALID_POSITION) {
        super(ASTKind.VAR_PATTERN)
        let decl = VarDecl()
        decl.begin = nodePos
        decl.identifier = ident
        decl.end = ident.End()
        decl.isVar = false
        decl.parentPattern = this
        varDecl = decl
        begin = nodePos
        end = decl.end
    }

    public override func ToString(): String {
        if (let Some(decl) <- varDecl) {
            return decl.identifier.Val()
        }
        return ""
    }
}

public class TuplePattern <: Pattern {
    public var leftBracePos: Position = INVALID_POSITION
    public let patterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var rightBracePos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.TUPLE_PATTERN)
    }

    public override func ToString(): String {
        return "(" + joinPatternStrings(patterns, ", ") + ")"
    }
}

public class TypePattern <: Pattern {
    public var pattern: Option<Pattern> = None
    public var colonPos: Position = INVALID_POSITION
    public var typeNode: Option<Type> = None
    public var desugarExpr: Option<Expr> = None
    public var desugarVarPattern: Option<VarPattern> = None
    public var needRuntimeTypeCheck: Bool = true
    public var matchBeforeRuntime: Bool = true

    public init() {
        super(ASTKind.TYPE_PATTERN)
    }

    public override func ToString(): String {
        var out = if (let Some(value) <- pattern) { value.ToString() } else { "" }
        if (let Some(value) <- typeNode) {
            if (!out.isEmpty()) {
                out += ": "
            }
            out += value.ToString()
        }
        return out
    }
}

public class EnumPattern <: Pattern {
    public var constructor: Option<Expr> = None
    public let patterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public var leftParenPos: Position = INVALID_POSITION
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var rightParenPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.ENUM_PATTERN)
    }

    public func GetIdentifier(): String {
        if (let Some(expr) <- constructor) {
            if (let Some(refExpr) <- (expr as RefExpr)) {
                return refExpr.ref.identifier.Val()
            }
            if (let Some(member) <- (expr as MemberAccess)) {
                return member.field.Val()
            }
        }
        return ""
    }

    public override func ToString(): String {
        var out = if (let Some(value) <- constructor) { value.ToString() } else { "" }
        if (!patterns.isEmpty()) {
            out += "(" + joinPatternStrings(patterns, ", ") + ")"
        }
        return out
    }
}

public class VarOrEnumPattern <: Pattern {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public var pattern: Option<Pattern> = None

    public init(id: SrcIdentifier) {
        super(ASTKind.VAR_OR_ENUM_PATTERN)
        identifier = id
    }

    public override func ToString(): String {
        if (let Some(value) <- pattern) {
            return value.ToString()
        }
        return identifier.Val()
    }
}

public class ExceptTypePattern <: Pattern {
    public var pattern: Option<Pattern> = None
    public var patternPos: Position = INVALID_POSITION
    public var colonPos: Position = INVALID_POSITION
    public let types: ArrayList<Type> = ArrayList<Type>()
    public let bitOrPosVector: ArrayList<Position> = ArrayList<Position>()

    public init() {
        super(ASTKind.EXCEPT_TYPE_PATTERN)
    }

    public override func ToString(): String {
        var out = if (let Some(value) <- pattern) { value.ToString() } else { "" }
        if (!types.isEmpty()) {
            if (!out.isEmpty()) {
                out += ": "
            }
            out += joinPatternTypeStrings(types, " | ")
        }
        return out
    }
}

public class CommandTypePattern <: Pattern {
    public var pattern: Option<Pattern> = None
    public var patternPos: Position = INVALID_POSITION
    public var colonPos: Position = INVALID_POSITION
    public let types: ArrayList<Type> = ArrayList<Type>()
    public let bitOrPosVector: ArrayList<Position> = ArrayList<Position>()

    public init() {
        super(ASTKind.COMMAND_TYPE_PATTERN)
    }

    public override func ToString(): String {
        var out = if (let Some(value) <- pattern) { value.ToString() } else { "" }
        if (!types.isEmpty()) {
            if (!out.isEmpty()) {
                out += ": "
            }
            out += joinPatternTypeStrings(types, " | ")
        }
        return out
    }
}
