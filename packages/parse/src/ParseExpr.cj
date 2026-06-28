package cangjie_compiler::parse

import std.collection.*
import cangjie_compiler::ast.MacroExpandDecl as AstMacroExpandDecl
import cangjie_compiler::ast.FuncBody as AstFuncBody
import cangjie_compiler::ast.FuncParam as AstFuncParam
import cangjie_compiler::ast.FuncParamList as AstFuncParamList
import cangjie_compiler::ast.MacroInvocation as AstMacroInvocation
import cangjie_compiler::ast.VarDecl as AstVarDecl

extend ParserImpl {
    public func ParseExpr(): Expr {
        return ParseExpr(ExprKind.ALL)
    }

    public func ParseExpr(ek: ExprKind): Expr {
        if (ExprKindEquals(ek, ExprKind.UNKNOWN_EXPR) && Seeing(TokenKind.LET)) {
            return ParseLetPattern(ek)
        }
        if (ExprKindEquals(ek, ExprKind.INDEX_EXPR)) {
            let ret = ParseIndexAccess()
            if (!SeeingExprOperator()) {
                CheckWildcardInExpr(ret)
            }
            if (SeeingFakeOperator()) {
                DiagExpectedOperatorOrEnd()
                ConsumeUntilAny([TokenKind.NL])
            }
            return ret
        }
        let left = ParseUnaryExpr(ek)
        let ret = ParseExprRhs(0, left, ek)
        if (ExprKindEquals(ek, ExprKind.VAR_INIT) && IsAssignmentExpressionRoot(ret)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                ret.begin,
                "assignment expression cannot be used as a variable initializer")
            ret.isBroken = true
        }
        if (!SeeingExprOperator() && !ExprKindEquals(ek, ExprKind.EXPR_IN_TUPLE) &&
            !ExprKindEquals(ek, ExprKind.EXPR_IN_IF_COND_TUPLE) &&
            !ExprKindEquals(ek, ExprKind.EXPR_IN_WHILE_COND_TUPLE)) {
            CheckWildcardInExpr(ret)
        }
        if (SeeingFakeOperator()) {
            DiagExpectedOperatorOrEnd()
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
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected expression without newline after unary operator")
            return InvalidExpr(Peek().Begin())
        }
        if (Seeing(TokenKind.NOT) || Seeing(TokenKind.ADD) || Seeing(TokenKind.SUB) || Seeing(TokenKind.BITNOT)) {
            let op = Peek()
            Next()
            let unary = UnaryExpr()
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
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '.', '(', '[', '{', or '?' after '?'")
                Next()
                break
            }
            if (!newlineSkipped && Skip(TokenKind.LPAREN)) {
                let call = CallExpr()
                call.baseFunc = base
                call.leftParenPos = lastToken.Begin()
                call.begin = base.begin
                while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                    call.args.add(ParseFuncArg())
                    if (!Skip(TokenKind.COMMA)) { break }
                }
                call.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after arguments").Begin()
                call.end = call.rightParenPos + 1
                base = call
                continue
            }
            if (Skip(TokenKind.DOT)) {
                let member = MemberAccess()
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
                base = member
                continue
            }
            if (!newlineSkipped && Skip(TokenKind.LSQUARE)) {
                let sub = SubscriptExpr()
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
                sub.rightParenPos = Expect(TokenKind.RSQUARE, "expected ']' after subscript").Begin()
                sub.end = sub.rightParenPos + 1
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
            if (!newlineSkipped && Seeing(TokenKind.LCURL) && (base.astKind == ASTKind.CALL_EXPR ||
                base.astKind == ASTKind.REF_EXPR || base.astKind == ASTKind.MEMBER_ACCESS ||
                base.astKind == ASTKind.OPTIONAL_EXPR || base.astKind == ASTKind.ARRAY_EXPR ||
                base.astKind == ASTKind.MACRO_EXPAND_EXPR)) {
                let trailing = TrailingClosureExpr()
                trailing.expr = base
                trailing.lambda = ParseLambdaExprWithTrailingClosure()
                trailing.begin = base.begin
                if (let Some(lambda) <- trailing.lambda) { trailing.end = lambda.end }
                base = trailing
                continue
            }
            break
        }
        if (hasQuestSuffix) {
            let chain = OptionalChainExpr()
            chain.expr = base
            chain.begin = base.begin
            chain.end = base.end
            base = chain
            base.hasQuestSuffix = true
        }
        return base
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
                let typeNode = ParseType()
                if (op.kind == TokenKind.IS) {
                    let expr = IsExpr()
                    expr.leftExpr = lhs
                    expr.isType = typeNode
                    expr.isPos = op.Begin()
                    expr.begin = lhs.begin
                    expr.end = typeNode.end
                    lhs = expr
                } else {
                    let expr = AsExpr()
                    expr.leftExpr = lhs
                    expr.asType = typeNode
                    expr.asPos = op.Begin()
                    expr.begin = lhs.begin
                    expr.end = typeNode.end
                    lhs = expr
                }
                continue
            }
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
            }
            let node = MakeBinaryExpr(lhs, op, rhs)
            lhs = node
        }
        return lhs
    }

    private func ParseExprWithPrevious(preKind: TokenKind, ek: ExprKind): Expr {
        return ParseExprWithPrevious(preKind, ParseUnaryExpr(ek), ek)
    }

    private func ParseExprWithPrevious(preKind: TokenKind, left: Expr, ek: ExprKind): Expr {
        var lhs = left
        let prePrec = Precedence(preKind)
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
            if (!CheckMacroExprRules(Token(preKind), op, lhs)) {
                lhs.isBroken = true
            }
            if (combinedOperator) {
                SkipAmbiguousToken()
            } else {
                Next()
            }
            if (op.kind == TokenKind.IS || op.kind == TokenKind.AS) {
                let typeNode = ParseType()
                if (op.kind == TokenKind.IS) {
                    let expr = IsExpr()
                    expr.leftExpr = lhs
                    expr.isType = typeNode
                    expr.isPos = op.Begin()
                    expr.begin = lhs.begin
                    expr.end = typeNode.end
                    lhs = expr
                } else {
                    let expr = AsExpr()
                    expr.leftExpr = lhs
                    expr.asType = typeNode
                    expr.asPos = op.Begin()
                    expr.begin = lhs.begin
                    expr.end = typeNode.end
                    lhs = expr
                }
                continue
            }
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
            }
            lhs = MakeBinaryExpr(lhs, op, rhs)
        }
        return lhs
    }

    private func ParseIndexAccess(): Expr {
        if (IsAssignment(Peek().kind)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_TOKEN,
                Peek().Begin(),
                "expected expression in index access")
            ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RSQUARE], targetTokenConsumed: false)
            return InvalidExpr(Peek().Begin())
        }
        let ret = RangeExpr()
        ret.begin = Peek().Begin()
        var hasFirstExpr = false
        if (!Seeing(TokenKind.RANGEOP) && !Seeing(TokenKind.CLOSEDRANGEOP)) {
            ret.startExpr = ParseExprWithPrevious(TokenKind.RANGEOP, ExprKind.INDEX_EXPR)
            hasFirstExpr = true
        }
        if (!Seeing(TokenKind.RANGEOP) && !Seeing(TokenKind.CLOSEDRANGEOP)) {
            if (let Some(first) <- ret.startExpr) {
                return ParseExprWithPrevious(TokenKind.DOT, first, ExprKind.INDEX_EXPR)
            }
            return InvalidExpr(Peek().Begin())
        }
        ret.isClosed = Peek().kind == TokenKind.CLOSEDRANGEOP
        ret.rangePos = Peek().Begin()
        Next()
        ret.end = lastToken.End()
        if (!Seeing(TokenKind.RSQUARE) && !Seeing(TokenKind.COLON)) {
            ret.stopExpr = ParseExprWithPrevious(TokenKind.RANGEOP, ExprKind.INDEX_EXPR)
            if (let Some(stop) <- ret.stopExpr) {
                ret.end = stop.end
            }
        }
        if (ret.isClosed && ret.stopExpr.isNone()) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.EXPECTED_TOKEN,
                lastToken.End(),
                "expected expression after closed range operator in index access")
            ret.isBroken = true
        }
        if (Seeing(TokenKind.COLON)) {
            if (!hasFirstExpr || ret.stopExpr.isNone()) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    Peek().Begin(),
                    "range expression in index access cannot have step if it is without start or end")
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RSQUARE], targetTokenConsumed: false)
                return ret
            }
            Next()
            ret.colonPos = lastToken.Begin()
            ret.stepExpr = ParseExprWithPrevious(TokenKind.RANGEOP, ExprKind.INDEX_EXPR)
            if (let Some(step) <- ret.stepExpr) {
                ret.end = step.end
            }
        }
        return ParseExprWithPrevious(TokenKind.DOT, ret, ExprKind.INDEX_EXPR)
    }

    public func MakeBinaryExpr(left: Expr, op: Token, right: Expr): Expr {
        if (IsAssignment(op.kind)) {
            let expr = AssignExpr()
            expr.leftValue = left
            expr.rightExpr = right
            expr.op = op.kind
            expr.assignPos = op.Begin()
            expr.isCompound = op.kind != TokenKind.ASSIGN
            expr.begin = left.begin
            expr.end = right.end
            if (op.kind == TokenKind.ASSIGN) {
                CheckWildcardInExpr(right)
            }
            expr.isBroken = left.isBroken || right.isBroken
            expr.hasQuestSuffix = left.hasQuestSuffix
            if (expr.hasQuestSuffix) {
                let chain = OptionalChainExpr()
                chain.expr = expr
                chain.begin = expr.begin
                chain.end = expr.end
                chain.hasQuestSuffix = true
                return chain
            }
            return expr
        }
        if (op.kind == TokenKind.RANGEOP || op.kind == TokenKind.CLOSEDRANGEOP) {
            let expr = RangeExpr()
            expr.startExpr = left
            expr.stopExpr = right
            expr.rangePos = op.Begin()
            expr.isClosed = op.kind == TokenKind.CLOSEDRANGEOP
            expr.begin = left.begin
            expr.end = right.end
            expr.isBroken = left.isBroken || right.isBroken
            return expr
        }
        let expr = BinaryExpr()
        expr.leftExpr = left
        expr.rightExpr = right
        expr.op = op.kind
        expr.operatorPos = op.Begin()
        expr.begin = left.begin
        expr.end = right.end
        expr.isBroken = left.isBroken || right.isBroken
        return expr
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

    private func DiagExpectedOperatorOrEnd(): Unit {
        diag.DiagnoseRefactor(
            DiagKindRefactor.PARSE_ERROR,
            Peek().Begin(),
            "expected operator or end of expression, found '${Peek().Value()}'")
    }

    private func CheckMacroExprRules(preT: Token, tok: Token, expr: Expr): Bool {
        if (let Some(macroExpr) <- (expr as MacroExpandExpr)) {
            if (!MacroInvocationHasExpandedDecl(macroExpr.invocation)) {
                return true
            }
            if (!preT.Begin().IsZero() && !expr.isBroken) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    expr.begin,
                    "macro expansion after '${preT.Value()}' must produce an expression")
                return false
            }
            if (!expr.isBroken) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    tok.Begin(),
                    "unrecognized token '${tok.Value()}' after macro expansion")
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

    private func DiagNoneAssociativeOp(preT: Token, tok: Token): Unit {
        if (let Some(name) <- NoneAssociativeName(tok.kind)) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                tok.Begin(),
                "chained ${name} operators are not associative after '${preT.Value()}'")
        }
    }

    private func CheckLeftExpression(base: Expr, tok: Token): Unit {
        if (!IsLeftValueExpression(base, tok) && !base.isBroken) {
            DiagInvalidLeftHandExpr(base, tok)
            base.isBroken = true
        }
        if (base.astKind == ASTKind.TUPLE_LIT && tok.kind != TokenKind.ASSIGN) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                tok.Begin(),
                "tuple literal cannot be used with operator '${tok.Value()}'")
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
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                node.begin,
                "expected expression, found wildcard")
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

    private func DiagInvalidLeftHandExpr(expr: Expr, tok: Token): Unit {
        diag.DiagnoseRefactor(
            DiagKindRefactor.PARSE_ERROR,
            expr.begin,
            "invalid left-hand side of assignment before '${tok.Value()}'")
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
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '<-' in ${conditionName} condition")
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
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected expression after '<-'")
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

    public func ParseUnsafeBlock(): Expr {
        let unsafeToken = Expect(TokenKind.UNSAFE, "expected 'unsafe'")
        if (!Seeing(TokenKind.LCURL)) {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected block after unsafe")
            return InvalidExpr(unsafeToken.Begin())
        }
        let block = ParseBlock(ScopeKind.FUNC_BODY)
        block.unsafePos = unsafeToken.Begin()
        block.begin = unsafeToken.Begin()
        return block
    }

    public func ParseBlock(): Block {
        return ParseBlock(ScopeKind.UNKNOWN_SCOPE)
    }

    public func ParseBlock(scopeKind: ScopeKind): Block {
        let block = Block()
        let left = Expect(TokenKind.LCURL, "expected '{'")
        block.leftCurlPos = left.Begin()
        block.begin = left.Begin()
        SkipNLOrSemi()
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
            let node = ParseExprOrDecl(scopeKind)
            block.body.add(node)
            SkipNLOrSemi()
        }
        block.rightCurlPos = Expect(TokenKind.RCURL, "expected '}' after block").Begin()
        block.end = block.rightCurlPos + 1
        return block
    }

    public func ParseExprOrDecl(scopeKind: ScopeKind): Node {
        if (SeeingKeywordAndOperater()) {
            return ParseExpr()
        }
        if (CheckIfSeeingDecl(scopeKind)) {
            return ParseDecl(scopeKind)
        }
        return ParseExpr()
    }

    public func CheckIfSeeingDecl(scopeKind: ScopeKind): Bool {
        return SeeingDeclInScope(scopeKind) || SeeingImport()
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
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '=>' after match case")
            }
            matchCase.arrowPos = lastToken.Begin()
            let block = Block()
            block.begin = Peek().Begin()
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.CASE) && !Seeing(TokenKind.RCURL)) {
                block.body.add(ParseExprOrDecl(ScopeKind.FUNC_BODY))
                SkipNLOrSemi()
            }
            block.end = lastToken.End()
            matchCase.exprOrDecls = block
            matchCase.end = block.end
            ret.matchCases.add(matchCase)
            SkipNLOrSemi()
        }
        ret.rightCurlPos = Expect(TokenKind.RCURL, "expected '}' after match").Begin()
        ret.end = ret.rightCurlPos + 1
        return ret
    }

    public func ParseMatchNoSelector(ret: MatchExpr): Unit {
        ret.matchMode = false
        ret.leftCurlPos = Expect(TokenKind.LCURL, "expected '{' for match body").Begin()
        SkipNLOrSemi()
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
            if (!Skip(TokenKind.CASE)) {
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected 'case'")
                Next()
                SkipNLOrSemi()
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
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '=>' after match case")
            }
            matchCase.arrowPos = lastToken.Begin()
            let block = Block()
            block.begin = Peek().Begin()
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.CASE) && !Seeing(TokenKind.RCURL)) {
                block.body.add(ParseExprOrDecl(ScopeKind.FUNC_BODY))
                SkipNLOrSemi()
            }
            block.end = lastToken.End()
            matchCase.exprOrDecls = block
            matchCase.end = block.end
            ret.matchCaseOthers.add(matchCase)
            SkipNLOrSemi()
        }
        ret.rightCurlPos = Expect(TokenKind.RCURL, "expected '}' after match").Begin()
        ret.end = ret.rightCurlPos + 1
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
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected try block or resource specification")
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
        let resourceNames = ArrayList<String>()
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
            let decl = AstVarDecl()
            decl.isVar = false
            decl.isResourceVar = true
            decl.identifier = ExpectIdentifierWithPos(decl)
            decl.begin = decl.identifier.Begin()
            for (name in resourceNames) {
                if (name == decl.identifier.Val()) {
                    diag.DiagnoseRefactor(DiagKindRefactor.PARSE_ERROR, decl.identifier.Begin(), "redefined resource name '${decl.identifier.Val()}'")
                }
            }
            resourceNames.add(decl.identifier.Val())
            if (Skip(TokenKind.COLON)) {
                decl.colonPos = lastToken.Begin()
                decl.typeNode = ParseType()
            }
            if (Skip(TokenKind.ASSIGN)) {
                decl.assignPos = lastToken.Begin()
                decl.initializer = ParseExpr(ExprKind.VAR_INIT)
            } else {
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected assignment in try resource")
            }
            decl.end = if (let Some(expr) <- decl.initializer) {
                expr.end
            } else if (let Some(ty) <- decl.typeNode) {
                ty.end
            } else {
                decl.identifier.End()
            }
            ret.resourceSpec.add(decl)
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
        if (Skip(TokenKind.LPAREN)) {
            ret.catchLParenPosVector.add(lastToken.Begin())
        } else {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '(' after catch")
            ret.isBroken = true
        }
        ret.catchPatterns.add(ParseExceptTypePattern())
        if (Skip(TokenKind.RPAREN)) {
            ret.catchRParenPosVector.add(lastToken.Begin())
        } else {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected ')' after catch pattern")
            ret.isBroken = true
        }
        ret.catchBlocks.add(ParseBlock(ScopeKind.FUNC_BODY))
    }

    public func ParseHandleBlock(ret: TryExpr): Unit {
        let handler = Handler()
        handler.pos = lastToken.Begin()
        if (!Skip(TokenKind.LPAREN)) {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '(' after handle")
            ret.isBroken = true
        }
        handler.commandPattern = ParseCommandTypePattern()
        if (!Skip(TokenKind.RPAREN)) {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected ')' after handle pattern")
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
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected ':' in catch pattern")
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
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected wildcard or exception pattern")
        Next()
        return InvalidPattern(token.Begin())
    }

    public func ParseCommandTypePattern(): Pattern {
        if (Skip(TokenKind.WILDCARD)) {
            let wildcard = WildcardPattern(lastToken.Begin())
            if (!Skip(TokenKind.COLON)) {
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected ':' in handle pattern")
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
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected ':' in handle pattern")
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
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected wildcard or handle pattern")
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
        if (Skip(TokenKind.LPAREN)) {
            ret.leftParenPos = lastToken.Begin()
            if (!Seeing(TokenKind.RPAREN)) {
                ret.arg = ParseExpr()
            }
            ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after spawn argument").Begin()
        }
        if (SeeingAnnotationLambdaExpr()) {
            ret.task = ParseAnnotationLambdaExpr(true)
        } else if (Seeing(TokenKind.LCURL)) {
            ret.task = ParseLambdaExprWithTrailingClosure()
        } else {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected lambda block after spawn")
            let invalid = InvalidExpr(Peek().Begin())
            ret.task = invalid
            ret.isBroken = true
        }
        if (let Some(task) <- ret.task) {
            if (task.astKind != ASTKind.LAMBDA_EXPR) {
                ret.isBroken = true
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
        return param
    }

    private func ParseFuncParamListInLambdaExpr(): AstFuncParamList {
        let paramList = AstFuncParamList()
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
        return paramList
    }

    public func ParseLambdaExpr(isTailClosure: Bool): LambdaExpr {
        let lambda = LambdaExpr()
        lambda.begin = Peek().Begin()
        let body = AstFuncBody()
        if (Skip(TokenKind.LCURL)) {
            let paramList = ParseFuncParamListInLambdaExpr()
            if (!paramList.params.isEmpty() && !SkipDoubleArrow()) {
                if (!lambda.TestAttr(Attribute.HAS_BROKEN)) {
                    diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(),
                        "expected '=>' in lambda expression")
                }
                ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.DOUBLE_ARROW, TokenKind.RCURL],
                    targetTokenConsumed: false)
                if (!Skip(TokenKind.DOUBLE_ARROW)) {
                    let _ = SkipCombinedDoubleArrow()
                }
                lambda.EnableAttr(Attribute.HAS_BROKEN)
            } else {
                if (paramList.params.isEmpty() && !isTailClosure) {
                    let hasDoubleArrow = lastToken.kind == TokenKind.DOUBLE_ARROW || Skip(TokenKind.DOUBLE_ARROW) ||
                        SkipCombinedDoubleArrow()
                    let hasWildcard = Seeing([TokenKind.WILDCARD, TokenKind.DOUBLE_ARROW]) ||
                        Seeing([TokenKind.WILDCARD, TokenKind.COMMA]) ||
                        SeeingTokenAndCombinator(TokenKind.WILDCARD, [TokenKind.ASSIGN, TokenKind.GT])
                    if (!hasDoubleArrow && !hasWildcard) {
                        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(),
                            "expected '=>' in lambda expression")
                    }
                }
                if (lastToken.kind == TokenKind.DOUBLE_ARROW || Skip(TokenKind.DOUBLE_ARROW) ||
                    SkipCombinedDoubleArrow()) {
                    body.doubleArrowPos = lastToken.Begin()
                }
            }
            body.begin = lastToken.Begin()
            body.paramLists.add(paramList)
            let block = Block()
            block.leftCurlPos = lambda.begin
            block.begin = lambda.begin
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
                block.body.add(ParseExprOrDecl(ScopeKind.FUNC_BODY))
                SkipNLOrSemi()
            }
            block.rightCurlPos = Expect(TokenKind.RCURL, "expected '}' after lambda").Begin()
            block.end = block.rightCurlPos + 1
            body.body = Some(block)
            body.end = block.end
            lambda.funcBody = Some(body)
            lambda.end = block.end
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
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    binary.operatorPos,
                    "let-pattern conditions can only be combined with '&&' or '||'")
                binary.isBroken = true
            }
            return hasSubCondition
        }
        return false
    }
}
