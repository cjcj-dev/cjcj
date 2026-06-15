package cangjie_compiler::parse

import std.collection.*

public open class Expr <: Node {
    public var semiPos: Position = INVALID_POSITION
    public var hasSemi: Bool = false
    public init() { super(ASTKind.EXPR) }
    public init(kind: ASTKind) { super(kind) }
}

public class InvalidExpr <: Expr {
    public init(pos: Position) {
        super(ASTKind.INVALID_EXPR)
        begin = pos
        end = pos
        isBroken = true
    }
}

public class WildcardExpr <: Expr {
    public init(pos: Position) {
        super(ASTKind.WILDCARD_EXPR)
        begin = pos
        end = pos + 1
    }
}

public enum LitConstKind {
    | INTEGER | FLOAT | RUNE | RUNE_BYTE | STRING | JSTRING | MULTILINE_STRING | MULTILINE_RAW_STRING
    | BOOL | UNIT
}

private func LitConstKindIndex(kind: LitConstKind): Int64 {
    return match (kind) {
        case LitConstKind.INTEGER => 0
        case LitConstKind.FLOAT => 1
        case LitConstKind.RUNE => 2
        case LitConstKind.RUNE_BYTE => 3
        case LitConstKind.STRING => 4
        case LitConstKind.JSTRING => 5
        case LitConstKind.MULTILINE_STRING => 6
        case LitConstKind.MULTILINE_RAW_STRING => 7
        case LitConstKind.BOOL => 8
        case LitConstKind.UNIT => 9
    }
}

extend LitConstKind <: Equatable<LitConstKind> {
    public operator func ==(right: LitConstKind): Bool { return LitConstKindIndex(this) == LitConstKindIndex(right) }
    public operator func !=(right: LitConstKind): Bool { return !(this == right) }
}

public class LitConstExpr <: Expr {
    public var kind: LitConstKind = LitConstKind.INTEGER
    public var stringValue: String = ""
    public var tokenKind: TokenKind = TokenKind.ILLEGAL

    public init(kind: LitConstKind, token: Token) {
        super(ASTKind.LIT_CONST_EXPR)
        this.kind = kind
        stringValue = token.Value()
        tokenKind = token.kind
        begin = token.Begin()
        end = token.End()
    }

    public override func ToString(): String { return stringValue }
}

public class RefExpr <: Expr {
    public var identifier: SrcIdentifier = SrcIdentifier()
    public let typeArguments: ArrayList<Type> = ArrayList<Type>()

    public init(identifier: SrcIdentifier) {
        super(ASTKind.REF_EXPR)
        this.identifier = identifier
        begin = identifier.Begin()
        end = identifier.End()
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (ty in typeArguments) { out.add(ty) }
        return out
    }

    public override func ToString(): String { return identifier.GetRawText() }
}

public class ParenExpr <: Expr {
    public var expr: Option<Expr> = None
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() { super(ASTKind.PAREN_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }
}

public class TupleLit <: Expr {
    public let children: ArrayList<Expr> = ArrayList<Expr>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() { super(ASTKind.TUPLE_LIT) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (child in children) { out.add(child) }
        return out
    }
}

public class ArrayLit <: Expr {
    public let children: ArrayList<Expr> = ArrayList<Expr>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var leftSquarePos: Position = INVALID_POSITION
    public var rightSquarePos: Position = INVALID_POSITION

    public init() { super(ASTKind.ARRAY_LIT) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (child in children) { out.add(child) }
        return out
    }
}

public class FuncArg <: Node {
    public var name: SrcIdentifier = SrcIdentifier()
    public var colonPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None

    public init() { super(ASTKind.FUNC_ARG) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }
}

public class CallExpr <: Expr {
    public var baseFunc: Option<Expr> = None
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION

    public init() { super(ASTKind.CALL_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- baseFunc) { out.add(base) }
        for (arg in args) { out.add(arg) }
        return out
    }
}

public class MemberAccess <: Expr {
    public var baseExpr: Option<Expr> = None
    public var dotPos: Position = INVALID_POSITION
    public var field: SrcIdentifier = SrcIdentifier()
    public let typeArguments: ArrayList<Type> = ArrayList<Type>()

    public init() { super(ASTKind.MEMBER_ACCESS) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- baseExpr) { out.add(base) }
        for (ty in typeArguments) { out.add(ty) }
        return out
    }
}

public class SubscriptExpr <: Expr {
    public var baseExpr: Option<Expr> = None
    public let indexExprs: ArrayList<Expr> = ArrayList<Expr>()
    public var leftSquarePos: Position = INVALID_POSITION
    public var rightSquarePos: Position = INVALID_POSITION

    public init() { super(ASTKind.SUBSCRIPT_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- baseExpr) { out.add(base) }
        for (expr in indexExprs) { out.add(expr) }
        return out
    }
}

public class UnaryExpr <: Expr {
    public var op: Token = Token(TokenKind.ILLEGAL)
    public var expr: Option<Expr> = None

    public init(op: Token) {
        super(ASTKind.UNARY_EXPR)
        this.op = op
        begin = op.Begin()
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }
}

public open class BinaryExpr <: Expr {
    public var leftExpr: Option<Expr> = None
    public var rightExpr: Option<Expr> = None
    public var op: Token = Token(TokenKind.ILLEGAL)

    public init(kind: ASTKind, op: Token) {
        super(kind)
        this.op = op
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(left) <- leftExpr) { out.add(left) }
        if (let Some(right) <- rightExpr) { out.add(right) }
        return out
    }
}

public class AssignExpr <: BinaryExpr {
    public init(op: Token) { super(ASTKind.ASSIGN_EXPR, op) }
}

public class RangeExpr <: BinaryExpr {
    public init(op: Token) { super(ASTKind.RANGE_EXPR, op) }
}

public class IsExpr <: BinaryExpr {
    public var typeNode: Option<Type> = None
    public init(op: Token) { super(ASTKind.IS_EXPR, op) }
}

public class AsExpr <: BinaryExpr {
    public var typeNode: Option<Type> = None
    public init(op: Token) { super(ASTKind.AS_EXPR, op) }
}

public class Block <: Expr {
    public let body: ArrayList<Node> = ArrayList<Node>()
    public var leftCurlPos: Position = INVALID_POSITION
    public var rightCurlPos: Position = INVALID_POSITION
    public var unsafePos: Position = INVALID_POSITION

    public init() { super(ASTKind.BLOCK) }

    public override func Children(): ArrayList<Node> {
        return body
    }
}

public class IfExpr <: Expr {
    public var ifPos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var condExpr: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public var thenBody: Option<Block> = None
    public var elsePos: Position = INVALID_POSITION
    public var elseBody: Option<Expr> = None
    public var hasElse: Bool = false

    public init() { super(ASTKind.IF_EXPR) }
}

public class MatchCase <: Node {
    public let patterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public var wherePos: Position = INVALID_POSITION
    public var patternGuard: Option<Expr> = None
    public var arrowPos: Position = INVALID_POSITION
    public var exprOrDecls: Option<Block> = None

    public init() { super(ASTKind.MATCH_CASE) }
}

public class MatchExpr <: Expr {
    public var selector: Option<Expr> = None
    public let matchCases: ArrayList<MatchCase> = ArrayList<MatchCase>()
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public var leftCurlPos: Position = INVALID_POSITION
    public var rightCurlPos: Position = INVALID_POSITION

    public init() { super(ASTKind.MATCH_EXPR) }
}

public class TryExpr <: Expr {
    public var tryPos: Position = INVALID_POSITION
    public var tryBlock: Option<Block> = None
    public let catchPatterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public let catchBlocks: ArrayList<Block> = ArrayList<Block>()
    public var finallyBlock: Option<Block> = None
    public init() { super(ASTKind.TRY_EXPR) }
}

public class WhileExpr <: Expr {
    public var whilePos: Position = INVALID_POSITION
    public var condExpr: Option<Expr> = None
    public var body: Option<Block> = None
    public init() { super(ASTKind.WHILE_EXPR) }
}

public class DoWhileExpr <: Expr {
    public var doPos: Position = INVALID_POSITION
    public var body: Option<Block> = None
    public var whilePos: Position = INVALID_POSITION
    public var condExpr: Option<Expr> = None
    public init() { super(ASTKind.DO_WHILE_EXPR) }
}

public class ForInExpr <: Expr {
    public var forPos: Position = INVALID_POSITION
    public var pattern: Option<Pattern> = None
    public var inPos: Position = INVALID_POSITION
    public var inExpr: Option<Expr> = None
    public var body: Option<Block> = None
    public init() { super(ASTKind.FOR_IN_EXPR) }
}

public class LambdaExpr <: Expr {
    public var funcBody: Option<FuncBody> = None
    public init() { super(ASTKind.LAMBDA_EXPR) }
}

public class ReturnExpr <: Expr {
    public var returnPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.RETURN_EXPR) }
}

public class JumpExpr <: Expr {
    public var token: Token = Token(TokenKind.ILLEGAL)
    public init(token: Token) {
        super(ASTKind.JUMP_EXPR)
        this.token = token
        begin = token.Begin()
        end = token.End()
    }
}

public open class ThrowExpr <: Expr {
    public var throwPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.THROW_EXPR) }
}

public class PerformExpr <: ThrowExpr {
    public init() {
        super()
    }
}

public class ResumeExpr <: Expr {
    public var resumePos: Position = INVALID_POSITION
    public var withExpr: Option<Expr> = None
    public var throwingExpr: Option<Expr> = None
    public init() { super(ASTKind.RESUME_EXPR) }
}

public class SpawnExpr <: Expr {
    public var task: Option<Expr> = None
    public init() { super(ASTKind.SPAWN_EXPR) }
}

public class SynchronizedExpr <: Expr {
    public var mutex: Option<Expr> = None
    public var body: Option<Block> = None
    public init() { super(ASTKind.SYNCHRONIZED_EXPR) }
}

public class QuoteExpr <: Expr {
    public let tokens: ArrayList<Token> = ArrayList<Token>()
    public init() { super(ASTKind.QUOTE_EXPR) }
}

public class MacroExpandExpr <: Expr {
    public var invocation: MacroInvocation = MacroInvocation()
    public init() { super(ASTKind.MACRO_EXPAND_EXPR) }
}

public class IfAvailableExpr <: Expr {
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public init() { super(ASTKind.IF_AVAILABLE_EXPR) }
}

public class TrailingClosureExpr <: Expr {
    public var expr: Option<Expr> = None
    public var lambda: Option<LambdaExpr> = None
    public init() { super(ASTKind.TRAIL_CLOSURE_EXPR) }
}
