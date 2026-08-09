package cjcj::ast

import std.collection.*

public class MacroInvocation {
    public var macroCallDiagInfo: MacroCallDiagInfo = MacroCallDiagInfo()
    public let fullNameDotPos: ArrayList<Position> = ArrayList<Position>()
    public var leftSquarePos: Position = INVALID_POSITION
    public var rightSquarePos: Position = INVALID_POSITION
    public var leftParenPos: Position = INVALID_POSITION
    public var rightParenPos: Position = INVALID_POSITION
    public var atPos: Position = INVALID_POSITION
    public var macroNamePos: Position = INVALID_POSITION
    public let attrs: ArrayList<Token> = ArrayList<Token>()
    public let args: ArrayList<Token> = ArrayList<Token>()
    public var decl: Option<Decl> = None
    public var parent: Option<Node> = None
    public var target: Option<Decl> = None
    public var outerDeclIdent: String = ""
    public let nodes: ArrayList<Node> = ArrayList<Node>()
    public let macroAtPosition: ArrayList<Position> = ArrayList<Position>()
    public let newTokens: ArrayList<Token> = ArrayList<Token>()
    public var newTokensStr: String = ""
    // Mirrors Node.h:2419 std::variant<ScopeKind, ExprKind> scope. Option presence
    // preserves the active alternative even when its value is UNKNOWN_*.
    public var scopeKind: Option<ScopeKind> = Some(ScopeKind.UNKNOWN_SCOPE)
    public var exprKind: Option<ExprKind> = None
    public var hasParenthesis: Bool = false
    public var hasAttr: Bool = false
    public var isFuncParam: Bool = false
    public var isCompileTimeVisible: Bool = false
    // Official Node.h:2426 is std::map<unsigned, Position, greater<>> (descending).
    // ArrayList + append/replace is equivalent for exact-key lookup only while write
    // keys stay non-decreasing (RefreshNewTokensPos advances lastColumn only upward).
    // collectMacroDebugPosition treats the last entry as max-key; that premise is a
    // write-order contract, not a structural guarantee — re-check if writers change.
    public let macroDebugMap: ArrayList<(UInt64, Position)> = ArrayList<(UInt64, Position)>()
    public let origin2newPosMap: ArrayList<(UInt64, Position)> = ArrayList<(UInt64, Position)>()

    public init() {}

    public func HasAttr(): Bool {
        return hasAttr
    }

    public func IsIfAvailable(): Bool {
        return macroCallDiagInfo.fullName == "IfAvailable"
    }
}

public class MacroExpandExpr <: Expr {
    public var invocation: MacroInvocation = MacroInvocation()
    public var identifier: Identifier = Identifier()
    public let annotations: ArrayList<Annotation> = ArrayList<Annotation>()
    public let modifiers: ArrayList<Modifier> = ArrayList<Modifier>()

    public init() {
        super(ASTKind.MACRO_EXPAND_EXPR)
    }

    public func GetNamedArg(): Option<FuncArg> {
        if (invocation.IsIfAvailable() && !invocation.nodes.isEmpty()) {
            return invocation.nodes[0] as FuncArg
        }
        return None
    }

    public func GetLambda(i: Int64): Option<LambdaExpr> {
        if (invocation.IsIfAvailable() && invocation.nodes.size > i) {
            return invocation.nodes[i + 1] as LambdaExpr
        }
        return None
    }

    // Mirrors AST/Node.cpp:728-733 MacroExpandExpr::Decompose.
    public func Decompose(): (FuncArg, LambdaExpr, LambdaExpr) {
        let namedArg = (invocation.nodes[0] as FuncArg).getOrThrow()
        let lambda1 = (invocation.nodes[1] as LambdaExpr).getOrThrow()
        let lambda2 = (invocation.nodes[2] as LambdaExpr).getOrThrow()
        invocation.nodes.clear()
        return (namedArg, lambda1, lambda2)
    }
}

public class MacroExpandDecl <: Decl {
    public var invocation: MacroInvocation = MacroInvocation()

    public init() {
        super(ASTKind.MACRO_EXPAND_DECL)
    }

    public override func ToString(): String {
        return "@" + identifier.Val()
    }
}

public class MacroExpandParam <: FuncParam {
    public var invocation: MacroInvocation = MacroInvocation()

    public init() {
        super(ASTKind.MACRO_EXPAND_PARAM)
        invocation.isFuncParam = true
    }
}
