package cjcj::parse

import std.collection.*
import cjcj::ast.MacroExpandDecl as AstMacroExpandDecl
import cjcj::ast.ExprKind as AstExprKind
import cjcj::ast.FuncBody as AstFuncBody
import cjcj::ast.FuncParam as AstFuncParam
import cjcj::ast.FuncParamList as AstFuncParamList
import cjcj::ast.MacroInvocation as AstMacroInvocation
import cjcj::ast.VarDecl as AstVarDecl
import cjcj::utils.IF_AVAILABLE

private let G_NO_NEED_SEMI_EXPR_LIST: Array<ASTKind> = [
    ASTKind.THROW_EXPR, ASTKind.RETURN_EXPR, ASTKind.ASSIGN_EXPR, ASTKind.UNARY_EXPR, ASTKind.SPAWN_EXPR,
    ASTKind.IF_EXPR, ASTKind.TRY_EXPR, ASTKind.FOR_IN_EXPR, ASTKind.WHILE_EXPR
]

extend ParserImpl {
    public func ParseExpr(): Expr {
        return ParseExpr(ExprKind.ALL)
    }

    public func ParseExpr(ek: ExprKind): Expr {
        if (ExprKindEquals(ek, ExprKind.UNKNOWN_EXPR) && Seeing(TokenKind.LET)) {
            return ParseLetPattern(ek)
        }
        let ret = if (ExprKindEquals(ek, ExprKind.INDEX_EXPR)) {
            ParseIndexAccess()
        } else if (enableCustomAnno && SeeingIfAvailable()) {
            ParseIfAvailable()
        } else {
            let left = ParseUnaryExpr(ek)
            ParseExprRhs(0, left, ek)
        }
        if (ExprKindEquals(ek, ExprKind.VAR_INIT) && IsAssignmentExpressionRoot(ret)) {
            DiagCannotHaveAssignmentInInit(ret)
            ret.isBroken = true
        }
        if (!SeeingExprOperator() && !ExprKindEquals(ek, ExprKind.EXPR_IN_TUPLE) &&
            !ExprKindEquals(ek, ExprKind.EXPR_IN_IF_COND_TUPLE) &&
            !ExprKindEquals(ek, ExprKind.EXPR_IN_WHILE_COND_TUPLE)) {
            CheckWildcardInExpr(ret)
        }
        if (Seeing(TokenKind.SEMI) && !G_NO_NEED_SEMI_EXPR_LIST.contains(ret.astKind)) {
            ret.hasSemi = true
            ret.semiPos = Peek().Begin()
        }
        if (let Some(macroExpr) <- (ret as MacroExpandExpr)) {
            macroExpr.invocation.exprKind = match (ek) {
                case ExprKind.ALL => AstExprKind.ALL
                case ExprKind.VAR_INIT => AstExprKind.VAR_INIT
                case ExprKind.INDEX_EXPR => AstExprKind.INDEX_EXPR
                case ExprKind.IF_COND_EXPR => AstExprKind.IF_COND_EXPR
                case ExprKind.WHILE_COND_EXPR => AstExprKind.WHILE_COND_EXPR
                case ExprKind.LET_PATTERN => AstExprKind.LET_PATTERN
                case ExprKind.LEFT_EXPR => AstExprKind.LEFT_EXPR
                case ExprKind.EXPR_IN_TUPLE => AstExprKind.EXPR_IN_TUPLE
                case ExprKind.EXPR_IN_IF_COND_TUPLE => AstExprKind.EXPR_IN_IF_COND_TUPLE
                case ExprKind.EXPR_IN_WHILE_COND_TUPLE => AstExprKind.EXPR_IN_WHILE_COND_TUPLE
                case ExprKind.EXPR_IN_ARRAY => AstExprKind.EXPR_IN_ARRAY
                case ExprKind.EXPR_IN_CALLSUFFIX => AstExprKind.EXPR_IN_CALLSUFFIX
                case ExprKind.EXPR_IN_ANNOTATION => AstExprKind.EXPR_IN_ANNOTATION
                case ExprKind.UNKNOWN_EXPR => AstExprKind.UNKNOWN_EXPR
            }
        }
        if (SeeingFakeOperator()) {
            DiagExpecetedOpeOrEnd()
            ConsumeUntilAny([TokenKind.NL])
        }
        return ret
    }

    public func ParseUnaryExpr(): Expr {
        return ParseUnaryExpr(ExprKind.ALL)
    }

    public func ParseUnaryExpr(ek: ExprKind): Expr {
        if (Seeing([TokenKind.SUB, TokenKind.NL], skipNewline: false) ||
            Seeing([TokenKind.NOT, TokenKind.NL], skipNewline: false)) {
            DiagExpectedNoNewLine()
            return InvalidExpr(Peek().Begin())
        }
        if (Seeing(TokenKind.NOT) || Seeing(TokenKind.ADD) || Seeing(TokenKind.SUB) || Seeing(TokenKind.BITNOT)) {
            let op = Peek()
            Next()
            let unary = UnaryExpr()
            try (cs = ChainScope(this, unary)) {
                unary.op = op.kind
                unary.operatorPos = op.Begin()
                unary.begin = op.Begin()
                let child = ParseUnaryExpr(RemoveParsingIfCondExpr(ek))
                if (op.kind == TokenKind.SUB) {
                    if (let Some(lit) <- (child as LitConstExpr)) {
                        if ((lit.kind == LitConstKind.INTEGER || lit.kind == LitConstKind.FLOAT) &&
                            !lit.stringValue.isEmpty() && lit.stringValue[0] != b'-') {
                            lit.stringValue = "-" + lit.stringValue
                            lit.rawString = lit.stringValue
                            lit.begin = op.Begin()
                            return lit
                        }
                    }
                }
                unary.expr = child
                if (let Some(child) <- unary.expr) { unary.end = child.end }
            }
            return unary
        }
        return ParseBaseExpr(ParseAtom(ek), ek)
    }

    public func RemoveParsingIfCondExpr(ek: ExprKind): ExprKind {
        if (ExprKindEquals(ek, ExprKind.EXPR_IN_IF_COND_TUPLE) ||
            ExprKindEquals(ek, ExprKind.EXPR_IN_WHILE_COND_TUPLE) ||
            ExprKindEquals(ek, ExprKind.IF_COND_EXPR) ||
            ExprKindEquals(ek, ExprKind.WHILE_COND_EXPR)) {
            return ExprKind.ALL
        }
        return ek
    }

    private func IsCompoundAssign(token: TokenKind): Bool {
        return token != TokenKind.ASSIGN && IsAssignment(token)
    }

    private func IsNeedToCreateOptionalChain(token: TokenKind, expr: Expr): Bool {
        if (!IsCompoundAssign(token) && token != TokenKind.ASSIGN && expr.hasQuestSuffix) {
            return true
        }
        if (let Some(incDecl) <- (expr as IncOrDecExpr)) {
            if (let Some(innerExpr) <- incDecl.expr) {
                return innerExpr.hasQuestSuffix
            }
        }
        return false
    }

    private func GetExprOperator(): Token {
        var token = Peek()
        if (let Some(combInfo) <- LookupSeenCombinator()) {
            token.kind = combInfo.kind
            token.SetValuePos(combInfo.Value(), token.Begin(), token.Begin() + combInfo.Value().size)
        }
        return token
    }

    public func ParseBaseExpr(expr: Expr): Expr {
        return ParseBaseExpr(expr, ExprKind.ALL)
    }

    public func ParseBaseExpr(expr: Expr, ek: ExprKind): Expr {
        var base = expr
        var hasQuestSuffix = false
        while (true) {
            if (newlineSkipped && !Seeing(TokenKind.DOT)) {
                break
            }
            if (!newlineSkipped && SeeingOptionalSuffix()) {
                base = ParseQuestSuffixExpr(base)
                hasQuestSuffix = true
            } else if (Seeing(TokenKind.QUEST) && !SeeingCombinator([TokenKind.QUEST, TokenKind.QUEST])) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character_after, Peek().Begin(),
                    "'.', '(', '[', '{' or '?'", Peek().Value()).Emit()
                Next()
                break
            }
            if (!newlineSkipped && Skip(TokenKind.LPAREN)) {
                let call = CallExpr()
                try (cs = ChainScope(this, call)) {
                    base.isBaseFunc = true
                    call.baseFunc = base
                    call.leftParenPos = lastToken.Begin()
                    call.begin = base.begin
                    while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                        call.args.add(ParseFuncArg())
                        if (!Skip(TokenKind.COMMA)) { break }
                    }
                    if (!Skip(TokenKind.RPAREN) && !call.TestAttr(Attribute.HAS_BROKEN)) {
                        call.EnableAttr(Attribute.HAS_BROKEN)
                        DiagExpectedRightDelimiter("(", call.leftParenPos)
                    }
                    call.rightParenPos = lastToken.Begin()
                    call.end = lastToken.End()
                }
                base = call
                continue
            }
            if (Skip(TokenKind.DOT)) {
                let member = MemberAccess()
                try (cs = ChainScope(this, member)) {
                    member.baseExpr = base
                    member.dotPos = lastToken.Begin()
                    member.begin = base.begin
                    member.field = ExpectIdentifierWithPos(member)
                    if (Seeing(TokenKind.LT) && LooksLikeTypeArguments()) {
                        let parsed = ParseTypeArguments(ek)
                        if (parsed[0]) {
                            for (ty in parsed[1]) { member.typeArguments.add(ty) }
                        }
                    }
                    member.end = member.field.End()
                }
                base = member
                continue
            }
            if (!newlineSkipped && Skip(TokenKind.LSQUARE)) {
                let sub = SubscriptExpr()
                try (cs = ChainScope(this, sub)) {
                    sub.baseExpr = base
                    sub.leftParenPos = lastToken.Begin()
                    sub.begin = base.begin
                    while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RSQUARE)) {
                        if (!sub.indexExprs.isEmpty()) {
                            sub.commaPos.add(lastToken.Begin())
                        }
                        sub.indexExprs.add(ParseExpr(ExprKind.INDEX_EXPR))
                        if (!Skip(TokenKind.COMMA)) { break }
                    }
                    if (!Skip(TokenKind.RSQUARE)) {
                        DiagExpectedRightDelimiter("[", sub.leftParenPos)
                        sub.EnableAttr(Attribute.HAS_BROKEN)
                    }
                    sub.rightParenPos = lastToken.Begin()
                    sub.end = lastToken.End()
                }
                base = sub
                continue
            }
            if ((Seeing(TokenKind.INCR) || Seeing(TokenKind.DECR)) && !newlineSkipped) {
                let op = Peek()
                Next()
                let incOrDec = IncOrDecExpr()
                incOrDec.expr = base
                incOrDec.op = op.kind
                incOrDec.operatorPos = op.Begin()
                incOrDec.begin = base.begin
                incOrDec.end = op.End()
                base = incOrDec
                continue
            }
            if (!newlineSkipped && Seeing(TokenKind.LCURL)) {
                let trailing = TrailingClosureExpr()
                trailing.lambda = ParseLambdaExprWithTrailingClosure()
                CheckBaseOfTrailingClosureExpr(base)
                trailing.expr = base
                trailing.begin = base.begin
                if (let Some(lambda) <- trailing.lambda) { trailing.end = lambda.end }
                base = trailing
                continue
            }
            break
        }
        if (hasQuestSuffix) {
            base.hasQuestSuffix = true
        }
        if (IsNeedToCreateOptionalChain(GetExprOperator().kind, base)) {
            let chain = OptionalChainExpr()
            chain.expr = base
            chain.begin = base.begin
            chain.end = base.end
            base = chain
        }
        return base
    }

    private func CheckBaseOfTrailingClosureExpr(baseExpr: Expr): Unit {
        if (baseExpr.TestAttr(Attribute.IS_BROKEN)) {
            return
        }
        if (![ASTKind.MACRO_EXPAND_EXPR, ASTKind.ARRAY_EXPR, ASTKind.OPTIONAL_EXPR, ASTKind.CALL_EXPR,
            ASTKind.REF_EXPR, ASTKind.MEMBER_ACCESS].contains(baseExpr.astKind)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_trailing_closure_only_follow_name, baseExpr).Emit()
        }
        if (baseExpr.astKind == ASTKind.CALL_EXPR) {
            let callExpr = (baseExpr as CallExpr).getOrThrow()
            let baseFunc = callExpr.baseFunc.getOrThrow()
            if (baseFunc.TestAttr(Attribute.IS_BROKEN)) {
                return
            }
            if (![ASTKind.MEMBER_ACCESS, ASTKind.REF_EXPR, ASTKind.OPTIONAL_EXPR].contains(baseFunc.astKind)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_trailing_closure_only_follow_name, baseExpr).Emit()
            }
        }
    }

    public func SeeingOptionalSuffix(): Bool {
        return Seeing([TokenKind.QUEST, TokenKind.DOT]) || Seeing([TokenKind.QUEST, TokenKind.LPAREN], skipNewline: false) ||
            Seeing([TokenKind.QUEST, TokenKind.LSQUARE], skipNewline: false) ||
            Seeing([TokenKind.QUEST, TokenKind.LCURL], skipNewline: false)
    }

    public func ParseQuestSuffixExpr(expr: Expr): OptionalExpr {
        let token = Expect(TokenKind.QUEST, "expected '?'")
        let ret = OptionalExpr()
        ret.baseExpr = expr
        ret.questPos = token.Begin()
        ret.begin = expr.begin
        ret.end = expr.end
        return ret
    }

    public func ParseExprRhs(minPrec: UInt8, left: Expr, ek: ExprKind): Expr {
        return ParseExprRhsWithPre(minPrec, left, ek, Token(TokenKind.SENTINEL))
    }

    private func ParseExprRhsWithPre(minPrec: UInt8, left: Expr, ek: ExprKind, preOp: Token): Expr {
        var lhs = left
        while (true) {
            var op = Peek()
            var combinedOperator = false
            if (let Some(combined) <- LookupSeenCombinator()) {
                op = combined
                combinedOperator = true
            }
            let prec = Precedence(op.kind)
            if (prec < minPrec || prec == INVALID_PRECEDENCE) {
                return lhs
            }
            if (ExprKindEquals(ek, ExprKind.LET_PATTERN) && prec < Precedence(TokenKind.RANGEOP)) {
                return lhs
            }
            if (IsConditionExprKind(ek) && lhs.astKind == ASTKind.LET_PATTERN_DESTRUCTOR &&
                prec < Precedence(TokenKind.RANGEOP) && op.kind != TokenKind.AND && op.kind != TokenKind.OR) {
                return lhs
            }
            if (IsAssignment(op.kind)) {
                CheckLeftExpression(lhs, op)
            }
            if (!CheckMacroExprRules(preOp, op, lhs)) {
                lhs.isBroken = true
            }
            if (combinedOperator) {
                SkipAmbiguousToken()
            } else {
                Next()
            }
            if (op.kind == TokenKind.IS || op.kind == TokenKind.AS) {
                if (op.kind == TokenKind.IS) {
                    let expr = IsExpr()
                    expr.leftExpr = lhs
                    expr.isPos = op.Begin()
                    expr.begin = lhs.begin
                    try (cs = ChainScope(this, expr)) {
                        let typeNode = ParseType()
                        expr.isType = typeNode
                        expr.end = typeNode.end
                    }
                    lhs = expr
                } else {
                    let expr = AsExpr()
                    expr.leftExpr = lhs
                    expr.asPos = op.Begin()
                    expr.begin = lhs.begin
                    try (cs = ChainScope(this, expr)) {
                        let typeNode = ParseType()
                        expr.asType = typeNode
                        expr.end = typeNode.end
                    }
                    lhs = expr
                }
                continue
            }
            let node: Expr = if (IsAssignment(op.kind)) {
                let expr = AssignExpr()
                expr.leftValue = lhs
                expr.op = op.kind
                expr.assignPos = op.Begin()
                expr.isCompound = op.kind != TokenKind.ASSIGN
                expr.begin = lhs.begin
                expr.hasQuestSuffix = lhs.hasQuestSuffix
                expr
            } else if (op.kind == TokenKind.RANGEOP || op.kind == TokenKind.CLOSEDRANGEOP) {
                let expr = RangeExpr()
                expr.startExpr = lhs
                expr.rangePos = op.Begin()
                expr.isClosed = op.kind == TokenKind.CLOSEDRANGEOP
                expr.begin = lhs.begin
                expr
            } else {
                let expr = BinaryExpr()
                expr.leftExpr = lhs
                expr.op = op.kind
                expr.operatorPos = op.Begin()
                expr.begin = lhs.begin
                expr
            }
            try (cs = ChainScope(this, node)) {
                var rhs = ParseUnaryExpr(ek)
                var nextOp = Peek()
                if (let Some(nextCombined) <- LookupSeenCombinator()) {
                    nextOp = nextCombined
                }
                let nextPrec = Precedence(nextOp.kind)
                if (prec < nextPrec) {
                    rhs = ParseExprRhsWithPre(prec + 1, rhs, ek, op)
                } else if (prec == nextPrec && (nextOp.kind == TokenKind.COALESCING || nextOp.kind == TokenKind.EXP)) {
                    rhs = ParseExprRhsWithPre(prec, rhs, ek, op)
                } else if (prec == nextPrec && IsNoneAssociative(nextOp.kind) && !rhs.isBroken) {
                    DiagNoneAssociativeOp(op, nextOp)
                    rhs.isBroken = true
                }
                if (!CheckMacroExprRules(op, Token(TokenKind.DOT), rhs)) {
                    rhs.isBroken = true
                    node.isBroken = true
                }
                if (let Some(assign) <- (node as AssignExpr)) {
                    assign.rightExpr = rhs
                    assign.end = rhs.end
                    if (op.kind == TokenKind.ASSIGN) {
                        CheckWildcardInExpr(rhs)
                    }
                    assign.isBroken = assign.isBroken || rhs.isBroken
                } else if (let Some(range) <- (node as RangeExpr)) {
                    range.stopExpr = rhs
                    range.end = rhs.end
                    range.isBroken = range.isBroken || rhs.isBroken
                    if (Skip(TokenKind.COLON)) {
                        range.colonPos = lastToken.Begin()
                        let dot2 = ".."
                        var preT = Token(TokenKind.RANGEOP, dot2, range.rangePos, range.rangePos + dot2.size)
                        preT.kind = if (range.isClosed) { TokenKind.CLOSEDRANGEOP } else { preT.kind }
                        let op = if (range.isClosed) { "..=" } else { preT.Value() }
                        preT.SetValuePos(op, preT.Begin(), preT.Begin() + op.size)
                        range.stepExpr = ParseExprWithPrevious(preT, ExprKind.ALL)
                        if (let Some(step) <- range.stepExpr) {
                            range.end = step.end
                        }
                    }
                } else if (let Some(binary) <- (node as BinaryExpr)) {
                    binary.rightExpr = rhs
                    binary.end = rhs.end
                    binary.isBroken = binary.isBroken || rhs.isBroken
                }
            }
            if (let Some(assign) <- (node as AssignExpr)) {
                if (assign.hasQuestSuffix) {
                    let chain = OptionalChainExpr()
                    chain.expr = assign
                    chain.begin = assign.begin
                    chain.end = assign.end
                    chain.hasQuestSuffix = true
                    lhs = chain
                    continue
                }
            }
            lhs = node
        }
        return lhs
    }

    private func ParseExprWithPrevious(preT: Token, ek: ExprKind): Expr {
        return ParseExprWithPrevious(preT, ParseUnaryExpr(ek), ek)
    }

    private func ParseExprWithPrevious(preT: Token, left: Expr, ek: ExprKind): Expr {
        var lhs = left
        let prePrec = Precedence(preT.kind)
        while (true) {
            var op = Peek()
            var combinedOperator = false
            if (let Some(combined) <- LookupSeenCombinator()) {
                op = combined
                combinedOperator = true
            }
            let prec = Precedence(op.kind)
            if (prec <= prePrec || prec == INVALID_PRECEDENCE) {
                return lhs
            }
            if (ExprKindEquals(ek, ExprKind.LET_PATTERN) && prec < Precedence(TokenKind.RANGEOP)) {
                return lhs
            }
            if (IsConditionExprKind(ek) && lhs.astKind == ASTKind.LET_PATTERN_DESTRUCTOR &&
                prec < Precedence(TokenKind.RANGEOP) && op.kind != TokenKind.AND && op.kind != TokenKind.OR) {
                return lhs
            }
            if (IsAssignment(op.kind)) {
                CheckLeftExpression(lhs, op)
            }
            if (!CheckMacroExprRules(preT, op, lhs)) {
                lhs.isBroken = true
            }
            if (combinedOperator) {
                SkipAmbiguousToken()
            } else {
                Next()
            }
            if (op.kind == TokenKind.IS || op.kind == TokenKind.AS) {
                if (op.kind == TokenKind.IS) {
                    let expr = IsExpr()
                    expr.leftExpr = lhs
                    expr.isPos = op.Begin()
                    expr.begin = lhs.begin
                    try (cs = ChainScope(this, expr)) {
                        let typeNode = ParseType()
                        expr.isType = typeNode
                        expr.end = typeNode.end
                    }
                    lhs = expr
                } else {
                    let expr = AsExpr()
                    expr.leftExpr = lhs
                    expr.asPos = op.Begin()
                    expr.begin = lhs.begin
                    try (cs = ChainScope(this, expr)) {
                        let typeNode = ParseType()
                        expr.asType = typeNode
                        expr.end = typeNode.end
                    }
                    lhs = expr
                }
                continue
            }
            let node: Expr = if (IsAssignment(op.kind)) {
                let expr = AssignExpr()
                expr.leftValue = lhs
                expr.op = op.kind
                expr.assignPos = op.Begin()
                expr.isCompound = op.kind != TokenKind.ASSIGN
                expr.begin = lhs.begin
                expr.hasQuestSuffix = lhs.hasQuestSuffix
                expr
            } else if (op.kind == TokenKind.RANGEOP || op.kind == TokenKind.CLOSEDRANGEOP) {
                let expr = RangeExpr()
                expr.startExpr = lhs
                expr.rangePos = op.Begin()
                expr.isClosed = op.kind == TokenKind.CLOSEDRANGEOP
                expr.begin = lhs.begin
                expr
            } else {
                let expr = BinaryExpr()
                expr.leftExpr = lhs
                expr.op = op.kind
                expr.operatorPos = op.Begin()
                expr.begin = lhs.begin
                expr
            }
            try (cs = ChainScope(this, node)) {
                var rhs = ParseUnaryExpr(ek)
                var nextOp = Peek()
                if (let Some(nextCombined) <- LookupSeenCombinator()) {
                    nextOp = nextCombined
                }
                let nextPrec = Precedence(nextOp.kind)
                if (prec < nextPrec) {
                    rhs = ParseExprRhsWithPre(prec + 1, rhs, ek, op)
                } else if (prec == nextPrec && (nextOp.kind == TokenKind.COALESCING || nextOp.kind == TokenKind.EXP)) {
                    rhs = ParseExprRhsWithPre(prec, rhs, ek, op)
                } else if (prec == nextPrec && IsNoneAssociative(nextOp.kind) && !rhs.isBroken) {
                    DiagNoneAssociativeOp(op, nextOp)
                    rhs.isBroken = true
                }
                if (!CheckMacroExprRules(op, Token(TokenKind.DOT), rhs)) {
                    rhs.isBroken = true
                    node.isBroken = true
                }
                if (let Some(assign) <- (node as AssignExpr)) {
                    assign.rightExpr = rhs
                    assign.end = rhs.end
                    if (op.kind == TokenKind.ASSIGN) {
                        CheckWildcardInExpr(rhs)
                    }
                    assign.isBroken = assign.isBroken || rhs.isBroken
                } else if (let Some(range) <- (node as RangeExpr)) {
                    range.stopExpr = rhs
                    range.end = rhs.end
                    range.isBroken = range.isBroken || rhs.isBroken
                    if (Skip(TokenKind.COLON)) {
                        range.colonPos = lastToken.Begin()
                        let dot2 = ".."
                        var preT = Token(TokenKind.RANGEOP, dot2, range.rangePos, range.rangePos + dot2.size)
                        preT.kind = if (range.isClosed) { TokenKind.CLOSEDRANGEOP } else { preT.kind }
                        let op = if (range.isClosed) { "..=" } else { preT.Value() }
                        preT.SetValuePos(op, preT.Begin(), preT.Begin() + op.size)
                        range.stepExpr = ParseExprWithPrevious(preT, ExprKind.ALL)
                        if (let Some(step) <- range.stepExpr) {
                            range.end = step.end
                        }
                    }
                } else if (let Some(binary) <- (node as BinaryExpr)) {
                    binary.rightExpr = rhs
                    binary.end = rhs.end
                    binary.isBroken = binary.isBroken || rhs.isBroken
                }
            }
            if (let Some(assign) <- (node as AssignExpr)) {
                if (assign.hasQuestSuffix) {
                    let chain = OptionalChainExpr()
                    chain.expr = assign
                    chain.begin = assign.begin
                    chain.end = assign.end
                    chain.hasQuestSuffix = true
                    lhs = chain
                    continue
                }
            }
            lhs = node
        }
        return lhs
    }

    private func ParseIndexAccess(): Expr {
        if (IsAssignment(Peek().kind)) {
            ParseDiagnoseRefactor(
                DiagKindRefactor.parse_expected_expression, lastToken.End(), lastToken.Value(), Peek().Value()).Emit()
            ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RSQUARE], targetTokenConsumed: false)
            return InvalidExpr(Peek().Begin())
        }
        let ret = RangeExpr()
        ret.begin = Peek().Begin()
        var hasFirstExpr = false
        if (!Seeing(TokenKind.RANGEOP) && !Seeing(TokenKind.CLOSEDRANGEOP)) {
            ret.startExpr = ParseExprWithPrevious(Token(TokenKind.RANGEOP), ExprKind.INDEX_EXPR)
            hasFirstExpr = true
        }
        if (!Seeing(TokenKind.RANGEOP) && !Seeing(TokenKind.CLOSEDRANGEOP)) {
            if (let Some(first) <- ret.startExpr) {
                return ParseExprWithPrevious(Token(TokenKind.DOT), first, ExprKind.INDEX_EXPR)
            }
            return InvalidExpr(Peek().Begin())
        }
        ret.isClosed = Peek().kind == TokenKind.CLOSEDRANGEOP
        ret.rangePos = Peek().Begin()
        Next()
        ret.end = lastToken.End()
        if (!Seeing(TokenKind.RSQUARE) && !Seeing(TokenKind.COLON)) {
            ret.stopExpr = ParseExprWithPrevious(Token(TokenKind.RANGEOP), ExprKind.INDEX_EXPR)
            if (let Some(stop) <- ret.stopExpr) {
                ret.end = stop.end
            }
        }
        if (ret.isClosed && ret.stopExpr.isNone()) {
            ParseDiagnoseRefactor(
                DiagKindRefactor.parse_expected_expression, lastToken.End(), lastToken.Value(), Peek().Value()).Emit()
            ret.isBroken = true
        }
        if (Seeing(TokenKind.COLON)) {
            if (!hasFirstExpr || ret.stopExpr.isNone()) {
                DiagUnexpectedColonInRange(ret)
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RSQUARE], targetTokenConsumed: false)
                return ret
            }
            Next()
            ret.colonPos = lastToken.Begin()
            ret.stepExpr = ParseExprWithPrevious(Token(TokenKind.RANGEOP), ExprKind.INDEX_EXPR)
            if (let Some(step) <- ret.stepExpr) {
                ret.end = step.end
            }
        }
        return ParseExprWithPrevious(Token(TokenKind.DOT), ret, ExprKind.INDEX_EXPR)
    }

    public func Precedence(kind: TokenKind): UInt8 {
        if (IsAssignment(kind)) { return 1u8 }
        return TokenPrecedence(kind)
    }

    public func SeeingExprOperator(): Bool {
        let token = Peek()
        if (newlineSkipped && (token.kind == TokenKind.SUB || token.kind == TokenKind.QUEST)) {
            return false
        }
        if (let Some(_) <- LookupSeenCombinator()) {
            return true
        }
        return Precedence(token.kind) != INVALID_PRECEDENCE
    }

    private func SeeingFakeOperator(): Bool {
        return Seeing(TokenKind.COLON)
    }

    func CheckMacroExprRules(preT: Token, tok: Token, expr: Expr): Bool {
        if (let Some(macroExpr) <- (expr as MacroExpandExpr)) {
            if (!MacroInvocationHasExpandedDecl(macroExpr.invocation)) {
                return true
            }
            if (!preT.Begin().IsZero() && !expr.isBroken) {
                DiagInvalidMacroExpandExpr(preT, macroExpr)
                return false
            }
            if (!expr.isBroken) {
                DiagUnrecognizedNodeAfterMacro(tok, macroExpr)
            }
            return false
        }
        return true
    }

    private func MacroInvocationHasExpandedDecl(invocation: AstMacroInvocation): Bool {
        if (let Some(decl) <- invocation.decl) {
            if (let Some(macroDecl) <- (decl as AstMacroExpandDecl)) {
                return MacroInvocationHasExpandedDecl(macroDecl.invocation)
            }
            return true
        }
        return false
    }

    public func IsAssignment(kind: TokenKind): Bool {
        return kind == TokenKind.ASSIGN || kind == TokenKind.ADD_ASSIGN || kind == TokenKind.SUB_ASSIGN ||
            kind == TokenKind.MUL_ASSIGN || kind == TokenKind.EXP_ASSIGN || kind == TokenKind.DIV_ASSIGN ||
            kind == TokenKind.MOD_ASSIGN || kind == TokenKind.AND_ASSIGN || kind == TokenKind.OR_ASSIGN ||
            kind == TokenKind.BITAND_ASSIGN || kind == TokenKind.BITOR_ASSIGN || kind == TokenKind.BITXOR_ASSIGN ||
            kind == TokenKind.LSHIFT_ASSIGN || kind == TokenKind.RSHIFT_ASSIGN
    }

    private func IsNoneAssociative(kind: TokenKind): Bool {
        if (let Some(_) <- NoneAssociativeName(kind)) {
            return true
        }
        return false
    }

    private func NoneAssociativeName(kind: TokenKind): Option<String> {
        if (IsAssignment(kind)) {
            return "assignment"
        }
        let prec = Precedence(kind)
        if (prec == Precedence(TokenKind.RANGEOP)) {
            return "range"
        }
        if (prec == Precedence(TokenKind.EQUAL)) {
            return "equality"
        }
        if (prec == Precedence(TokenKind.LT)) {
            return "comparison"
        }
        return None
    }

    private func CheckLeftExpression(base: Expr, tok: Token): Unit {
        if (!IsLeftValueExpression(base, tok) && !base.isBroken) {
            DiagInvalidLeftHandExpr(base, tok)
            base.isBroken = true
        }
        if (base.astKind == ASTKind.TUPLE_LIT && tok.kind != TokenKind.ASSIGN) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_cannot_operator_a_tuple, tok, tok.Value()).Emit()
        }
    }

    private func CheckWildcardInExpr(root: Expr): Unit {
        CheckWildcardInExprNode(root)
    }

    private func CheckWildcardInExprNode(node: Node): Unit {
        if (node.astKind == ASTKind.MATCH_CASE_OTHER) {
            return
        }
        if (let Some(assign) <- (node as AssignExpr)) {
            if (assign.op == TokenKind.ASSIGN) {
                return
            }
        }
        if (node.astKind == ASTKind.WILDCARD_EXPR) {
            if (node.begin.line == Peek().Begin().line && Peek().Begin().line == lastToken.Begin().line &&
                Peek().kind != TokenKind.SENTINEL) {
                ConsumeUntilAny(
                    [TokenKind.NL, TokenKind.RPAREN, TokenKind.COMMA, TokenKind.RCURL],
                    targetTokenConsumed: false)
            }
            let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_expected_found, node, "_ wildcard")
            builder.AddMainHintArguments("expression", "wildcard")
            builder.Emit()
            node.isBroken = true
            return
        }
        for (child in node.Children()) {
            CheckWildcardInExprNode(child)
        }
    }

    private func IsAssignmentExpressionRoot(expr: Expr): Bool {
        if (expr.astKind == ASTKind.ASSIGN_EXPR) {
            return true
        }
        if (expr.astKind == ASTKind.OPTIONAL_CHAIN_EXPR) {
            if (let Some(chain) <- (expr as OptionalChainExpr)) {
                if (let Some(child) <- chain.expr) {
                    return IsAssignmentExpressionRoot(child)
                }
            }
        }
        return false
    }

    private func IsLeftValueExpression(expr: Expr, tok: Token): Bool {
        if (expr.astKind == ASTKind.REF_EXPR || expr.astKind == ASTKind.WILDCARD_EXPR ||
            expr.astKind == ASTKind.OPTIONAL_CHAIN_EXPR) {
            return true
        }
        if (expr.astKind == ASTKind.TUPLE_LIT) {
            if (let Some(tuple) <- (expr as TupleLit)) {
                for (child in tuple.children) {
                    if (!IsLeftValueExpression(child, tok) && !child.isBroken) {
                        DiagInvalidLeftHandExpr(child, tok)
                    }
                }
            }
            return true
        }
        if (expr.astKind == ASTKind.MEMBER_ACCESS) {
            if (let Some(member) <- (expr as MemberAccess)) {
                return IsLeftAuxExpressionOption(member.baseExpr, tok)
            }
            return false
        }
        if (expr.astKind == ASTKind.SUBSCRIPT_EXPR) {
            if (let Some(subscript) <- (expr as SubscriptExpr)) {
                return IsLeftAuxExpressionOption(subscript.baseExpr, tok)
            }
            return false
        }
        return false
    }

    private func IsLeftAuxExpressionOption(expr: Option<Expr>, tok: Token): Bool {
        if (let Some(base) <- expr) {
            return IsLeftAuxExpression(base, tok)
        }
        return false
    }

    private func IsLeftAuxExpression(expr: Expr, tok: Token): Bool {
        if (expr.astKind == ASTKind.REF_EXPR || expr.astKind == ASTKind.PRIMITIVE_TYPE_EXPR) {
            return true
        }
        if (expr.astKind == ASTKind.OPTIONAL_EXPR) {
            if (let Some(optional) <- (expr as OptionalExpr)) {
                return IsLeftAuxExpressionOption(optional.baseExpr, tok)
            }
            return false
        }
        if (expr.astKind == ASTKind.MEMBER_ACCESS) {
            if (let Some(member) <- (expr as MemberAccess)) {
                return IsLeftAuxExpressionOption(member.baseExpr, tok)
            }
            return false
        }
        if (expr.astKind == ASTKind.CALL_EXPR) {
            if (let Some(call) <- (expr as CallExpr)) {
                return IsLeftAuxExpressionOption(call.baseFunc, tok)
            }
            return false
        }
        if (expr.astKind == ASTKind.SUBSCRIPT_EXPR) {
            if (let Some(subscript) <- (expr as SubscriptExpr)) {
                return IsLeftAuxExpressionOption(subscript.baseExpr, tok)
            }
            return false
        }
        return false
    }

    public func ParseLetPattern(ek: ExprKind): LetPatternDestructor {
        let ret = LetPatternDestructor()
        let letToken = Expect(TokenKind.LET, "expected 'let'")
        let conditionName = if (ExprKindEquals(ek, ExprKind.WHILE_COND_EXPR)) { "while-let" } else { "if-let" }
        ret.begin = letToken.Begin()
        ret.patterns.add(ParsePattern())
        while (Skip(TokenKind.BITOR)) {
            ret.orPos.add(lastToken.Begin())
            ret.patterns.add(ParsePattern())
        }
        if (!SkipBackarrow()) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_backarrow_in_let_cond, Peek(), conditionName,
                ConvertToken(Peek())).Emit()
            ConsumeUntilAny([TokenKind.AND, TokenKind.OR, TokenKind.RPAREN, TokenKind.LET, TokenKind.BACKARROW], targetTokenConsumed: false)
            let invalid = InvalidExpr(Peek().Begin())
            ret.backarrowPos = Peek().Begin()
            ret.initializer = invalid
            ret.end = invalid.end
            ret.isBroken = true
            return ret
        }
        ret.backarrowPos = lastToken.Begin()
        if (AtTerminator()) {
            ParseDiagnoseRefactor(
                DiagKindRefactor.parse_expected_expression, lastToken.End(), lastToken.Value(), Peek().Value()).Emit()
            let invalid = InvalidExpr(Peek().Begin())
            ret.initializer = invalid
            ret.end = invalid.end
            ret.isBroken = true
            return ret
        }
        ret.initializer = ParseExpr(ExprKind.LET_PATTERN)
        if (let Some(expr) <- ret.initializer) {
            ret.end = expr.end
        }
        return ret
    }

    public func ParseFuncArg(): FuncArg {
        let arg = FuncArg()
        let first = Peek()
        if (IsIdentifierOrContextualKeyword(first.kind) &&
            lexer.LookAheadSkipNL(1).size > 0 && lexer.LookAheadSkipNL(1)[0].kind == TokenKind.COLON) {
            arg.name = ParseIdentifierFromToken(first)
            Next()
            arg.colonPos = Expect(TokenKind.COLON, "expected ':' after argument name").Begin()
        } else if (Skip(TokenKind.INOUT)) {
            arg.withInout = true
            arg.inoutPos = lastToken.Begin()
        }
        arg.expr = ParseExpr(ExprKind.EXPR_IN_CALLSUFFIX)
        arg.begin = first.Begin()
        MarkEndFromLast(arg)
        return arg
    }

    public func ParseIfAvailable(): IfAvailableExpr {
        let _ = Skip(TokenKind.AT)
        let begin = lastToken.Begin()
        let _ = Skip(TokenKind.IDENTIFIER)

        var bad = false
        var lparenPos = INVALID_POSITION
        var lparenSkipped = false
        if (Skip(TokenKind.LPAREN)) {
            lparenPos = lastToken.Begin()
            lparenSkipped = true
        } else {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character, lookahead.Begin(), "(", lookahead.Value()).Emit()
            bad = true
        }
        let arg = ParseFuncArg()
        if (arg.name.Empty()) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_ifavailable_arg_no_name, lookahead).Emit()
            bad = true
        }
        if (!Skip(TokenKind.COMMA)) {
            Next()
            let firstCommaBuilder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character,
                lastToken.Begin(), "','", "'" + lastToken.Value() + "'")
            firstCommaBuilder.AddMainHintArguments("','")
            firstCommaBuilder.Emit()
            let missingFirstComma = IfAvailableExpr()
            missingFirstComma.SetArg(arg)
            missingFirstComma.begin = begin
            missingFirstComma.EnableAttr(Attribute.IS_BROKEN)
            missingFirstComma.end = lastToken.End()
            ConsumeUntil(TokenKind.RPAREN)
            return missingFirstComma
        }

        let firstLambdaExpr = ParseExpr()
        if (let Some(lambda) <- (firstLambdaExpr as LambdaExpr)) {
            let _ = lambda
        } else {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_ifavailable_not_lambda, firstLambdaExpr).Emit()
            bad = true
        }

        if (!Skip(TokenKind.COMMA)) {
            Next()
            let secondCommaBuilder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_character,
                lastToken.Begin(), "','", "'" + lastToken.Value() + "'")
            secondCommaBuilder.AddMainHintArguments("','")
            secondCommaBuilder.Emit()
            let missingSecondComma = IfAvailableExpr()
            missingSecondComma.SetArg(arg)
            if (let Some(lambda) <- (firstLambdaExpr as LambdaExpr)) {
                missingSecondComma.SetLambda1(lambda)
            }
            missingSecondComma.begin = begin
            missingSecondComma.EnableAttr(Attribute.IS_BROKEN)
            missingSecondComma.end = lastToken.End()
            ConsumeUntil(TokenKind.RPAREN)
            return missingSecondComma
        }
        let secondLambdaExpr = ParseExpr()
        if (let Some(lambda) <- (secondLambdaExpr as LambdaExpr)) {
            let _ = lambda
        } else {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_ifavailable_not_lambda, secondLambdaExpr).Emit()
            bad = true
        }
        let parsedIfAvailable = IfAvailableExpr()
        parsedIfAvailable.SetArg(arg)
        if (let Some(lambda) <- (firstLambdaExpr as LambdaExpr)) {
            parsedIfAvailable.SetLambda1(lambda)
        }
        if (let Some(lambda) <- (secondLambdaExpr as LambdaExpr)) {
            parsedIfAvailable.SetLambda2(lambda)
        }
        parsedIfAvailable.begin = begin
        if (!Skip(TokenKind.RPAREN)) {
            if (lparenSkipped) {
                let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_right_delimiter,
                    lookahead.Begin(), "(")
                builder.AddMainHintArguments(")")
                builder.AddHint(lparenPos, arguments: ["("])
                builder.Emit()
            }
            bad = true
        }
        if (bad) {
            parsedIfAvailable.EnableAttr(Attribute.IS_BROKEN)
        }
        parsedIfAvailable.end = lastToken.End()
        return parsedIfAvailable
    }

    public func ParseUnsafeBlock(): Expr {
        let unsafeToken = Expect(TokenKind.UNSAFE, "expected 'unsafe'")
        if (!Seeing(TokenKind.LCURL)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, unsafeToken, ConvertToken(Peek())).Emit()
            return InvalidExpr(unsafeToken.Begin())
        }
        let block = ParseBlock(ScopeKind.FUNC_BODY)
        block.EnableAttr(Attribute.UNSAFE)
        SetUnsafe(block)
        block.unsafePos = unsafeToken.Begin()
        block.begin = unsafeToken.Begin()
        return block
    }

    public func ParseBlock(): Block {
        return ParseBlock(ScopeKind.UNKNOWN_SCOPE)
    }

    public func ParseExpressionOrDeclarations(scopeKind: ScopeKind): Block {
        let result = Block()
        result.begin = lastToken.Begin()
        result.leftCurlPos = lastToken.Begin()
        try (cs = ChainScope(this, result)) {
            SkipBlank(TokenKind.SEMI)
            while (true) {
                let hasNLorSEMI = SkipNLOrSemi()
                if (Skip(TokenKind.RCURL)) {
                    result.rightCurlPos = lastToken.Begin()
                    break
                }
                if (DetectPrematureEnd()) {
                    var resPos = result.begin
                    let toLambdaLen: Int64 = 3
                    if (chainedAST.size >= toLambdaLen &&
                        chainedAST[chainedAST.size - toLambdaLen].astKind == ASTKind.LAMBDA_EXPR) {
                        let le = (chainedAST[chainedAST.size - toLambdaLen] as LambdaExpr).getOrThrow()
                        resPos = le.begin
                    }
                    DiagExpectedRightDelimiter("{", resPos)
                    break
                }
                if (!result.body.isEmpty() && !hasNLorSEMI) {
                    if (DiagForBlock(result)) {
                        result.end = lookahead.End()
                        return result
                    }
                    ConsumeUntilDeclOrNL(TokenKind.RCURL)
                    SkipBlank(TokenKind.NL)
                }
                if (SeeingMacroCallDecl() || SeeingDecl() || SeeingExpr()) {
                    let node = ParseExprOrDecl(scopeKind)
                    result.body.add(node)
                } else {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_expr_or_decl_in, lookahead,
                        ConvertToken(lookahead)).Emit()
                    ConsumeUntilAny([TokenKind.RCURL, TokenKind.NL], targetTokenConsumed: false)
                }
            }
            if (Seeing(TokenKind.SEMI)) {
                result.hasSemi = true
                result.semiPos = lookahead.Begin()
            }
            result.end = lastToken.End()
        }
        return result
    }

    public func DiagForBlock(block: Block): Bool {
        if (SeeingAny([TokenKind.RPAREN, TokenKind.RSQUARE, TokenKind.GT])) {
            if (CanMatchBracketInStack()) {
                DiagExpectedRightDelimiter("{", block.begin)
                return true
            } else {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_unmatched_right_delimiter, lookahead,
                    lookahead.Value()).Emit()
            }
        } else {
            DiagExpectSemiOrNewline()
        }
        return false
    }

    public func ParseBlock(scopeKind: ScopeKind): Block {
        if (!Skip(TokenKind.LCURL)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_brace, lookahead,
                ConvertToken(lookahead)).Emit()
            let block = Block()
            block.begin = lookahead.Begin()
            block.end = lookahead.Begin()
            block.isBroken = true
            return block
        }
        return ParseExpressionOrDeclarations(scopeKind)
    }

    public func ParseExprOrDecl(scopeKind: ScopeKind): Node {
        if (SeeingKeywordAndOperater()) {
            return ParseExpr()
        }
        if (SeeingMacroCall()) {
            if (curMacroCall.isSome() || enableCustomAnno) {
                if (SeeingIfAvailable()) {
                    return ParseIfAvailable()
                }
                return ParseDecl(scopeKind)
            }
            return ParseExpr()
        } else if (SeeingMacroCallDecl()) {
            return ParseDecl(scopeKind)
        } else if (CheckIfSeeingDecl(scopeKind)) {
            return ParseDecl(scopeKind)
        } else if (SeeingExpr()) {
            return ParseExpr()
        }
        return InvalidExpr(Peek().Begin())
    }

    public func CheckIfSeeingDecl(scopeKind: ScopeKind): Bool {
        if (SeeingIfAvailable()) {
            return false
        }
        return SeeingDecl() || SeeingMacroCallDecl() || SeeingIllegalDeclInBlock() ||
            SeeingPrimaryCtorDecl(scopeKind) || SeeingEnumConstructor(scopeKind)
    }

    public func SeeingIfAvailable(): Bool {
        if (!Seeing(TokenKind.AT)) {
            return false
        }
        let tokens = lexer.LookAheadSkipNL(1)
        return !tokens.isEmpty() && tokens[0].kind == TokenKind.IDENTIFIER && tokens[0].Value() == IF_AVAILABLE
    }

    public func SeeingPrimaryCtorDecl(scopeKind: ScopeKind): Bool {
        if (!ScopeKindEquals(scopeKind, ScopeKind.STRUCT_BODY) && !ScopeKindEquals(scopeKind, ScopeKind.CLASS_BODY)) {
            return false
        }
        return Seeing(TokenKind.INIT) || SeeingPrimaryIdentifier()
    }

    public func SeeingEnumConstructor(scopeKind: ScopeKind): Bool {
        return (Seeing(TokenKind.IDENTIFIER) || SeeingContextualKeyword()) &&
            (ScopeKindEquals(scopeKind, ScopeKind.ENUM_BODY) || ScopeKindEquals(scopeKind, ScopeKind.ENUM_CONSTRUCTOR))
    }

    public func SeeingIllegalDeclInBlock(): Bool {
        return SeeingAny([TokenKind.CLASS, TokenKind.INIT, TokenKind.INTERFACE, TokenKind.EXTEND, TokenKind.STRUCT,
            TokenKind.PROP]) || SeeingImport()
    }

    public func ParseIfExpr(): IfExpr {
        let ret = IfExpr()
        let token = Expect(TokenKind.IF, "expected 'if'")
        ret.ifPos = token.Begin()
        ret.begin = token.Begin()
        ret.leftParenPos = Expect(TokenKind.LPAREN, "expected '(' after if").Begin()
        ret.condExpr = ParseExpr(ExprKind.IF_COND_EXPR)
        if (let Some(cond) <- ret.condExpr) {
            CheckCondition(cond)
        }
        ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after if condition").Begin()
        ret.thenBody = ParseBlock(ScopeKind.FUNC_BODY)
        if (Skip(TokenKind.ELSE)) {
            ret.hasElse = true
            ret.elsePos = lastToken.Begin()
            ret.elseBody = if (Seeing(TokenKind.IF)) { ParseIfExpr() } else { ParseBlock(ScopeKind.FUNC_BODY) }
        }
        if (let Some(elseBody) <- ret.elseBody) {
            ret.end = elseBody.end
        } else if (let Some(thenBody) <- ret.thenBody) {
            ret.end = thenBody.end
        }
        return ret
    }

    public func ParseMatchExpr(): MatchExpr {
        let ret = MatchExpr()
        let token = Expect(TokenKind.MATCH, "expected 'match'")
        ret.begin = token.Begin()
        try (cs = ChainScope(this, ret)) {
            if (Seeing([TokenKind.LCURL, TokenKind.CASE])) {
                ParseMatchNoSelector(ret)
                return ret
            }
            ret.matchMode = true
            if (Skip(TokenKind.LPAREN)) {
                ret.leftParenPos = lastToken.Begin()
                if (!Seeing(TokenKind.RPAREN)) {
                    ret.selector = ParseExpr()
                }
                ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after match selector").Begin()
            }
            ret.leftCurlPos = Expect(TokenKind.LCURL, "expected '{' for match body").Begin()
            SkipNLOrSemi()
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
                let matchCase = MatchCase()
                Expect(TokenKind.CASE, "expected 'case'")
                matchCase.begin = lastToken.Begin()
                try (caseScope = ChainScope(this, matchCase)) {
                    while (!Seeing(TokenKind.END) && !SeeingDoubleArrow() && !Seeing(TokenKind.WHERE)) {
                        matchCase.patterns.add(ParsePattern())
                        if (Skip(TokenKind.BITOR)) {
                            matchCase.bitOrPosVector.add(lastToken.Begin())
                        } else {
                            break
                        }
                    }
                    if (Skip(TokenKind.WHERE)) {
                        matchCase.wherePos = lastToken.Begin()
                        matchCase.patternGuard = ParseExpr()
                    }
                    if (!SkipDoubleArrow()) {
                        let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_double_arrow_in_case, Peek(),
                            ConvertToken(Peek()))
                        builder.AddHint(MakeRange(matchCase.begin, "case"))
                        builder.Emit()
                    }
                    matchCase.arrowPos = lastToken.Begin()
                    let block = ParseExprOrDeclsInMatchCase()
                    matchCase.exprOrDecls = block
                    matchCase.end = block.end
                    ret.matchCases.add(matchCase)
                    SkipNLOrSemi()
                }
            }
            ret.rightCurlPos = Expect(TokenKind.RCURL, "expected '}' after match").Begin()
            ret.end = ret.rightCurlPos + 1
        }
        return ret
    }

    public func ParseMatchNoSelector(ret: MatchExpr): Unit {
        ret.matchMode = false
        ret.leftCurlPos = Expect(TokenKind.LCURL, "expected '{' for match body").Begin()
        SkipNLOrSemi()
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
            if (!Skip(TokenKind.CASE)) {
                let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_case, Peek(), ConvertToken(Peek()))
                builder.AddHint(MakeRange(ret.begin, "match"))
                Next()
                SkipNLOrSemi()
                builder.Emit()
                continue
            }
            let matchCase = MatchCaseOther()
            matchCase.begin = lastToken.Begin()
            if (Skip(TokenKind.WILDCARD)) {
                matchCase.matchExpr = WildcardExpr(lastToken.Begin())
            } else {
                matchCase.matchExpr = ParseExpr()
            }
            if (!SkipDoubleArrow()) {
                let builder = ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_double_arrow_in_case, Peek(),
                    ConvertToken(Peek()))
                builder.AddHint(MakeRange(matchCase.begin, "case"))
                builder.Emit()
            }
            matchCase.arrowPos = lastToken.Begin()
            let block = ParseExprOrDeclsInMatchCase()
            matchCase.exprOrDecls = block
            matchCase.end = block.end
            ret.matchCaseOthers.add(matchCase)
            SkipNLOrSemi()
        }
        ret.rightCurlPos = Expect(TokenKind.RCURL, "expected '}' after match").Begin()
        ret.end = ret.rightCurlPos + 1
    }

    public func ParseExprOrDeclsInMatchCase(): Block {
        let exprOrDecls = Block()
        exprOrDecls.begin = lookahead.Begin()
        var flag = false
        var hasSemi = false
        while (!SeeingAny([TokenKind.CASE, TokenKind.RCURL])) {
            if (flag && !newlineSkipped && !hasSemi && !exprOrDecls.TestAttr(Attribute.HAS_BROKEN)) {
                DiagExpectSemiOrNewline()
            }
            flag = true
            SkipBlank(TokenKind.SEMI)
            if (DetectPrematureEnd()) {
                break
            }
            if (SeeingMacroCallDecl() || SeeingDecl() || SeeingExpr()) {
                let node = ParseExprOrDecl(ScopeKind.FUNC_BODY)
                if (exprOrDecls.body.isEmpty()) {
                    exprOrDecls.begin = node.begin
                }
                exprOrDecls.body.add(node)
            } else {
                DiagMatchCaseExpectedExprOrDecl()
                exprOrDecls.EnableAttr(Attribute.HAS_BROKEN)
                ConsumeUntilAny([TokenKind.CASE, TokenKind.RCURL, TokenKind.NL], targetTokenConsumed: false)
            }
            hasSemi = Seeing(TokenKind.SEMI)
            SkipBlank(TokenKind.SEMI)
        }
        exprOrDecls.end = lastToken.End()
        return exprOrDecls
    }

    public func ParseTryExpr(): TryExpr {
        let ret = TryExpr()
        let token = Expect(TokenKind.TRY, "expected 'try'")
        ret.tryPos = token.Begin()
        ret.begin = token.Begin()
        if (Seeing(TokenKind.LCURL)) {
            ret.tryBlock = ParseBlock(ScopeKind.FUNC_BODY)
        } else if (Seeing(TokenKind.LPAREN)) {
            ParseTryWithResource(ret, ScopeKind.FUNC_BODY)
        } else {
            DiagExpectCharacter("'{' or '('", noteStr: "try expression must have block or resources")
            ret.isBroken = true
        }
        while (Seeing(TokenKind.HANDLE) || Seeing(TokenKind.CATCH)) {
            if (Skip(TokenKind.HANDLE)) {
                ParseHandleBlock(ret)
            } else if (Skip(TokenKind.CATCH)) {
                ParseCatchBlock(ret)
            }
        }
        if (Skip(TokenKind.FINALLY)) {
            ret.finallyPos = lastToken.Begin()
            ret.finallyBlock = ParseBlock(ScopeKind.FUNC_BODY)
        }
        if (let Some(finallyBlock) <- ret.finallyBlock) {
            ret.end = finallyBlock.end
        } else if (!ret.handlers.isEmpty()) {
            if (let Some(block) <- ret.handlers[ret.handlers.size - 1].block) {
                ret.end = block.end
            }
        } else if (!ret.catchBlocks.isEmpty()) {
            ret.end = ret.catchBlocks[ret.catchBlocks.size - 1].end
        } else if (let Some(tryBlock) <- ret.tryBlock) {
            ret.end = tryBlock.end
        } else {
            ret.end = token.End()
        }
        return ret
    }

    public func ParseTryWithResource(ret: TryExpr, scopeKind: ScopeKind): Unit {
        ret.lParen = Expect(TokenKind.LPAREN, "expected '(' after try").Begin()
        let resourceNames = ArrayList<(String, Position)>()
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
            let decl = AstVarDecl()
            try (cs = ChainScope(this, decl)) {
                decl.isVar = false
                decl.isResourceVar = true
                decl.identifier = ExpectIdentifierWithPos(decl)
                decl.begin = decl.identifier.Begin()
                for (nameAndPos in resourceNames) {
                    if (nameAndPos[0] == decl.identifier.Val()) {
                        DiagRedefinedResourceName((decl.identifier.Val(), decl.identifier.Begin()), nameAndPos)
                    }
                }
                resourceNames.add((decl.identifier.Val(), decl.identifier.Begin()))
                if (Skip(TokenKind.COLON)) {
                    decl.colonPos = lastToken.Begin()
                    decl.typeNode = ParseType()
                }
                if (Skip(TokenKind.ASSIGN)) {
                    decl.assignPos = lastToken.Begin()
                    decl.initializer = ParseExpr(ExprKind.VAR_INIT)
                } else {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_assignment, Peek(),
                        ConvertToken(Peek())).Emit()
                }
                decl.end = if (let Some(expr) <- decl.initializer) {
                    expr.end
                } else if (let Some(ty) <- decl.typeNode) {
                    ty.end
                } else {
                    decl.identifier.End()
                }
                ret.resourceSpec.add(decl)
            }
            if (Skip(TokenKind.COMMA)) {
                ret.resourceSpecCommaPos.add(lastToken.Begin())
            } else {
                break
            }
        }
        ret.rParen = Expect(TokenKind.RPAREN, "expected ')' after try resources").Begin()
        ret.isDesugaredFromTryWithResources = true
        ret.tryBlock = ParseBlock(scopeKind)
    }

    public func ParseCatchBlock(ret: TryExpr): Unit {
        ret.catchPosVector.add(lastToken.Begin())
        var leftParenPos = INVALID_POSITION
        if (Skip(TokenKind.LPAREN)) {
            leftParenPos = lastToken.Begin()
            ret.catchLParenPosVector.add(leftParenPos)
        } else {
            DiagExpectedLeftParenAfter(ret.catchPosVector[ret.catchPosVector.size - 1], "catch")
            ret.isBroken = true
        }
        ret.catchPatterns.add(ParseExceptTypePattern())
        if (Skip(TokenKind.RPAREN)) {
            ret.catchRParenPosVector.add(lastToken.Begin())
        } else if (!leftParenPos.IsZero()) {
            DiagExpectedRightDelimiter("(", leftParenPos)
            ret.isBroken = true
        }
        ret.catchBlocks.add(ParseBlock(ScopeKind.FUNC_BODY))
    }

    public func ParseHandleBlock(ret: TryExpr): Unit {
        let handler = Handler()
        handler.pos = lastToken.Begin()
        var leftParenPos = INVALID_POSITION
        if (!Skip(TokenKind.LPAREN)) {
            DiagExpectedLeftParenAfter(handler.pos, "handle")
            ret.isBroken = true
        } else {
            leftParenPos = lastToken.Begin()
        }
        handler.commandPattern = ParseCommandTypePattern()
        if (!Skip(TokenKind.RPAREN) && !leftParenPos.IsZero()) {
            DiagExpectedRightDelimiter("(", leftParenPos)
            ret.isBroken = true
        }
        handler.block = ParseBlock(ScopeKind.FUNC_BODY)
        ret.handlers.add(handler)
    }

    public func ParseExceptTypePattern(): Pattern {
        if (Skip(TokenKind.WILDCARD)) {
            let wildcard = WildcardPattern(lastToken.Begin())
            if (!Skip(TokenKind.COLON)) {
                return wildcard
            }
            let pattern = ExceptTypePattern()
            pattern.pattern = wildcard
            pattern.patternPos = wildcard.begin
            pattern.colonPos = lastToken.Begin()
            pattern.begin = wildcard.begin
            do {
                if (lastToken.kind == TokenKind.BITOR) {
                    pattern.bitOrPosVector.add(lastToken.Begin())
                }
                pattern.types.add(ParseType())
            } while (Skip(TokenKind.BITOR))
            if (!pattern.types.isEmpty()) {
                pattern.end = pattern.types[pattern.types.size - 1].end
            }
            return pattern
        }
        if (SeeingIdentifierLike()) {
            let token = Peek()
            let identifier = ParseIdentifierFromToken(token)
            Next()
            let varPattern = VarPattern(identifier, false)
            let pattern = ExceptTypePattern()
            pattern.pattern = varPattern
            pattern.patternPos = token.Begin()
            pattern.begin = token.Begin()
            if (Skip(TokenKind.COLON)) {
                pattern.colonPos = lastToken.Begin()
            } else {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_colon_in_catch_pattern, Peek(),
                    ConvertToken(Peek())).Emit()
                pattern.isBroken = true
            }
            do {
                if (lastToken.kind == TokenKind.BITOR) {
                    pattern.bitOrPosVector.add(lastToken.Begin())
                }
                pattern.types.add(ParseType())
            } while (Skip(TokenKind.BITOR))
            if (!pattern.types.isEmpty()) {
                pattern.end = pattern.types[pattern.types.size - 1].end
            }
            return pattern
        }
        let token = Peek()
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_wildcard_or_exception_pattern, token,
            ConvertToken(token)).Emit()
        Next()
        return InvalidPattern(token.Begin())
    }

    public func ParseCommandTypePattern(): Pattern {
        if (Skip(TokenKind.WILDCARD)) {
            let wildcard = WildcardPattern(lastToken.Begin())
            if (!Skip(TokenKind.COLON)) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_colon_in_effect_pattern, Peek(),
                    ConvertToken(Peek())).Emit()
                return InvalidPattern(wildcard.begin)
            }
            let pattern = CommandTypePattern()
            pattern.pattern = wildcard
            pattern.patternPos = wildcard.begin
            pattern.colonPos = lastToken.Begin()
            pattern.begin = wildcard.begin
            do {
                if (lastToken.kind == TokenKind.BITOR) {
                    pattern.bitOrPosVector.add(lastToken.Begin())
                }
                pattern.types.add(ParseType())
            } while (Skip(TokenKind.BITOR))
            if (!pattern.types.isEmpty()) {
                pattern.end = pattern.types[pattern.types.size - 1].end
            }
            return pattern
        }
        if (SeeingIdentifierLike()) {
            let token = Peek()
            let identifier = ParseIdentifierFromToken(token)
            Next()
            let varPattern = VarPattern(identifier, false)
            let pattern = CommandTypePattern()
            pattern.pattern = varPattern
            pattern.patternPos = token.Begin()
            pattern.begin = token.Begin()
            if (Skip(TokenKind.COLON)) {
                pattern.colonPos = lastToken.Begin()
            } else {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_colon_in_effect_pattern, Peek(),
                    ConvertToken(Peek())).Emit()
                pattern.isBroken = true
            }
            do {
                if (lastToken.kind == TokenKind.BITOR) {
                    pattern.bitOrPosVector.add(lastToken.Begin())
                }
                pattern.types.add(ParseType())
            } while (Skip(TokenKind.BITOR))
            if (!pattern.types.isEmpty()) {
                pattern.end = pattern.types[pattern.types.size - 1].end
            }
            return pattern
        }
        let token = Peek()
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_wildcard_or_effect_pattern, token, ConvertToken(token)).Emit()
        Next()
        return InvalidPattern(token.Begin())
    }

    public func ParseWhileExpr(): WhileExpr {
        let ret = WhileExpr()
        let token = Expect(TokenKind.WHILE, "expected 'while'")
        ret.whilePos = token.Begin()
        ret.begin = token.Begin()
        Expect(TokenKind.LPAREN, "expected '(' after while")
        ret.condExpr = ParseExpr(ExprKind.WHILE_COND_EXPR)
        if (let Some(cond) <- ret.condExpr) {
            CheckCondition(cond)
        }
        Expect(TokenKind.RPAREN, "expected ')' after while condition")
        ret.body = ParseBlock(ScopeKind.FUNC_BODY)
        if (let Some(body) <- ret.body) { ret.end = body.end }
        return ret
    }

    public func ParseDoWhileExpr(): DoWhileExpr {
        let ret = DoWhileExpr()
        let token = Expect(TokenKind.DO, "expected 'do'")
        ret.doPos = token.Begin()
        ret.begin = token.Begin()
        ret.body = ParseBlock(ScopeKind.FUNC_BODY)
        let whileTok = Expect(TokenKind.WHILE, "expected 'while' after do body")
        ret.whilePos = whileTok.Begin()
        Expect(TokenKind.LPAREN, "expected '(' after while")
        ret.condExpr = ParseExpr(ExprKind.WHILE_COND_EXPR)
        let right = Expect(TokenKind.RPAREN, "expected ')' after condition")
        ret.end = right.End()
        return ret
    }

    public func ParseForInExpr(): ForInExpr {
        let ret = ForInExpr()
        let token = Expect(TokenKind.FOR, "expected 'for'")
        ret.begin = token.Begin()
        ret.leftParenPos = Expect(TokenKind.LPAREN, "expected '(' after for").Begin()
        ret.pattern = ParsePattern()
        ret.inPos = Expect(TokenKind.IN, "expected 'in' in for expression").Begin()
        ret.inExpression = ParseExpr()
        if (Skip(TokenKind.WHERE)) {
            ret.wherePos = lastToken.Begin()
            ret.patternGuard = ParseExpr()
        }
        ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after for-in").Begin()
        ret.body = ParseBlock(ScopeKind.FUNC_BODY)
        if (let Some(body) <- ret.body) { ret.end = body.end }
        return ret
    }

    public func ParseReturnExpr(): ReturnExpr {
        let ret = ReturnExpr()
        let token = Expect(TokenKind.RETURN, "expected 'return'")
        ret.returnPos = token.Begin()
        ret.begin = token.Begin()
        if ((SeeingDecl() && !SeeingContextualKeyword()) || AtTerminator() || Seeing(TokenKind.CASE) ||
            SeeingDoubleArrow()) {
            let unitLit = LitConstExpr(LitConstKind.UNIT, "()")
            unitLit.begin = lastToken.End()
            unitLit.end = unitLit.begin
            unitLit.EnableAttr(Attribute.COMPILER_ADD)
            ret.expr = unitLit
            if (Seeing(TokenKind.SEMI)) {
                ret.hasSemi = true
                ret.semiPos = Peek().Begin()
            }
        } else {
            ret.expr = ParseExpr()
        }
        ret.end = ret.expr.getOrThrow().end
        return ret
    }

    public func ParseThrowExpr(): ThrowExpr {
        let ret = ThrowExpr()
        let token = Expect(TokenKind.THROW, "expected 'throw'")
        ret.throwPos = token.Begin()
        ret.begin = token.Begin()
        if (!AtTerminator()) { ret.expr = ParseExpr() }
        ret.end = if (let Some(expr) <- ret.expr) { expr.end } else { token.End() }
        return ret
    }

    public func ParsePerformExpr(): PerformExpr {
        let ret = PerformExpr()
        let token = Expect(TokenKind.PERFORM, "expected 'perform'")
        ret.performPos = token.Begin()
        ret.begin = token.Begin()
        ret.expr = ParseExpr()
        ret.end = if (let Some(expr) <- ret.expr) { expr.end } else { token.End() }
        return ret
    }

    public func ParseResumeExpr(): ResumeExpr {
        let ret = ResumeExpr()
        let token = Expect(TokenKind.RESUME, "expected 'resume'")
        ret.resumePos = token.Begin()
        ret.begin = token.Begin()
        ret.end = token.End()
        if (Skip(TokenKind.WITH)) {
            ret.withPos = lastToken.Begin()
            ret.withExpr = ParseExpr()
            if (let Some(expr) <- ret.withExpr) { ret.end = expr.end }
        } else if (Skip(TokenKind.THROWING)) {
            ret.throwingPos = lastToken.Begin()
            ret.throwingExpr = ParseExpr()
            if (let Some(expr) <- ret.throwingExpr) { ret.end = expr.end }
        }
        return ret
    }

    public func ParseSpawnExpr(): SpawnExpr {
        let ret = SpawnExpr()
        let token = Expect(TokenKind.SPAWN, "expected 'spawn'")
        ret.spawnPos = token.Begin()
        ret.begin = token.Begin()
        if (Seeing(TokenKind.LPAREN)) {
            if (newlineSkipped) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_newline_not_allowed_between_spawn_and_argument,
                    firstNLPosition).Emit()
            }
            if (Skip(TokenKind.LPAREN)) {
                ret.leftParenPos = lastToken.Begin()
                ret.arg = ParseExpr()
            }
            ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after spawn argument").Begin()
        }
        if (SeeingAnnotationLambdaExpr()) {
            ret.task = ParseAnnotationLambdaExpr(true)
        } else if (Seeing(TokenKind.LCURL)) {
            ret.task = ParseLambdaExprWithTrailingClosure()
        } else {
            DiagExpectedExpression()
            let invalid = InvalidExpr(Peek().Begin())
            ret.task = invalid
            ret.isBroken = true
        }
        if (let Some(task) <- ret.task) {
            if (task.astKind != ASTKind.LAMBDA_EXPR) {
                ret.isBroken = true
            }
            if (let Some(lambda) <- (task as LambdaExpr)) {
                let body = lambda.funcBody.getOrThrow()
                if (!body.paramLists[0].params.isEmpty()) {
                    let params = body.paramLists[0].params
                    DiagExpectedNoArgumentsInSpawn(params, ret.begin)
                    ret.isBroken = true
                }
            }
            ret.end = task.end
        }
        return ret
    }

    public func ParseSynchronizedExpr(): SynchronizedExpr {
        let ret = SynchronizedExpr()
        let token = Expect(TokenKind.SYNCHRONIZED, "expected 'synchronized'")
        ret.syncPos = token.Begin()
        ret.begin = token.Begin()
        ret.leftParenPos = Expect(TokenKind.LPAREN, "expected '(' after synchronized").Begin()
        ret.mutex = ParseExpr()
        ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after synchronized expression").Begin()
        ret.body = ParseBlock(ScopeKind.FUNC_BODY)
        if (let Some(body) <- ret.body) { ret.end = body.end }
        return ret
    }

    public func ParseLambdaExprWithTrailingClosure(): LambdaExpr {
        return ParseLambdaExpr(true)
    }

    public func ParseLambdaExpr(): LambdaExpr {
        return ParseLambdaExpr(false)
    }

    private func ParseLambdaFuncParam(): AstFuncParam {
        let param = AstFuncParam()
        try (cs = ChainScope(this, param)) {
            if (Skip(TokenKind.WILDCARD)) {
                param.identifier = SrcIdentifier("_", "_", lastToken.Begin(), lastToken.End(), false)
            } else {
                param.identifier = ExpectIdentifierWithPos(param)
            }
            if (param.identifier.Empty()) {
                param.EnableAttr(Attribute.IS_BROKEN)
                ConsumeUntilAny([TokenKind.DOUBLE_ARROW, TokenKind.COLON, TokenKind.COMMA, TokenKind.NL,
                    TokenKind.SEMI, TokenKind.RCURL], targetTokenConsumed: false)
            }
            param.isVar = false
            param.begin = param.identifier.Begin()
            if (Skip(TokenKind.COLON)) {
                param.colonPos = lastToken.Begin()
                param.typeNode = ParseType()
                if (let Some(typeNode) <- param.typeNode) {
                    param.end = typeNode.end
                }
            } else {
                param.end = param.identifier.End()
            }
        }
        return param
    }

    private func ParseFuncParamListInLambdaExpr(): AstFuncParamList {
        let paramList = AstFuncParamList()
        try (cs = ChainScope(this, paramList)) {
            if (SeeingInvalidParamListInLambdaExpr()) {
                paramList.begin = Peek().Begin()
                paramList.end = Peek().Begin()
                return paramList
            }
            while (!Seeing(TokenKind.END) && !SeeingDoubleArrow()) {
                let param = ParseLambdaFuncParam()
                if (param.TestAttr(Attribute.IS_BROKEN)) {
                    paramList.EnableAttr(Attribute.IS_BROKEN)
                }
                paramList.params.add(param)
                if (Skip(TokenKind.COMMA)) {
                    param.commaPos = lastToken.Begin()
                } else {
                    break
                }
            }
            if (!paramList.params.isEmpty()) {
                paramList.begin = paramList.params[0].begin
                paramList.end = paramList.params[paramList.params.size - 1].end
            }
        }
        return paramList
    }

    public func ParseLambdaExpr(isTailClosure: Bool): LambdaExpr {
        let lambda = LambdaExpr()
        lambda.begin = Peek().Begin()
        try (cs = ChainScope(this, lambda)) {
            let body = AstFuncBody()
            try (bodyScope = ChainScope(this, body)) {
                if (Skip(TokenKind.LCURL)) {
                    let paramList = ParseFuncParamListInLambdaExpr()
                    if (!paramList.params.isEmpty() && !SkipDoubleArrow()) {
                        if (!lambda.TestAttr(Attribute.HAS_BROKEN)) {
                            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_double_arrow_in_lambda, Peek(),
                                ConvertToken(Peek())).Emit()
                        }
                        ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.DOUBLE_ARROW, TokenKind.RCURL],
                            targetTokenConsumed: false)
                        if (!Skip(TokenKind.DOUBLE_ARROW)) {
                            let _ = SkipCombinedDoubleArrow()
                        }
                        lambda.EnableAttr(Attribute.HAS_BROKEN)
                    } else {
                        if (paramList.params.isEmpty() && !isTailClosure) {
                            let hasDoubleArrow = lastToken.kind == TokenKind.DOUBLE_ARROW ||
                                Skip(TokenKind.DOUBLE_ARROW) || SkipCombinedDoubleArrow()
                            let hasWildcard = Seeing([TokenKind.WILDCARD, TokenKind.DOUBLE_ARROW]) ||
                                Seeing([TokenKind.WILDCARD, TokenKind.COMMA]) ||
                                SeeingTokenAndCombinator(TokenKind.WILDCARD, [TokenKind.ASSIGN, TokenKind.GT])
                            if (!hasDoubleArrow && !hasWildcard) {
                                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_double_arrow_in_lambda, Peek(),
                                    ConvertToken(Peek())).Emit()
                            }
                        }
                        if (lastToken.kind == TokenKind.DOUBLE_ARROW || Skip(TokenKind.DOUBLE_ARROW) ||
                            SkipCombinedDoubleArrow()) {
                            body.doubleArrowPos = lastToken.Begin()
                        }
                    }
                    body.begin = lastToken.Begin()
                    body.paramLists.add(paramList)
                    let block = ParseExpressionOrDeclarations(ScopeKind.FUNC_BODY)
                    block.leftCurlPos = lambda.begin
                    body.body = Some(block)
                    body.end = block.end
                    lambda.funcBody = Some(body)
                    lambda.end = block.end
                }
            }
        }
        return lambda
    }

    public func CheckCondition(expr: Expr): Bool {
        if (let Some(paren) <- (expr as ParenExpr)) {
            if (let Some(child) <- paren.expr) {
                return CheckCondition(child)
            }
            return false
        }
        if (expr.astKind == ASTKind.LET_PATTERN_DESTRUCTOR) {
            return true
        }
        if (let Some(binary) <- (expr as BinaryExpr)) {
            var hasSubCondition = false
            if (let Some(left) <- binary.leftExpr) {
                hasSubCondition = CheckCondition(left)
            }
            if (let Some(right) <- binary.rightExpr) {
                hasSubCondition = CheckCondition(right) || hasSubCondition
            }
            if (hasSubCondition && binary.op != TokenKind.AND && binary.op != TokenKind.OR) {
                diag.DiagnoseRefactor(DiagKindRefactor.parse_expected_if_let_andand, binary.operatorPos).Emit()
                binary.isBroken = true
            }
            return hasSubCondition
        }
        return false
    }
}
