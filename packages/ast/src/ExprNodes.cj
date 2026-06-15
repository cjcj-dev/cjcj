package cangjie_compiler::ast

import std.collection.*

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

    public func GetLastExprOrDecl(): Option<Node> {
        if (body.isEmpty()) {
            return None
        }
        return body[body.size - 1]
    }

    public override func ToString(): String {
        let parts = ArrayList<String>()
        for (node in body) {
            parts.add(node.ToString())
        }
        return "{" + JoinStrings(parts, "\n") + "}"
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
}

public class LetPatternDestructor <: Expr {
    public let patterns: ArrayList<Pattern> = ArrayList<Pattern>()
    public let orPos: ArrayList<Position> = ArrayList<Position>()
    public var backarrowPos: Position = INVALID_POSITION
    public var initializer: Option<Expr> = None

    public init() {
        super(ASTKind.LET_PATTERN_DESTRUCTOR)
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
}

public class QuoteExpr <: Expr {
    public var quotePos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public let exprs: ArrayList<Expr> = ArrayList<Expr>()

    public init() {
        super(ASTKind.QUOTE_EXPR)
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

    public func SetCtxExprForPatterns(ctxExpr: Expr): Unit {
        for (pattern in patterns) {
            pattern.ctxExpr = ctxExpr
        }
    }
}

public class MatchCaseOther <: Node {
    public var matchExpr: Option<Expr> = None
    public var arrowPos: Position = INVALID_POSITION
    public var exprOrDecls: Option<Block> = None

    public init() {
        super(ASTKind.MATCH_CASE_OTHER)
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
}

public class ThrowExpr <: Expr {
    public var throwPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.THROW_EXPR) }
}

public class PerformExpr <: Expr {
    public var performPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.PERFORM_EXPR) }
}

public class ResumeExpr <: Expr {
    public var resumePos: Position = INVALID_POSITION
    public var withPos: Position = INVALID_POSITION
    public var withExpr: Option<Expr> = None
    public var throwingPos: Position = INVALID_POSITION
    public var throwingExpr: Option<Expr> = None
    public var enclosing: Option<Handler> = None
    public init() { super(ASTKind.RESUME_EXPR) }
}

public class ReturnExpr <: Expr {
    public var returnPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public var refFuncBody: Option<FuncBody> = None
    public init() { super(ASTKind.RETURN_EXPR) }
}

public class JumpExpr <: Expr {
    public var refLoop: Option<Expr> = None
    public var isBreak: Bool = false
    public init() { super(ASTKind.JUMP_EXPR) }
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
}

public class WhileExpr <: Expr {
    public var whilePos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var condExpr: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public var body: Option<Block> = None
    public var sugarKind: SugarKind = SugarKind.NO_SUGAR
    public init() { super(ASTKind.WHILE_EXPR) }
}

public class DoWhileExpr <: Expr {
    public var doPos: Position = INVALID_POSITION
    public var body: Option<Block> = None
    public var whilePos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var condExpr: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public init() { super(ASTKind.DO_WHILE_EXPR) }
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
}

public class IncOrDecExpr <: OverloadableExpr {
    public var operatorPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.INC_OR_DEC_EXPR) }
}

public class UnaryExpr <: OverloadableExpr {
    public var expr: Option<Expr> = None
    public var operatorPos: Position = INVALID_POSITION
    public init() { super(ASTKind.UNARY_EXPR) }
}

public class BinaryExpr <: OverloadableExpr {
    public var leftExpr: Option<Expr> = None
    public var rightExpr: Option<Expr> = None
    public var operatorPos: Position = INVALID_POSITION
    public init() { super(ASTKind.BINARY_EXPR) }
}

public class IsExpr <: Expr {
    public var leftExpr: Option<Expr> = None
    public var isType: Option<Type> = None
    public var isPos: Position = INVALID_POSITION
    public init() { super(ASTKind.IS_EXPR) }
}

public class AsExpr <: Expr {
    public var leftExpr: Option<Expr> = None
    public var asType: Option<Type> = None
    public var asPos: Position = INVALID_POSITION
    public init() { super(ASTKind.AS_EXPR) }
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

    public func IsVArrayAccess(): Bool {
        if (let Some(base) <- baseExpr) {
            return base.TyKind() == TypeKind.TYPE_VARRAY
        }
        return false
    }
}

public class InterpolationExpr <: Expr {
    public var rawString: String = ""
    public var dollarPos: Position = INVALID_POSITION
    public var block: Option<Block> = None
    public init() { super(ASTKind.INTERPOLATION_EXPR) }
}

public class StrInterpolationExpr <: Expr {
    public var rawString: String = ""
    public let strParts: ArrayList<StringPart> = ArrayList<StringPart>()
    public let strPartExprs: ArrayList<Expr> = ArrayList<Expr>()
    public init() { super(ASTKind.STR_INTERPOLATION_EXPR) }
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

private func LitConstKindIndex(kind: LitConstKind): Int64 {
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
        if (kind == LitConstKind.RUNE_BYTE) {
            return TypeKind.TYPE_UINT8
        }
        if (kind == LitConstKind.INTEGER) {
            if (stringValue.endsWith("i8")) { return TypeKind.TYPE_INT8 }
            if (stringValue.endsWith("i16")) { return TypeKind.TYPE_INT16 }
            if (stringValue.endsWith("i32")) { return TypeKind.TYPE_INT32 }
            if (stringValue.endsWith("i64")) { return TypeKind.TYPE_INT64 }
            if (stringValue.endsWith("u8")) { return TypeKind.TYPE_UINT8 }
            if (stringValue.endsWith("u16")) { return TypeKind.TYPE_UINT16 }
            if (stringValue.endsWith("u32")) { return TypeKind.TYPE_UINT32 }
            if (stringValue.endsWith("u64")) { return TypeKind.TYPE_UINT64 }
            return TypeKind.TYPE_IDEAL_INT
        }
        if (kind == LitConstKind.FLOAT) {
            if (stringValue.endsWith("f16")) { return TypeKind.TYPE_FLOAT16 }
            if (stringValue.endsWith("f32")) { return TypeKind.TYPE_FLOAT32 }
            if (stringValue.endsWith("f64")) { return TypeKind.TYPE_FLOAT64 }
            return TypeKind.TYPE_IDEAL_FLOAT
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

    public override func Clear(): Unit {
        super.Clear()
        if (let Some(value) <- expr) {
            value.Clear()
        }
        DisableAttr(Attribute.HAS_INITIAL)
    }

    public override func ToString(): String {
        var prefix = ""
        if (!name.Empty()) {
            prefix = name.GetRawText() + ": "
        }
        if (let Some(value) <- expr) {
            return prefix + value.ToString()
        }
        return prefix
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

public class CallExpr <: Expr {
    public var baseFunc: Option<Expr> = None
    public var leftParenPos: Position = INVALID_POSITION
    public let args: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var rightParenPos: Position = INVALID_POSITION
    public var resolvedFunction: Option<FuncDecl> = None
    public var callKind: CallKind = CallKind.CALL_INVALID
    public let defaultArgs: ArrayList<FuncArg> = ArrayList<FuncArg>()
    public var needCheckToTokens: Bool = false
    public var sugarKind: SugarKind = SugarKind.NO_SUGAR

    public init() {
        super(ASTKind.CALL_EXPR)
    }

    public override func Clear(): Unit {
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
    public let targets: ArrayList<Decl> = ArrayList<Decl>()
    public var target: Option<Decl> = None
    public let foundUpperBoundMap: ArrayList<(Decl, ArrayList<Ty>)> = ArrayList<(Decl, ArrayList<Ty>)>()
    public var isExposedAccess: Bool = false
    public var isPattern: Bool = false

    public init() {
        super(ASTKind.MEMBER_ACCESS)
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
}

public class TrailingClosureExpr <: Expr {
    public var leftLambda: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public var lambda: Option<LambdaExpr> = None
    public var rightLambda: Position = INVALID_POSITION
    public init() { super(ASTKind.TRAIL_CLOSURE_EXPR) }
}

public class OptionalExpr <: Expr {
    public var baseExpr: Option<Expr> = None
    public var questPos: Position = INVALID_POSITION
    public init() { super(ASTKind.OPTIONAL_EXPR) }
}

public class OptionalChainExpr <: Expr {
    public var expr: Option<Expr> = None
    public init() { super(ASTKind.OPTIONAL_CHAIN_EXPR) }
}

public class ArrayLit <: Expr {
    public var leftSquarePos: Position = INVALID_POSITION
    public let children: ArrayList<Expr> = ArrayList<Expr>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var rightSquarePos: Position = INVALID_POSITION
    public var initFunc: Option<FuncDecl> = None
    public init() { super(ASTKind.ARRAY_LIT) }
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
}

public class PointerExpr <: Expr {
    public var typeNode: Option<Type> = None
    public var arg: Option<FuncArg> = None
    public init() { super(ASTKind.POINTER_EXPR) }
}

public class TupleLit <: Expr {
    public var leftParenPos: Position = INVALID_POSITION
    public let children: ArrayList<Expr> = ArrayList<Expr>()
    public let commaPosVector: ArrayList<Position> = ArrayList<Position>()
    public var rightParenPos: Position = INVALID_POSITION
    public init() { super(ASTKind.TUPLE_LIT) }
}

public class TypeConvExpr <: Expr {
    public var typeNode: Option<Type> = None
    public var leftParenPos: Position = INVALID_POSITION
    public var expr: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public init() { super(ASTKind.TYPE_CONV_EXPR) }
}

public class RefExpr <: NameReferenceExpr {
    public var ref: Reference = Reference()
    public var isThis: Bool = false
    public var isSuper: Bool = false
    public var isQuoteDollar: Bool = false

    public init() {
        super(ASTKind.REF_EXPR)
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
        return ref.identifier.GetRawText()
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
}

public class SpawnExpr <: Expr {
    public var spawnPos: Position = INVALID_POSITION
    public var futureObj: Option<VarDecl> = None
    public var task: Option<Expr> = None
    public var arg: Option<Expr> = None
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public init() { super(ASTKind.SPAWN_EXPR) }
}

public class SynchronizedExpr <: Expr {
    public var syncPos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var mutex: Option<Expr> = None
    public var rightParenPos: Position = INVALID_POSITION
    public var body: Option<Block> = None
    public init() { super(ASTKind.SYNCHRONIZED_EXPR) }
}
