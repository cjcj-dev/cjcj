package cjcj::ast

import cjcj::utils.CJC_ASSERT
import cjcj::utils.CJC_NULLPTR_CHECK
import cjcj::utils.Stoi
import std.collection.*

private func exprJoinExprs(values: ArrayList<Expr>, delimiter: String): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, delimiter)
}

private func exprJoinPatterns(values: ArrayList<Pattern>, delimiter: String): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, delimiter)
}

private func exprJoinVarDecls(values: ArrayList<VarDecl>, delimiter: String): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, delimiter)
}

private func exprJoinFuncArgs(values: ArrayList<FuncArg>, delimiter: String): String {
    let parts = ArrayList<String>()
    for (value in values) {
        parts.add(value.ToString())
    }
    return JoinStrings(parts, delimiter)
}

public open class Expr <: Node {
    public var desugarExpr: Option<Expr> = None
    public var sourceExpr: Option<Expr> = None
    public var mapExpr: Option<Expr> = None
    public var semiPos: Position = INVALID_POSITION
    public var constNumValue: ConstNumValue = ConstNumValue()
    public var overflowStrategy: OverflowStrategy = OverflowStrategy.NA
    public var isConst: Bool = false
    public var isBaseFunc: Bool = false
    public var isInFlowExpr: Bool = false
    public var hasSemi: Bool = false
    public var hasQuestSuffix: Bool = false

    public init() {
        super(ASTKind.EXPR)
    }

    public init(kind: ASTKind) {
        super(kind)
    }

    public open func GetTypeArgs(): ArrayList<Type> {
        return ArrayList<Type>()
    }

    public func IsReferenceExpr(): Bool {
        return astKind == ASTKind.REF_EXPR || astKind == ASTKind.MEMBER_ACCESS
    }
}

public enum FlowStatus {
    | NORMAL
    | OVER
    | UNDER
}

public enum SugarKind {
    | QUEST
    | IF_LET
    | WHILE_LET
    | FOR_IN_EXPR
    | IS
    | AS
    | TOKEN_CALL
    | NO_SUGAR
}

public class FloatLiteralValue {
    public var value: Float64 = 0.0
    public var flowStatus: FlowStatus = FlowStatus.NORMAL
    public init() {}
}

public class ConstNumValue {
    public var asInt: IntLiteral = IntLiteral()
    public var asFloat: FloatLiteralValue = FloatLiteralValue()
    public var asBoolean: Bool = true
    public init() {}
}

public class WildcardExpr <: Expr {
    public init() {
        super(ASTKind.WILDCARD_EXPR)
    }

    public init(begin: Position) {
        super(ASTKind.WILDCARD_EXPR)
        this.begin = begin
        end = begin + Len(TokenKind.WILDCARD)
    }
}

public class Block <: Expr {
    public var leftCurlPos: Position = INVALID_POSITION
    public let body: ArrayList<Node> = ArrayList<Node>()
    public var rightCurlPos: Position = INVALID_POSITION
    public var unsafePos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.BLOCK)
    }

    public override func Children(): ArrayList<Node> {
        return body
    }

    public func GetLastExprOrDecl(): Option<Node> {
        if (body.isEmpty()) {
            return None
        }
        return body[body.size - 1]
    }

    public override func ToString(): String {
        var out = "{"
        for (node in body) {
            out += "\n" + node.ToString()
        }
        if (!body.isEmpty()) {
            out += "\n"
        }
        out += "}"
        return out
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
    public var isElseIf: Bool = false
    public var hasElse: Bool = false
    public var sugarKind: SugarKind = SugarKind.NO_SUGAR

    public init() {
        super(ASTKind.IF_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(cond) <- condExpr) { out.add(cond) }
        if (let Some(thenBlock) <- thenBody) { out.add(thenBlock) }
        if (let Some(elseExpr) <- elseBody) { out.add(elseExpr) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(condExpr)
        var out = "if (" + condExpr.getOrThrow().ToString() + ") "
        CJC_NULLPTR_CHECK(thenBody)
        out += thenBody.getOrThrow().ToString()
        if (let Some(value) <- elseBody) {
            out += " else " + value.ToString()
        }
        return out
    }
}

public class LetPatternDestructor <: Expr {
    public let patterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public let orPos: ArrayList<Position> = ArrayList<Position>()
    public var backarrowPos: Position = INVALID_POSITION
    public var initializer: Option<Expr> = None

    public init() {
        super(ASTKind.LET_PATTERN_DESTRUCTOR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (pattern in patterns) { out.add(pattern) }
        if (let Some(expr) <- initializer) { out.add(expr) }
        return out
    }

    public override func ToString(): String {
        var out = "let "
        out += exprJoinPatterns(patterns, " | ")
        out += " <- "
        CJC_NULLPTR_CHECK(initializer)
        out += initializer.getOrThrow().ToString()
        return out
    }
}

public class TokenPart <: Expr {
    public let tokens: ArrayList<Token> = ArrayList<Token>()

    public init() {
        super(ASTKind.TOKEN_PART)
    }

    public init(tokens: Array<Token>) {
        super(ASTKind.TOKEN_PART)
        for (token in tokens) {
            this.tokens.add(token)
        }
        if (!this.tokens.isEmpty()) {
            begin = this.tokens[0].Begin()
            end = this.tokens[this.tokens.size - 1].End()
        }
    }

    public init(inputTokens: ArrayList<Token>) {
        super(ASTKind.TOKEN_PART)
        for (token in inputTokens) {
            tokens.add(token)
        }
        if (!tokens.isEmpty()) {
            begin = tokens[0].Begin()
            end = tokens[tokens.size - 1].End()
        }
    }

    public override func ToString(): String {
        var out = ""
        for (token in tokens) {
            out += token.Value()
        }
        return out
    }
}

public class QuoteExpr <: Expr {
    public var quotePos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public let exprs: ArrayList<Expr> = ArrayList<Expr>()

    public init() {
        super(ASTKind.QUOTE_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (expr in exprs) { out.add(expr) }
        return out
    }

    public override func ToString(): String {
        return "quote(" + exprJoinExprs(exprs, ", ") + ")"
    }
}

public class MatchCase <: Node {
    public let patterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public let bitOrPosVector: ArrayList<Position> = ArrayList<Position>()
    public var patternGuard: Option<Expr> = None
    public var wherePos: Position = INVALID_POSITION
    public var arrowPos: Position = INVALID_POSITION
    public var exprOrDecls: Option<Block> = None

    public init() {
        super(ASTKind.MATCH_CASE)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (pattern in patterns) { out.add(pattern) }
        if (let Some(guard) <- patternGuard) { out.add(guard) }
        if (let Some(block) <- exprOrDecls) { out.add(block) }
        return out
    }

    public func SetCtxExprForPatterns(ctxExpr: Expr): Unit {
        for (pattern in patterns) {
            pattern.ctxExpr = ctxExpr
        }
    }

    public override func ToString(): String {
        var out = "case " + exprJoinPatterns(patterns, " | ")
        if (let Some(guardExpr) <- patternGuard) {
            out += " where " + guardExpr.ToString()
        }
        CJC_NULLPTR_CHECK(exprOrDecls)
        out += " => " + exprOrDecls.getOrThrow().ToString()
        return out
    }
}

public class MatchCaseOther <: Node {
    public var matchExpr: Option<Expr> = None
    public var arrowPos: Position = INVALID_POSITION
    public var exprOrDecls: Option<Block> = None

    public init() {
        super(ASTKind.MATCH_CASE_OTHER)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(expr) <- matchExpr) { out.add(expr) }
        if (let Some(block) <- exprOrDecls) { out.add(block) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(matchExpr)
        CJC_NULLPTR_CHECK(exprOrDecls)
        return "case " + matchExpr.getOrThrow().ToString() + " => " + exprOrDecls.getOrThrow().ToString()
    }
}

public class MatchExpr <: Expr {
    public var sugarKind: SugarKind = SugarKind.NO_SUGAR
    public var matchMode: Bool = false
    public var leftParenPos: Position = INVALID_POSITION
    public var selector: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public var leftCurlPos: Position = INVALID_POSITION
    public let matchCases: ArrayList<MatchCase> = ArrayList<MatchCase>()
    public let matchCaseOthers: ArrayList<MatchCaseOther> = ArrayList<MatchCaseOther>()
    public var rightCurlPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.MATCH_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(sel) <- selector) { out.add(sel) }
        for (matchCase in matchCases) { out.add(matchCase) }
        for (matchCaseOther in matchCaseOthers) { out.add(matchCaseOther) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(selector)
        var out = "match (" + selector.getOrThrow().ToString() + ") {"
        for (matchCase in matchCases) {
            out += "\n" + matchCase.ToString()
        }
        for (matchCaseOther in matchCaseOthers) {
            out += "\n" + matchCaseOther.ToString()
        }
        if (!matchCases.isEmpty() || !matchCaseOthers.isEmpty()) {
            out += "\n"
        }
        out += "}"
        return out
    }
}

public class Handler {
    public var pos: Position = INVALID_POSITION
    public var commandPattern: Option<Pattern> = None
    public var block: Option<Block> = None
    public var desugaredLambda: Option<LambdaExpr> = None
    public var commandResultTy: Option<Ty> = None
    public init() {}
}

public class TryExpr <: Expr {
    public var tryPos: Position = INVALID_POSITION
    public var lParen: Position = INVALID_POSITION
    public let resourceSpec: ArrayList<VarDecl> = ArrayList<VarDecl>()
    public let resourceSpecCommaPos: ArrayList<Position> = ArrayList<Position>()
    public var rParen: Position = INVALID_POSITION
    public var tryBlock: Option<Block> = None
    public let catchPosVector: ArrayList<Position> = ArrayList<Position>()
    public let catchLParenPosVector: ArrayList<Position> = ArrayList<Position>()
    public let catchRParenPosVector: ArrayList<Position> = ArrayList<Position>()
    public let catchBlocks: ArrayList<Block> = ArrayList<Block>()
    public let catchPatterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public var finallyPos: Position = INVALID_POSITION
    public var finallyBlock: Option<Block> = None
    public let handlers: ArrayList<Handler> = ArrayList<Handler>()
    public var isIllegalResourceSpec: Bool = false
    public var isDesugaredFromTryWithResources: Bool = false
    public var isDesugaredFromSyncBlock: Bool = false
    public var tryLambda: Option<LambdaExpr> = None
    public var finallyLambda: Option<LambdaExpr> = None

    public init() {
        super(ASTKind.TRY_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (decl in resourceSpec) { out.add(decl) }
        if (let Some(block) <- tryBlock) { out.add(block) }
        for (pattern in catchPatterns) { out.add(pattern) }
        for (block in catchBlocks) { out.add(block) }
        if (let Some(block) <- finallyBlock) { out.add(block) }
        for (handler in handlers) {
            if (let Some(pattern) <- handler.commandPattern) { out.add(pattern) }
            if (let Some(block) <- handler.block) { out.add(block) }
        }
        return out
    }

    public override func ToString(): String {
        var out = "try "
        if (!resourceSpec.isEmpty()) {
            out += "(" + exprJoinVarDecls(resourceSpec, ", ") + ") "
        }
        CJC_NULLPTR_CHECK(tryBlock)
        out += tryBlock.getOrThrow().ToString()
        var catchIdx: Int64 = 0
        while (catchIdx < catchBlocks.size) {
            out += " catch("
            if (catchIdx < catchPatterns.size) {
                out += catchPatterns[catchIdx].ToString()
            }
            out += ") " + catchBlocks[catchIdx].ToString()
            catchIdx++
        }
        for (handler in handlers) {
            out += " handle("
            if (let Some(commandPattern) <- handler.commandPattern) {
                out += commandPattern.ToString()
            }
            out += ") "
            if (let Some(block) <- handler.block) {
                out += block.ToString()
            }
        }
        if (let Some(block) <- finallyBlock) {
            out += " finally " + block.ToString()
        }
        return out
    }
}

public class ThrowExpr <: Expr {
    public var throwPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.THROW_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(expr)
        return "throw " + expr.getOrThrow().ToString()
    }
}

public class PerformExpr <: Expr {
    public var performPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.PERFORM_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(expr)
        return "perform " + expr.getOrThrow().ToString()
    }
}

public class ResumeExpr <: Expr {
    public var resumePos: Position = INVALID_POSITION
    public var withPos: Position = INVALID_POSITION
    public var withExpr: Option<Expr> = None
    public var throwingPos: Position = INVALID_POSITION
    public var throwingExpr: Option<Expr> = None
    public var enclosing: Option<Handler> = None
    public init() { super(ASTKind.RESUME_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(expr) <- withExpr) { out.add(expr) }
        if (let Some(expr) <- throwingExpr) { out.add(expr) }
        return out
    }

    public override func ToString(): String {
        var out = "resume"
        if (let Some(value) <- withExpr) {
            out += " with " + value.ToString()
        }
        if (let Some(value) <- throwingExpr) {
            out += " throwing " + value.ToString()
        }
        return out
    }
}

public class ReturnExpr <: Expr {
    public var returnPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public var refFuncBody: Option<FuncBody> = None
    public init() { super(ASTKind.RETURN_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }

    public override func ToString(): String {
        if (let Some(value) <- expr) {
            return "return " + value.ToString()
        }
        return "return"
    }
}

public class JumpExpr <: Expr {
    public var refLoop: Option<Expr> = None
    public var isBreak: Bool = false
    public init() { super(ASTKind.JUMP_EXPR) }

    public init(token: Token) {
        super(ASTKind.JUMP_EXPR)
        isBreak = token.kind == TokenKind.BREAK
        begin = token.Begin()
        end = token.End()
    }

    public override func ToString(): String {
        return if (isBreak) { "break" } else { "continue" }
    }
}

public class ForInExpr <: Expr {
    public var leftParenPos: Position = INVALID_POSITION
    public var pattern: Option<Pattern> = None
    public var patternInDesugarExpr: Option<Pattern> = None
    public var inPos: Position = INVALID_POSITION
    public var inExpression: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public var wherePos: Position = INVALID_POSITION
    public var patternGuard: Option<Expr> = None
    public var body: Option<Block> = None
    public var forInKind: ForInKind = ForInKind.FORIN_INVALID
    public init() { super(ASTKind.FOR_IN_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(pat) <- pattern) { out.add(pat) }
        if (let Some(expr) <- inExpression) { out.add(expr) }
        if (let Some(guard) <- patternGuard) { out.add(guard) }
        if (let Some(block) <- body) { out.add(block) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(pattern)
        CJC_NULLPTR_CHECK(inExpression)
        var out = "for (" + pattern.getOrThrow().ToString() + " in " + inExpression.getOrThrow().ToString()
        if (let Some(value) <- patternGuard) {
            out += " where " + value.ToString()
        }
        out += ") "
        CJC_NULLPTR_CHECK(body)
        out += body.getOrThrow().ToString()
        return out
    }
}

public class WhileExpr <: Expr {
    public var whilePos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var condExpr: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public var body: Option<Block> = None
    public var sugarKind: SugarKind = SugarKind.NO_SUGAR
    public init() { super(ASTKind.WHILE_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(cond) <- condExpr) { out.add(cond) }
        if (let Some(block) <- body) { out.add(block) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(condExpr)
        CJC_NULLPTR_CHECK(body)
        return "while (" + condExpr.getOrThrow().ToString() + ") " + body.getOrThrow().ToString()
    }
}

public class DoWhileExpr <: Expr {
    public var doPos: Position = INVALID_POSITION
    public var body: Option<Block> = None
    public var whilePos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var condExpr: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public init() { super(ASTKind.DO_WHILE_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(block) <- body) { out.add(block) }
        if (let Some(cond) <- condExpr) { out.add(cond) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(body)
        CJC_NULLPTR_CHECK(condExpr)
        return "do " + body.getOrThrow().ToString() + " while (" + condExpr.getOrThrow().ToString() + ")"
    }
}

public open class OverloadableExpr <: Expr {
    public var op: TokenKind = TokenKind.ILLEGAL
    public init(kind: ASTKind) { super(kind) }
}

public class AssignExpr <: OverloadableExpr {
    public var leftValue: Option<Expr> = None
    public var assignPos: Position = INVALID_POSITION
    public var rightExpr: Option<Expr> = None
    public var isCompound: Bool = false
    public init() { super(ASTKind.ASSIGN_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(left) <- leftValue) { out.add(left) }
        if (let Some(right) <- rightExpr) { out.add(right) }
        return out
    }

    public override func Clear(): Unit {
        RecoverToAssignExpr(this)
        super.Clear()
    }
}

public class IncOrDecExpr <: OverloadableExpr {
    public var operatorPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.INC_OR_DEC_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }
}

public class UnaryExpr <: OverloadableExpr {
    public var expr: Option<Expr> = None
    public var operatorPos: Position = INVALID_POSITION
    public init() { super(ASTKind.UNARY_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }

    public override func Clear(): Unit {
        RecoverToUnaryExpr(this)
        super.Clear()
        if (let Some(value) <- expr) {
            value.Clear()
        }
    }
}

public class BinaryExpr <: OverloadableExpr {
    public var leftExpr: Option<Expr> = None
    public var rightExpr: Option<Expr> = None
    public var operatorPos: Position = INVALID_POSITION
    public init() { super(ASTKind.BINARY_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(left) <- leftExpr) { out.add(left) }
        if (let Some(right) <- rightExpr) { out.add(right) }
        return out
    }

    public override func Clear(): Unit {
        RecoverToBinaryExpr(this)
        super.Clear()
        if (let Some(left) <- leftExpr) {
            left.Clear()
        }
        if (let Some(right) <- rightExpr) {
            right.Clear()
        }
    }
}

public class IsExpr <: Expr {
    public var leftExpr: Option<Expr> = None
    public var isType: Option<Type> = None
    public var isPos: Position = INVALID_POSITION
    public init() { super(ASTKind.IS_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(left) <- leftExpr) { out.add(left) }
        if (let Some(ty) <- isType) { out.add(ty) }
        return out
    }

    public override func ToString(): String {
        CJC_ASSERT(leftExpr.isSome())
        CJC_ASSERT(isType.isSome())
        return leftExpr.getOrThrow().ToString() + " is " + isType.getOrThrow().ToString()
    }
}

public class AsExpr <: Expr {
    public var leftExpr: Option<Expr> = None
    public var asType: Option<Type> = None
    public var asPos: Position = INVALID_POSITION
    public init() { super(ASTKind.AS_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(left) <- leftExpr) { out.add(left) }
        if (let Some(ty) <- asType) { out.add(ty) }
        return out
    }

    public override func ToString(): String {
        CJC_ASSERT(leftExpr.isSome())
        CJC_ASSERT(asType.isSome())
        return leftExpr.getOrThrow().ToString() + " as " + asType.getOrThrow().ToString()
    }
}

public class RangeExpr <: Expr {
    public var startExpr: Option<Expr> = None
    public var rangePos: Position = INVALID_POSITION
    public var stopExpr: Option<Expr> = None
    public var colonPos: Position = INVALID_POSITION
    public var stepExpr: Option<Expr> = None
    public var decl: Option<StructDecl> = None
    public var isClosed: Bool = true
    public init() { super(ASTKind.RANGE_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(start) <- startExpr) { out.add(start) }
        if (let Some(stop) <- stopExpr) { out.add(stop) }
        if (let Some(step) <- stepExpr) { out.add(step) }
        return out
    }
}

public class SubscriptExpr <: OverloadableExpr {
    public var baseExpr: Option<Expr> = None
    public var leftParenPos: Position = INVALID_POSITION
    public let indexExprs: ArrayList<Expr> = ArrayList<Expr>()
    public let commaPos: ArrayList<Position> = ArrayList<Position>()
    public var rightParenPos: Position = INVALID_POSITION
    public var isTupleAccess: Bool = false

    public init() {
        super(ASTKind.SUBSCRIPT_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- baseExpr) { out.add(base) }
        for (expr in indexExprs) { out.add(expr) }
        return out
    }

    public func IsVArrayAccess(): Bool {
        if (let Some(base) <- baseExpr) {
            return base.TyKind() == TypeKind.TYPE_VARRAY
        }
        return false
    }

    public override func Clear(): Unit {
        RecoverToSubscriptExpr(this)
        if (let Some(base) <- baseExpr) {
            base.Clear()
        }
        for (indexExpr in indexExprs) {
            indexExpr.Clear()
        }
        commaPos.clear()
        super.Clear()
    }
}

public class InterpolationExpr <: Expr {
    public var rawString: String = ""
    public var dollarPos: Position = INVALID_POSITION
    public var block: Option<Block> = None
    public init() { super(ASTKind.INTERPOLATION_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(value) <- block) { out.add(value) }
        return out
    }

    public override func ToString(): String {
        return rawString
    }
}

public class StrInterpolationExpr <: Expr {
    public var rawString: String = ""
    public let strParts: ArrayList<StringPart> = ArrayList<StringPart>()
    public let strPartExprs: ArrayList<Expr> = ArrayList<Expr>()
    public init() { super(ASTKind.STR_INTERPOLATION_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (expr in strPartExprs) { out.add(expr) }
        return out
    }

    public override func ToString(): String {
        return rawString
    }
}

public enum LitConstKind {
    | INTEGER
    | RUNE_BYTE
    | FLOAT
    | RUNE
    | STRING
    | JSTRING
    | BOOL
    | UNIT
    | NONE
}

public func LitConstKindIndex(kind: LitConstKind): Int64 {
    return match (kind) {
        case LitConstKind.INTEGER => 0
        case LitConstKind.RUNE_BYTE => 1
        case LitConstKind.FLOAT => 2
        case LitConstKind.RUNE => 3
        case LitConstKind.STRING => 4
        case LitConstKind.JSTRING => 5
        case LitConstKind.BOOL => 6
        case LitConstKind.UNIT => 7
        case LitConstKind.NONE => 8
    }
}

extend LitConstKind <: Equatable<LitConstKind> {
    public operator func ==(right: LitConstKind): Bool {
        return LitConstKindIndex(this) == LitConstKindIndex(right)
    }

    public operator func !=(right: LitConstKind): Bool {
        return !(this == right)
    }
}

public class LitConstExpr <: Expr {
    public var ref: Option<RefType> = None
    public var rawString: String = ""
    public var siExpr: Option<StrInterpolationExpr> = None
    public var stringValue: String = ""
    public let codepoint: ArrayList<UInt32> = ArrayList<UInt32>()
    public var kind: LitConstKind = LitConstKind.NONE
    public var stringKind: StringKind = StringKind.NORMAL
    public var isSingleQuote: Bool = false
    public var delimiterNum: UInt64 = 1

    public init() {
        super(ASTKind.LIT_CONST_EXPR)
    }

    public init(kind: LitConstKind, str: String) {
        super(ASTKind.LIT_CONST_EXPR)
        this.kind = kind
        stringValue = str
    }

    public init(kind: LitConstKind, token: Token) {
        super(ASTKind.LIT_CONST_EXPR)
        this.kind = kind
        stringValue = token.Value()
        rawString = token.Value()
        begin = token.Begin()
        end = token.End()
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(expr) <- siExpr) { out.add(expr) }
        return out
    }

    public func LitKindToString(): String {
        return match (kind) {
            case LitConstKind.INTEGER => "Integer"
            case LitConstKind.RUNE_BYTE => "RuneByte"
            case LitConstKind.FLOAT => "Float"
            case LitConstKind.RUNE => "Rune"
            case LitConstKind.STRING => "String"
            case LitConstKind.JSTRING => "JString"
            case LitConstKind.BOOL => "Bool"
            case LitConstKind.UNIT => "Unit"
            case LitConstKind.NONE => "None"
        }
    }

    public override func ToString(): String {
        return if (kind == LitConstKind.STRING) { "\"" + stringValue + "\"" } else { stringValue }
    }

    public func GetNumLitTypeKind(): TypeKind {
        var suffixWidth: Int64 = 0
        if (kind == LitConstKind.RUNE_BYTE) {
            return TypeKind.TYPE_UINT8
        }
        if (kind == LitConstKind.INTEGER) {
            var suffixStart = stringValue.size
            var idx: Int64 = 0
            while (idx < stringValue.size) {
                let c = stringValue[idx]
                if (c == b'i' || c == b'u') {
                    suffixStart = idx
                    break
                }
                idx++
            }
            let suffix = stringValue[suffixStart..]
            if (suffix.isEmpty()) {
                return TypeKind.TYPE_IDEAL_INT
            } else {
                if (let Some(suffixWid) <- Stoi(suffix[1..])) {
                    suffixWidth = suffixWid
                } else {
                    return TypeKind.TYPE_INVALID
                }
                var suffixWidthValue = suffixWidth
                var powerBase2: Int64 = 0
                while (suffixWidthValue != 0 && suffixWidthValue % 2 == 0) {
                    powerBase2++
                    suffixWidthValue /= 2
                }
                let signedness = suffix[0]
                if (signedness == b'i' || signedness == b'u') {
                    let leastPowerBase2: Int64 = 3
                    let tk = if (signedness == b'i') { TypeKind.TYPE_INT8 } else { TypeKind.TYPE_UINT8 }
                    let typeKindIndex = powerBase2 - leastPowerBase2 + TypeKindIndex(tk)
                    return match (typeKindIndex) {
                        case 2 => TypeKind.TYPE_INT8
                        case 3 => TypeKind.TYPE_INT16
                        case 4 => TypeKind.TYPE_INT32
                        case 5 => TypeKind.TYPE_INT64
                        case 6 => TypeKind.TYPE_INT_NATIVE
                        case 8 => TypeKind.TYPE_UINT8
                        case 9 => TypeKind.TYPE_UINT16
                        case 10 => TypeKind.TYPE_UINT32
                        case 11 => TypeKind.TYPE_UINT64
                        case 12 => TypeKind.TYPE_UINT_NATIVE
                        case _ => TypeKind.TYPE_INVALID
                    }
                } else {
                    return TypeKind.TYPE_INVALID
                }
            }
        }
        if (kind == LitConstKind.FLOAT) {
            let isNegative = !stringValue.isEmpty() && stringValue[0] == b'-'
            let prefixStart: Int64 = if (isNegative) { 1 } else { 0 }
            let prefixEnd = if (stringValue.size < prefixStart + 2) { stringValue.size } else { prefixStart + 2 }
            let prefix = stringValue[prefixStart..prefixEnd]
            if (prefix == "0x" || prefix == "0X") {
                return TypeKind.TYPE_IDEAL_FLOAT
            }
            var suffixStart = stringValue.size
            var idx: Int64 = 0
            while (idx < stringValue.size) {
                if (stringValue[idx] == b'f') {
                    suffixStart = idx
                    break
                }
                idx++
            }
            let suffix = stringValue[suffixStart..]
            if (suffix.isEmpty()) {
                return TypeKind.TYPE_IDEAL_FLOAT
            } else {
                if (let Some(suffixWid) <- Stoi(suffix[1..])) {
                    suffixWidth = suffixWid
                } else {
                    return TypeKind.TYPE_INVALID
                }
                var suffixWidthValue = suffixWidth
                var powerBase2: Int64 = 0
                while (suffixWidthValue != 0 && suffixWidthValue % 2 == 0) {
                    powerBase2++
                    suffixWidthValue /= 2
                }
                let leastPowerBase2: Int64 = 4
                let typeKindIndex = powerBase2 - leastPowerBase2 + TypeKindIndex(TypeKind.TYPE_FLOAT16)
                return match (typeKindIndex) {
                    case 13 => TypeKind.TYPE_FLOAT16
                    case 14 => TypeKind.TYPE_FLOAT32
                    case 15 => TypeKind.TYPE_FLOAT64
                    case 16 => TypeKind.TYPE_IDEAL_FLOAT
                    case _ => TypeKind.TYPE_INVALID
                }
            }
        }
        return TypeKind.TYPE_INVALID
    }
}

public class FuncArg <: Node {
    public var name: SrcIdentifier = SrcIdentifier()
    public var colonPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public var commaPos: Position = INVALID_POSITION
    public var withInout: Bool = false
    public var inoutPos: Position = INVALID_POSITION

    public init() {
        super(ASTKind.FUNC_ARG)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }

    public override func Clear(): Unit {
        super.Clear()
        if (let Some(value) <- expr) {
            value.Clear()
        }
        DisableAttr(Attribute.HAS_INITIAL)
    }

    public override func ToString(): String {
        if (!name.Empty()) {
            if (let Some(value) <- expr) {
                let inoutText = if (withInout) { "inout " } else { "" }
                return name.Val() + ": " + inoutText + value.ToString()
            }
            return name.Val() + ":"
        }
        if (let Some(value) <- expr) {
            let inoutText = if (withInout) { "inout " } else { "" }
            return inoutText + value.ToString()
        }
        return ""
    }
}

public enum CallKind {
    | CALL_INVALID
    | CALL_DECLARED_FUNCTION
    | CALL_OBJECT_CREATION
    | CALL_FUNCTION_PTR
    | CALL_STRUCT_CREATION
    | CALL_SUPER_FUNCTION
    | CALL_VARIADIC_FUNCTION
    | CALL_ANNOTATION
    | CALL_BUILTIN_FUNCTION
    | CALL_INTRINSIC_FUNCTION
}

private func CallKindIndex(kind: CallKind): Int64 {
    return match (kind) {
        case CallKind.CALL_INVALID => 0
        case CallKind.CALL_DECLARED_FUNCTION => 1
        case CallKind.CALL_OBJECT_CREATION => 2
        case CallKind.CALL_FUNCTION_PTR => 3
        case CallKind.CALL_STRUCT_CREATION => 4
        case CallKind.CALL_SUPER_FUNCTION => 5
        case CallKind.CALL_VARIADIC_FUNCTION => 6
        case CallKind.CALL_ANNOTATION => 7
        case CallKind.CALL_BUILTIN_FUNCTION => 8
        case CallKind.CALL_INTRINSIC_FUNCTION => 9
    }
}

extend CallKind <: Equatable<CallKind> {
    public operator func ==(right: CallKind): Bool {
        return CallKindIndex(this) == CallKindIndex(right)
    }

    public operator func !=(right: CallKind): Bool {
        return !(this == right)
    }
}

public class CallExpr <: Expr {
    public var baseFunc: Option<Expr> = None
    public var leftParenPos: Position = INVALID_POSITION
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var rightParenPos: Position = INVALID_POSITION
    public var resolvedFunction: Option<FuncDecl> = None
    public var callKind: CallKind = CallKind.CALL_INVALID
    public var desugarArgs: Option<ArrayList<FuncArg>> = None
    public let defaultArgs: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var needCheckToTokens: Bool = false
    public var sugarKind: SugarKind = SugarKind.NO_SUGAR

    public init() {
        super(ASTKind.CALL_EXPR)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- baseFunc) { out.add(base) }
        for (arg in args) { out.add(arg) }
        return out
    }

    public override func Clear(): Unit {
        RecoverToCallExpr(this)
        super.Clear()
        if (let Some(base) <- baseFunc) {
            base.Clear()
        }
        callKind = CallKind.CALL_INVALID
        resolvedFunction = None
    }

    public override func ToString(): String {
        let parts = ArrayList<String>()
        for (arg in args) {
            parts.add(arg.ToString())
        }
        let base = if (let Some(value) <- baseFunc) { value.ToString() } else { "" }
        return base + "(" + JoinStrings(parts, ", ") + ")"
    }
}

public open class NameReferenceExpr <: Expr {
    public var leftAnglePos: Position = INVALID_POSITION
    public let typeArguments: ArrayList<Type> = ArrayList<Type>()
    public var rightAnglePos: Position = INVALID_POSITION
    public let instTys: ArrayList<Ty> = ArrayList<Ty>()
    public var callOrPattern: Option<Node> = None
    public var matchedParentTy: Option<Ty> = None
    public var aliasTarget: Option<TypeAliasDecl> = None
    public var isAlone: Bool = true
    public var compilerAddedTyArgs: Bool = false

    public init(kind: ASTKind) {
        super(kind)
    }

    public open override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (ty in typeArguments) { out.add(ty) }
        return out
    }

    public override func GetTypeArgs(): ArrayList<Type> {
        return typeArguments
    }

    public func OuterArgSize(): Int64 {
        if (let Some(node) <- callOrPattern) {
            if (let Some(call) <- (node as CallExpr)) {
                return call.args.size
            }
            if (let Some(pattern) <- (node as EnumPattern)) {
                return pattern.patterns.size
            }
        }
        return 0
    }
}

public class MemberAccess <: NameReferenceExpr {
    public var baseExpr: Option<Expr> = None
    public var dotPos: Position = INVALID_POSITION
    public var field: SrcIdentifier = SrcIdentifier()
    public let targets: ArrayList<Option<FuncDecl>> = ArrayList<Option<FuncDecl>>()
    public var target: Option<Decl> = None
    public let foundUpperBoundMap: ArrayList<(Decl, ArrayList<Ty>)> = ArrayList<(Decl, ArrayList<Ty>)>()
    public var isExposedAccess: Bool = false
    public var isPattern: Bool = false

    public init() {
        super(ASTKind.MEMBER_ACCESS)
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- baseExpr) { out.add(base) }
        for (ty in typeArguments) { out.add(ty) }
        return out
    }

    public override func Clear(): Unit {
        super.Clear()
        if (let Some(base) <- baseExpr) {
            base.Clear()
        }
        foundUpperBoundMap.clear()
        target = None
        targets.clear()
        instTys.clear()
        isExposedAccess = false
        matchedParentTy = None
        desugarExpr = None
    }

    public func GetFieldPos(): Position {
        return GetMacroCallPos(field.Begin())
    }

    public override func ToString(): String {
        let base = if (let Some(value) <- baseExpr) { value.ToString() + "." } else { "" }
        return base + field.GetRawText()
    }
}

public class ParenExpr <: Expr {
    public var leftParenPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public init() { super(ASTKind.PAREN_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }

    public override func ToString(): String {
        CJC_ASSERT(expr.isSome())
        return "(" + expr.getOrThrow().ToString() + ")"
    }
}

public class LambdaExpr <: Expr {
    public var funcBody: Option<FuncBody> = None
    public var mangledName: String = ""

    public init() {
        super(ASTKind.LAMBDA_EXPR)
    }

    public init(body: FuncBody) {
        super(ASTKind.LAMBDA_EXPR)
        funcBody = body
    }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(body) <- funcBody) { out.add(body) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(funcBody)
        return "{ " + funcBody.getOrThrow().ToString() + " }"
    }
}

public class TrailingClosureExpr <: Expr {
    public var leftLambda: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public var lambda: Option<LambdaExpr> = None
    public var rightLambda: Position = INVALID_POSITION
    public init() { super(ASTKind.TRAIL_CLOSURE_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- expr) { out.add(base) }
        if (let Some(value) <- lambda) { out.add(value) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(expr)
        var out = expr.getOrThrow().ToString()
        if (let Some(value) <- lambda) {
            out += " " + value.ToString()
        }
        return out
    }
}

public class OptionalExpr <: Expr {
    public var baseExpr: Option<Expr> = None
    public var questPos: Position = INVALID_POSITION
    public init() { super(ASTKind.OPTIONAL_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(base) <- baseExpr) { out.add(base) }
        return out
    }

    public override func ToString(): String {
        CJC_ASSERT(baseExpr.isSome())
        return baseExpr.getOrThrow().ToString() + "?"
    }
}

public class OptionalChainExpr <: Expr {
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.OPTIONAL_CHAIN_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }

    public override func ToString(): String {
        CJC_ASSERT(expr.isSome())
        return expr.getOrThrow().ToString()
    }
}

public class ArrayLit <: Expr {
    public var leftSquarePos: Position = INVALID_POSITION
    public let children: ArrayList<Expr> = ArrayList<Expr>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var rightSquarePos: Position = INVALID_POSITION
    public var initFunc: Option<FuncDecl> = None
    public init() { super(ASTKind.ARRAY_LIT) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (child in children) { out.add(child) }
        return out
    }

    public override func ToString(): String {
        return "[" + exprJoinExprs(children, ", ") + "]"
    }
}

public class ArrayExpr <: Expr {
    public var typeNode: Option<Type> = None
    public var leftParenPos: Position = INVALID_POSITION
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var rightParenPos: Position = INVALID_POSITION
    public var initFunc: Option<FuncDecl> = None
    public var isValueArray: Bool = false
    public init() { super(ASTKind.ARRAY_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(ty) <- typeNode) { out.add(ty) }
        for (arg in args) { out.add(arg) }
        return out
    }

    public override func ToString(): String {
        let typeText = if (let Some(value) <- typeNode) { value.ToString() } else { "" }
        return typeText + "(" + exprJoinFuncArgs(args, ", ") + ")"
    }
}

public class PointerExpr <: Expr {
    public var typeNode: Option<Type> = None
    public var arg: Option<FuncArg> = None
    public init() { super(ASTKind.POINTER_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(ty) <- typeNode) { out.add(ty) }
        if (let Some(value) <- arg) { out.add(value) }
        return out
    }

    public override func ToString(): String {
        var pointee = ""
        if (let Some(semTy) <- GetTy()) {
            if (!semTy.typeArgs.isEmpty()) {
                pointee = Ty.ToString(semTy.typeArgs[0])
            }
        }
        let argText = if (let Some(value) <- arg) { value.ToString() } else { "" }
        return "CPointer<" + pointee + ">(" + argText + ")"
    }
}

public class TupleLit <: Expr {
    public var leftParenPos: Position = INVALID_POSITION
    public let children: ArrayList<Expr> = ArrayList<Expr>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var rightParenPos: Position = INVALID_POSITION
    public init() { super(ASTKind.TUPLE_LIT) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        for (child in children) { out.add(child) }
        return out
    }
}

public class TypeConvExpr <: Expr {
    public var typeNode: Option<Type> = None
    public var leftParenPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public init() { super(ASTKind.TYPE_CONV_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(ty) <- typeNode) { out.add(ty) }
        if (let Some(child) <- expr) { out.add(child) }
        return out
    }

    public override func ToString(): String {
        CJC_ASSERT(typeNode.isSome())
        CJC_ASSERT(expr.isSome())
        return typeNode.getOrThrow().ToString() + "(" + expr.getOrThrow().ToString() + ")"
    }
}

public class RefExpr <: NameReferenceExpr {
    public var ref: Reference = Reference()
    public var isThis: Bool = false
    public var isSuper: Bool = false
    public var isQuoteDollar: Bool = false

    public init() {
        super(ASTKind.REF_EXPR)
    }

    public init(identifier: SrcIdentifier) {
        super(ASTKind.REF_EXPR)
        ref.identifier = identifier
        if (!identifier.IsRaw()) {
            isThis = identifier == "this"
            isSuper = identifier == "super"
        }
        begin = identifier.Begin()
        end = identifier.End()
    }

    public override func Clear(): Unit {
        super.Clear()
        ref.target = None
        ref.targets.clear()
        instTys.clear()
        matchedParentTy = None
    }

    public func GetIdentifierPos(): Position {
        return GetMacroCallPos(ref.identifier.Begin())
    }

    public override func ToString(): String {
        return ref.identifier.Val()
    }
}

public class PrimitiveTypeExpr <: Expr {
    public var typeKind: TypeKind = TypeKind.TYPE_INVALID

    public init(typeKind: TypeKind) {
        super(ASTKind.PRIMITIVE_TYPE_EXPR)
        this.typeKind = typeKind
    }

    public override func ToString(): String {
        return TypeKindName(typeKind)
    }
}

public class InvalidExpr <: Expr {
    public var value: String = ""

    public init() {
        super(ASTKind.INVALID_EXPR)
        EnableAttr(Attribute.IS_BROKEN)
    }

    public init(pos: Position) {
        super(ASTKind.INVALID_EXPR)
        EnableAttr(Attribute.IS_BROKEN)
        begin = pos
        end = pos
    }

    public override func ToString(): String {
        return if (value.isEmpty()) { "<invalid>" } else { value }
    }
}

public class SpawnExpr <: Expr {
    public var spawnPos: Position = INVALID_POSITION
    public var futureObj: Option<VarDecl> = None
    public var task: Option<Expr> = None
    public var arg: Option<Expr> = None
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public init() { super(ASTKind.SPAWN_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(expr) <- arg) { out.add(expr) }
        if (let Some(expr) <- task) { out.add(expr) }
        return out
    }

    public override func ToString(): String {
        var out = "spawn"
        if (let Some(value) <- arg) {
            out += "(" + value.ToString() + ")"
        }
        CJC_NULLPTR_CHECK(task)
        out += " " + task.getOrThrow().ToString()
        return out
    }
}

public class SynchronizedExpr <: Expr {
    public var syncPos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var mutex: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public var body: Option<Block> = None
    public init() { super(ASTKind.SYNCHRONIZED_EXPR) }

    public override func Children(): ArrayList<Node> {
        let out = ArrayList<Node>()
        if (let Some(expr) <- mutex) { out.add(expr) }
        if (let Some(block) <- body) { out.add(block) }
        return out
    }

    public override func ToString(): String {
        CJC_NULLPTR_CHECK(mutex)
        CJC_NULLPTR_CHECK(body)
        return "synchronized (" + mutex.getOrThrow().ToString() + ") " + body.getOrThrow().ToString()
    }
}
