package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParseExpr(): Expr {
        return ParseExpr(ExprKind.ALL)
    }

    public func ParseExpr(ek: ExprKind): Expr {
        let left = ParseUnaryExpr(ek)
        return ParseExprRhs(0, left, ek)
    }

    public func ParseUnaryExpr(): Expr {
        return ParseUnaryExpr(ExprKind.ALL)
    }

    public func ParseUnaryExpr(ek: ExprKind): Expr {
        if (Seeing(TokenKind.NOT) || Seeing(TokenKind.ADD) || Seeing(TokenKind.SUB) || Seeing(TokenKind.BITNOT)) {
            let op = Peek()
            Next()
            let unary = UnaryExpr(op)
            unary.expr = ParseUnaryExpr(ek)
            if (let Some(child) <- unary.expr) { unary.end = child.end }
            return unary
        }
        return ParseBaseExpr(ParseAtom(ek), ek)
    }

    public func ParseBaseExpr(expr: Expr): Expr {
        return ParseBaseExpr(expr, ExprKind.ALL)
    }

    public func ParseBaseExpr(expr: Expr, ek: ExprKind): Expr {
        var base = expr
        var hasQuestSuffix = false
        while (true) {
            if (SeeingOptionalSuffix()) {
                base = ParseQuestSuffixExpr(base)
                hasQuestSuffix = true
            } else if (Seeing(TokenKind.QUEST) && !Seeing([TokenKind.QUEST, TokenKind.QUEST])) {
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '.', '(', '[', '{', or '?' after '?'")
                Next()
                break
            }
            if (Skip(TokenKind.LPAREN)) {
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
                if (Seeing(TokenKind.LT)) {
                    let parsed = ParseTypeArguments(ek)
                    if (parsed[0]) {
                        for (ty in parsed[1]) { member.typeArguments.add(ty) }
                    }
                }
                member.end = member.field.End()
                base = member
                continue
            }
            if (Skip(TokenKind.LSQUARE)) {
                let sub = SubscriptExpr()
                sub.baseExpr = base
                sub.leftSquarePos = lastToken.Begin()
                sub.begin = base.begin
                while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RSQUARE)) {
                    sub.indexExprs.add(ParseExpr(ExprKind.INDEX_EXPR))
                    if (!Skip(TokenKind.COMMA)) { break }
                }
                sub.rightSquarePos = Expect(TokenKind.RSQUARE, "expected ']' after subscript").Begin()
                sub.end = sub.rightSquarePos + 1
                base = sub
                continue
            }
            if (Seeing(TokenKind.INCR) || Seeing(TokenKind.DECR)) {
                let op = Peek()
                Next()
                let unary = UnaryExpr(op)
                unary.expr = base
                unary.begin = base.begin
                unary.end = op.End()
                base = unary
                continue
            }
            if (Seeing(TokenKind.LCURL) && (base.astKind == ASTKind.CALL_EXPR || base.astKind == ASTKind.REF_EXPR ||
                base.astKind == ASTKind.MEMBER_ACCESS || base.astKind == ASTKind.OPTIONAL_EXPR)) {
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
        return Seeing([TokenKind.QUEST, TokenKind.DOT]) || Seeing([TokenKind.QUEST, TokenKind.LPAREN]) ||
            Seeing([TokenKind.QUEST, TokenKind.LSQUARE]) || Seeing([TokenKind.QUEST, TokenKind.LCURL])
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
        var lhs = left
        while (true) {
            let prec = Precedence(Peek().kind)
            if (prec < minPrec || prec == INVALID_PRECEDENCE) {
                return lhs
            }
            let op = Peek()
            Next()
            if (op.kind == TokenKind.IS || op.kind == TokenKind.AS) {
                let typeNode = ParseType()
                if (op.kind == TokenKind.IS) {
                    let expr = IsExpr(op)
                    expr.leftExpr = lhs
                    expr.typeNode = typeNode
                    expr.begin = lhs.begin
                    expr.end = typeNode.end
                    lhs = expr
                } else {
                    let expr = AsExpr(op)
                    expr.leftExpr = lhs
                    expr.typeNode = typeNode
                    expr.begin = lhs.begin
                    expr.end = typeNode.end
                    lhs = expr
                }
                continue
            }
            var rhs = ParseUnaryExpr(ek)
            let nextPrec = Precedence(Peek().kind)
            if (prec < nextPrec) {
                rhs = ParseExprRhs(prec + 1, rhs, ek)
            }
            let node = MakeBinaryExpr(lhs, op, rhs)
            lhs = node
        }
        return lhs
    }

    public func MakeBinaryExpr(left: Expr, op: Token, right: Expr): Expr {
        let expr: BinaryExpr = if (IsAssignment(op.kind)) {
            AssignExpr(op)
        } else if (op.kind == TokenKind.RANGEOP || op.kind == TokenKind.CLOSEDRANGEOP) {
            RangeExpr(op)
        } else {
            BinaryExpr(ASTKind.BINARY_EXPR, op)
        }
        expr.leftExpr = left
        expr.rightExpr = right
        expr.begin = left.begin
        expr.end = right.end
        return expr
    }

    public func Precedence(kind: TokenKind): UInt8 {
        if (IsAssignment(kind)) { return 1u8 }
        if (kind == TokenKind.COALESCING) { return 2u8 }
        if (kind == TokenKind.OR) { return 3u8 }
        if (kind == TokenKind.AND) { return 4u8 }
        if (kind == TokenKind.BITOR) { return 5u8 }
        if (kind == TokenKind.BITXOR) { return 6u8 }
        if (kind == TokenKind.BITAND) { return 7u8 }
        if (kind == TokenKind.EQUAL || kind == TokenKind.NOTEQ || kind == TokenKind.IS || kind == TokenKind.AS) { return 8u8 }
        if (kind == TokenKind.LT || kind == TokenKind.LE || kind == TokenKind.GT || kind == TokenKind.GE) { return 9u8 }
        if (kind == TokenKind.RANGEOP || kind == TokenKind.CLOSEDRANGEOP) { return 10u8 }
        if (kind == TokenKind.ADD || kind == TokenKind.SUB || kind == TokenKind.PIPELINE || kind == TokenKind.COMPOSITION) { return 11u8 }
        if (kind == TokenKind.MUL || kind == TokenKind.DIV || kind == TokenKind.MOD) { return 12u8 }
        if (kind == TokenKind.EXP) { return 13u8 }
        return INVALID_PRECEDENCE
    }

    public func IsAssignment(kind: TokenKind): Bool {
        return kind == TokenKind.ASSIGN || kind == TokenKind.ADD_ASSIGN || kind == TokenKind.SUB_ASSIGN ||
            kind == TokenKind.MUL_ASSIGN || kind == TokenKind.EXP_ASSIGN || kind == TokenKind.DIV_ASSIGN ||
            kind == TokenKind.MOD_ASSIGN || kind == TokenKind.AND_ASSIGN || kind == TokenKind.OR_ASSIGN ||
            kind == TokenKind.BITAND_ASSIGN || kind == TokenKind.BITOR_ASSIGN || kind == TokenKind.BITXOR_ASSIGN ||
            kind == TokenKind.LSHIFT_ASSIGN || kind == TokenKind.RSHIFT_ASSIGN
    }

    public func ParseLetPattern(ek: ExprKind): LetPatternDestructor {
        let ret = LetPatternDestructor()
        let letToken = Expect(TokenKind.LET, "expected 'let'")
        let conditionName = if (ek == ExprKind.WHILE_COND_EXPR) { "while-let" } else { "if-let" }
        ret.begin = letToken.Begin()
        ret.patterns.add(ParsePattern())
        while (Skip(TokenKind.BITOR)) {
            ret.orPos.add(lastToken.Begin())
            ret.patterns.add(ParsePattern())
        }
        if (!Skip(TokenKind.BACKARROW)) {
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
        if (Seeing(TokenKind.IDENTIFIER) && lexer.LookAheadSkipNL(1).size > 0 && lexer.LookAheadSkipNL(1)[0].kind == TokenKind.COLON) {
            arg.name = ParseIdentifierFromToken(first)
            Next()
            arg.colonPos = Expect(TokenKind.COLON, "expected ':' after argument name").Begin()
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
        if (CheckIfSeeingDecl(scopeKind)) {
            return ParseDecl(scopeKind)
        }
        return ParseExpr()
    }

    public func CheckIfSeeingDecl(scopeKind: ScopeKind): Bool {
        return SeeingDecl() || SeeingImport()
    }

    public func ParseIfExpr(): IfExpr {
        let ret = IfExpr()
        let token = Expect(TokenKind.IF, "expected 'if'")
        ret.ifPos = token.Begin()
        ret.begin = token.Begin()
        ret.leftParenPos = Expect(TokenKind.LPAREN, "expected '(' after if").Begin()
        ret.condExpr = ParseExpr(ExprKind.IF_COND_EXPR)
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
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.DOUBLE_ARROW) && !Seeing(TokenKind.WHERE)) {
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
            matchCase.arrowPos = Expect(TokenKind.DOUBLE_ARROW, "expected '=>' after match case").Begin()
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
            let decl = VarDecl()
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

    public func ParseTypeAlternatives(pattern: TypeListPattern): Unit {
        pattern.types.add(ParseType())
        while (Skip(TokenKind.BITOR)) {
            pattern.bitOrPosVector.add(lastToken.Begin())
            pattern.types.add(ParseType())
        }
        if (!pattern.types.isEmpty()) {
            pattern.end = pattern.types[pattern.types.size - 1].end
        }
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
            ParseTypeAlternatives(pattern)
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
            ParseTypeAlternatives(pattern)
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
            ParseTypeAlternatives(pattern)
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
            ParseTypeAlternatives(pattern)
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
        ret.forPos = token.Begin()
        ret.begin = token.Begin()
        ret.leftParenPos = Expect(TokenKind.LPAREN, "expected '(' after for").Begin()
        ret.pattern = ParsePattern()
        ret.inPos = Expect(TokenKind.IN, "expected 'in' in for expression").Begin()
        ret.inExpr = ParseExpr()
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
        if (!AtTerminator()) {
            ret.expr = ParseExpr()
        }
        ret.end = if (let Some(expr) <- ret.expr) { expr.end } else { token.End() }
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
        ret.begin = token.Begin()
        ret.task = if (Seeing(TokenKind.LCURL)) { ParseLambdaExprWithTrailingClosure() } else { ParseExpr() }
        if (let Some(task) <- ret.task) { ret.end = task.end }
        return ret
    }

    public func ParseSynchronizedExpr(): SynchronizedExpr {
        let ret = SynchronizedExpr()
        let token = Expect(TokenKind.SYNCHRONIZED, "expected 'synchronized'")
        ret.begin = token.Begin()
        Expect(TokenKind.LPAREN, "expected '(' after synchronized")
        ret.mutex = ParseExpr()
        Expect(TokenKind.RPAREN, "expected ')' after synchronized expression")
        ret.body = ParseBlock(ScopeKind.FUNC_BODY)
        if (let Some(body) <- ret.body) { ret.end = body.end }
        return ret
    }

    public func ParseLambdaExprWithTrailingClosure(): LambdaExpr {
        return ParseLambdaExpr()
    }

    public func ParseLambdaExpr(): LambdaExpr {
        let lambda = LambdaExpr()
        lambda.begin = Peek().Begin()
        let body = FuncBody()
        if (Skip(TokenKind.LCURL)) {
            let paramList = FuncParamList()
            if (!Seeing(TokenKind.DOUBLE_ARROW)) {
                while (!Seeing(TokenKind.END) && !Seeing(TokenKind.DOUBLE_ARROW) && !Seeing(TokenKind.RCURL)) {
                    paramList.params.add(ParseFuncParam())
                    if (!Skip(TokenKind.COMMA)) { break }
                }
            }
            if (Skip(TokenKind.DOUBLE_ARROW)) {
                body.paramLists.add(paramList)
            }
            let block = Block()
            block.leftCurlPos = lambda.begin
            block.begin = lambda.begin
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RCURL)) {
                block.body.add(ParseExprOrDecl(ScopeKind.FUNC_BODY))
                SkipNLOrSemi()
            }
            block.rightCurlPos = Expect(TokenKind.RCURL, "expected '}' after lambda").Begin()
            block.end = block.rightCurlPos + 1
            body.body = block
            body.end = block.end
            lambda.funcBody = body
            lambda.end = block.end
        }
        return lambda
    }
}
