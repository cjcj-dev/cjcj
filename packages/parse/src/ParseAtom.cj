package cjcj::parse

import std.collection.*
import cjcj::basic.StringConvertor

extend ParserImpl {
    public func SeeingLiteral(): Bool {
        return SeeingAny([TokenKind.INTEGER_LITERAL, TokenKind.RUNE_BYTE_LITERAL, TokenKind.BOOL_LITERAL,
            TokenKind.STRING_LITERAL, TokenKind.JSTRING_LITERAL, TokenKind.MULTILINE_STRING,
            TokenKind.MULTILINE_RAW_STRING, TokenKind.RUNE_LITERAL, TokenKind.FLOAT_LITERAL, TokenKind.UNIT_LITERAL])
    }

    public func ParseAtom(): Expr {
        return ParseAtom(ExprKind.ALL)
    }

    public func ParseAtom(ek: ExprKind): Expr {
        if (IsConditionExprKind(ek) && Seeing(TokenKind.LPAREN)) {
            return ParseLeftParenExprInKind(ek)
        }
        if (SeeingLiteral()) { return ParseLitConst() }
        if ((IsConditionExprKind(ek) || ExprKindEquals(ek, ExprKind.UNKNOWN_EXPR)) && Seeing(TokenKind.LET)) {
            return ParseLetPattern(ek)
        }
        if (Seeing([TokenKind.UNSAFE, TokenKind.LCURL])) { return ParseUnsafeBlock() }
        if (Seeing(TokenKind.VARRAY)) { return ParseVArrayExpr() }
        if (SeeingPrimitiveTypeAndLParen()) { return ParseTypeConvExpr() }
        if (SeeingPrimitiveTypeAndDot()) {
            let token = Peek()
            Next()
            let ret = PrimitiveTypeExpr(TypeKindFromName(token.Value()))
            ret.begin = token.Begin()
            ret.end = token.End()
            return ret
        }
        if (Seeing(TokenKind.IDENTIFIER) || SeeingContextualKeyword() ||
            Seeing(TokenKind.PACKAGE_IDENTIFIER) || Seeing(TokenKind.THIS) || Seeing(TokenKind.SUPER)) {
            return ParseRefExpr(ek)
        }
        if (Seeing(TokenKind.WILDCARD)) {
            let token = Peek()
            Next()
            return WildcardExpr(token.Begin())
        }
        if (Seeing(TokenKind.LPAREN)) { return ParseLeftParenExpr() }
        if (Seeing(TokenKind.LSQUARE)) { return ParseArrayLitExpr() }
        if (Skip(TokenKind.LCURL)) { return ParseLambdaExpr() }
        if (Seeing(TokenKind.IF)) { return ParseIfExpr() }
        if (Seeing(TokenKind.MATCH)) { return ParseMatchExpr() }
        if (Seeing(TokenKind.TRY)) { return ParseTryExpr() }
        if (Seeing(TokenKind.WHILE)) { return ParseWhileExpr() }
        if (Seeing(TokenKind.DO)) { return ParseDoWhileExpr() }
        if (Seeing(TokenKind.FOR)) { return ParseForInExpr() }
        if (Seeing(TokenKind.RETURN)) { return ParseReturnExpr() }
        if (Seeing(TokenKind.BREAK) || Seeing(TokenKind.CONTINUE)) {
            let token = Peek()
            Next()
            return JumpExpr(token)
        }
        if (Seeing(TokenKind.THROW)) { return ParseThrowExpr() }
        if (Seeing(TokenKind.PERFORM)) { return ParsePerformExpr() }
        if (Seeing(TokenKind.RESUME)) { return ParseResumeExpr() }
        if (Seeing(TokenKind.SPAWN)) { return ParseSpawnExpr() }
        if (Seeing(TokenKind.SYNCHRONIZED)) { return ParseSynchronizedExpr() }
        if (Seeing(TokenKind.QUOTE)) { return ParseQuoteExpr() }
        if (SeeingMacroCall() || SeeingBuiltinAnnotation()) { return ParseMacroExprOrLambdaExpr() }
        return GetInvalidExprInAtom(Peek().Begin())
    }

    public func GetInvalidExprInAtom(pos: Position): Expr {
        let ret = InvalidExpr(pos)
        ret.isBroken = true
        if (chainedAST.isEmpty()) {
            DiagExpectedExpression()
        }
        if (!chainedAST.isEmpty() && !chainedAST[chainedAST.size - 1].hasBroken) {
            DiagExpectedExpression()
            chainedAST[chainedAST.size - 1].hasBroken = true
        }
        ret.value = Peek().Value()
        if (ret.end.column == 1) {
            ret.end = Peek().End()
        }
        return ret
    }

    private func NormalizeLitConst(lit: LitConstExpr, token: Token, isRawString!: Bool = false): LitConstExpr {
        lit.rawString = token.Value()
        lit.stringValue = StringConvertor.Normalize(token.Value(), isRawString: isRawString)
        for (point in StringConvertor.UTF8ToCodepoint(lit.stringValue)) {
            lit.codepoint.add(point)
        }
        lit.isSingleQuote = token.isSingleQuote
        return lit
    }

    public func ParseLitConst(): Expr {
        let token = Peek()
        let kind = if (token.kind == TokenKind.INTEGER_LITERAL) {
            LitConstKind.INTEGER
        } else if (token.kind == TokenKind.FLOAT_LITERAL) {
            LitConstKind.FLOAT
        } else if (token.kind == TokenKind.RUNE_LITERAL) {
            LitConstKind.RUNE
        } else if (token.kind == TokenKind.RUNE_BYTE_LITERAL) {
            LitConstKind.RUNE_BYTE
        } else if (token.kind == TokenKind.BOOL_LITERAL) {
            LitConstKind.BOOL
        } else if (token.kind == TokenKind.UNIT_LITERAL) {
            LitConstKind.UNIT
        } else if (token.kind == TokenKind.JSTRING_LITERAL) {
            LitConstKind.JSTRING
        } else if (token.kind == TokenKind.MULTILINE_STRING || token.kind == TokenKind.MULTILINE_RAW_STRING) {
            LitConstKind.STRING
        } else {
            LitConstKind.STRING
        }
        Next()
        if (token.kind == TokenKind.STRING_LITERAL || token.kind == TokenKind.JSTRING_LITERAL ||
            token.kind == TokenKind.MULTILINE_STRING) {
            return ProcessStringInterpolation(token, kind)
        }
        let lit = LitConstExpr(kind, token)
        if (token.kind == TokenKind.MULTILINE_RAW_STRING) {
            lit.stringKind = StringKind.MULTILINE_RAW
            lit.delimiterNum = UInt64(token.delimiterNum)
            return NormalizeLitConst(lit, token, isRawString: true)
        }
        if (token.kind == TokenKind.RUNE_LITERAL) {
            return NormalizeLitConst(lit, token)
        }
        return lit
    }

    public func ParseNegativeLiteral(): Expr {
        let subToken = Expect(TokenKind.SUB, "expected '-'")
        let literalToken = Peek()
        if (literalToken.kind != TokenKind.INTEGER_LITERAL && literalToken.kind != TokenKind.FLOAT_LITERAL &&
            literalToken.kind != TokenKind.RUNE_BYTE_LITERAL) {
            DiagExpectedLiteral(subToken.Begin())
            return InvalidExpr(subToken.Begin())
        }
        let kind = if (literalToken.kind == TokenKind.FLOAT_LITERAL) {
            LitConstKind.FLOAT
        } else if (literalToken.kind == TokenKind.RUNE_BYTE_LITERAL) {
            LitConstKind.RUNE_BYTE
        } else {
            LitConstKind.INTEGER
        }
        var token = literalToken
        token.SetValuePos("-" + literalToken.Value(), subToken.Begin(), literalToken.End())
        Next()
        return LitConstExpr(kind, token)
    }

    public func ProcessStringInterpolation(token: Token, kind: LitConstKind): Expr {
        let parts = lexer.GetStrParts(token)
        let lit = NormalizeLitConst(LitConstExpr(kind, token), token)
        if (token.kind == TokenKind.MULTILINE_STRING) {
            lit.stringKind = StringKind.MULTILINE
        } else if (token.kind == TokenKind.JSTRING_LITERAL) {
            lit.stringKind = StringKind.JSTRING
        }
        var hasInterpolation = false
        for (part in parts) {
            if (part.strKind == StringPartKind.EXPR) {
                hasInterpolation = true
                break
            }
        }
        if (!hasInterpolation) {
            return lit
        }
        let strExpr = StrInterpolationExpr()
        strExpr.begin = token.Begin()
        strExpr.end = token.End()
        strExpr.rawString = token.Value()
        for (part in parts) {
            strExpr.strParts.add(part)
            if (part.strKind == StringPartKind.STR) {
                let partToken = Token(token.kind, part.value, part.begin, part.end)
                let partLit = NormalizeLitConst(LitConstExpr(kind, partToken), partToken)
                if (token.kind == TokenKind.MULTILINE_STRING) {
                    partLit.stringKind = StringKind.MULTILINE
                } else if (token.kind == TokenKind.JSTRING_LITERAL) {
                    partLit.stringKind = StringKind.JSTRING
                }
                strExpr.strPartExprs.add(partLit)
            } else {
                strExpr.strPartExprs.add(ParseInterpolationExpr(part))
            }
        }
        lit.siExpr = strExpr
        return lit
    }

    public func ParseInterpolationExpr(part: StringPart): Expr {
        let ret = InterpolationExpr()
        try (cs = ChainScope(this, ret)) {
            ret.begin = part.begin
            ret.end = part.end
            ret.dollarPos = part.begin
            ret.rawString = part.value
            if (part.value.size >= 2) {
                let nested = ParserImpl(part.value[1..], diag, sourceManager, part.begin + 1, enableAttachComment, parseDeclFile)
                nested.SetCompileOptions(compileOptions)
                ret.block = nested.ParseBlock(ScopeKind.FUNC_BODY)
                if ((let None <- ret.block) || ret.block.getOrThrow().body.isEmpty() ||
                    nested.Peek().kind != TokenKind.END) {
                    ParseDiagnoseRefactor(
                        DiagKindRefactor.parse_empty_string_interpolation,
                        MakeRange(part.begin, ret.end)
                    ).Emit()
                    return InvalidExpr(part.begin)
                }
            } else {
                ret.isBroken = true
            }
        }
        return ret
    }

    public func ParseTypeConvExpr(): Expr {
        let token = Peek()
        let ret = TypeConvExpr()
        let primitive = PrimitiveType(token.Value(), token.Begin(), token.End())
        ret.typeNode = primitive
        ret.begin = token.Begin()
        Next()
        if (!Skip(TokenKind.LPAREN)) {
            DiagExpectedLeftParenAfter(ret.begin, lastToken.Value())
            return InvalidExpr(lookahead.Begin())
        }
        ret.leftParenPos = lastToken.Begin()
        ret.expr = ParseExpr()
        if (!Skip(TokenKind.RPAREN)) {
            DiagExpectedRightDelimiter("(", ret.leftParenPos)
            ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RPAREN])
            return InvalidExpr(lookahead.Begin())
        }
        ret.rightParenPos = lastToken.Begin()
        ret.end = lastToken.End()
        return ret
    }

    public func ParseVArrayExpr(): Expr {
        let ret = ArrayExpr()
        try (cs = ChainScope(this, ret)) {
            ret.begin = Peek().Begin()
            ret.typeNode = ParseVarrayType()
            ret.isValueArray = true
            if (!Skip(TokenKind.LPAREN)) {
                if (!Seeing(TokenKind.LCURL)) {
                    if (let Some(ty) <- ret.typeNode) {
                        if (!ty.isBroken) {
                            ParseDiagnoseRefactor(DiagKindRefactor.parse_varray_with_paren, ty.end).Emit()
                        }
                    }
                    ret.isBroken = true
                }
                if (let Some(ty) <- ret.typeNode) { ret.end = ty.end }
                return ret
            }
            ret.leftParenPos = lastToken.Begin()
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                ret.args.add(ParseFuncArg())
                if (Skip(TokenKind.COMMA)) {
                    ret.commaPosVector.add(lastToken.Begin())
                } else {
                    break
                }
            }
            if (!Skip(TokenKind.RPAREN)) {
                ret.isBroken = true
                DiagExpectedRightDelimiter("(", ret.leftParenPos)
            }
            ret.rightParenPos = lastToken.Begin()
            ret.end = ret.rightParenPos + 1
        }
        return ret
    }

    public func ParseRefExpr(): RefExpr {
        return ParseRefExpr(ExprKind.ALL)
    }

    public func ParseRefExpr(ek: ExprKind): RefExpr {
        let begin = Peek().Begin()
        let id = ParseIdentifierFromToken(Peek())
        Next()
        let expr = RefExpr(id)
        expr.begin = begin
        if (!Seeing(TokenKind.LT)) {
            return expr
        }
        let scope = ParserScope(this)
        expr.leftAnglePos = Peek().Begin()
        Next()
        diag.Prepare()
        let parsed = ParseTypeArguments(ek)
        if (parsed[0]) {
            for (ty in parsed[1]) { expr.typeArguments.add(ty) }
            expr.rightAnglePos = lastToken.Begin()
            diag.Commit()
        } else {
            diag.ClearTransaction()
            scope.ResetParserScope()
            expr.leftAnglePos = INVALID_POSITION
            expr.rightAnglePos = INVALID_POSITION
        }
        if (expr.rightAnglePos != INVALID_POSITION) {
            expr.end = expr.rightAnglePos + 1
        }
        return expr
    }

    public func ParseTypeArguments(): (Bool, ArrayList<Type>) {
        return ParseTypeArguments(ExprKind.UNKNOWN_EXPR)
    }

    public func ParseTypeArguments(ek: ExprKind): (Bool, ArrayList<Type>) {
        let out = ArrayList<Type>()
        let leftAnglePos = lastToken.Begin()
        if (Skip(TokenKind.GT)) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_type_argument, lastToken.Begin()).Emit()
            return (true, out)
        }
        ParseOneOrMoreSepTrailing(
            { commaPos: Position =>
                if (!out.isEmpty()) {
                    out[out.size - 1].commaPos = commaPos
                }
            },
            { =>
                while (Skip(TokenKind.NL)) {}
                let ty = ParseType()
                if (!ty.TestAttr(Attribute.IS_BROKEN)) {
                    out.add(ty)
                }
            },
            TokenKind.GT
        )
        if (!Skip(TokenKind.GT) && !out.isEmpty()) {
            DiagExpectedRightDelimiter("<", leftAnglePos)
            out.clear()
            return (false, out)
        }
        if (out.isEmpty()) {
            return (false, out)
        }
        for (ty in out) {
            if (ty.astKind == ASTKind.INVALID_TYPE) {
                out.clear()
                return (false, out)
            }
        }
        if (IsExprFollowedComma(ek) && TypeArgsMaybeConfusedWithExprWithComma(out) &&
            !IsLegFollowForGenArgInExprWithComma(ek)) {
            out.clear()
            return (false, out)
        }
        return (true, out)
    }

    public func ParseLeftParenExpr(): Expr {
        return ParseLeftParenExprInKind(ExprKind.ALL)
    }

    public func ParseTupleLitForParenExpr(leftParenPos: Position): TupleLit {
        let refExprs = ArrayList<RefExpr>()
        let commaPosVector = ArrayList<Position>()
        do {
            if (Seeing(TokenKind.IDENTIFIER) || SeeingContextualKeyword()) {
                refExprs.add(ParseRefExpr(ExprKind.EXPR_IN_TUPLE))
            }
            Next()
            commaPosVector.add(Peek().Begin())
        } while (SeeingIdentifierAndTargetOp([TokenKind.COMMA]))
        let tupleLit = TupleLit()
        tupleLit.begin = leftParenPos
        tupleLit.leftParenPos = leftParenPos
        for (refExpr in refExprs) {
            tupleLit.children.add(refExpr)
        }
        for (commaPos in commaPosVector) {
            tupleLit.commaPosVector.add(commaPos)
        }
        ParseOneOrMoreWithSeparator(TokenKind.COMMA,
            { pos: Position => tupleLit.commaPosVector.add(pos) },
            { =>
                if (Seeing(TokenKind.RPAREN) && tupleLit.children.size > 1) {
                    return
                }
                tupleLit.children.add(ParseExpr(ExprKind.EXPR_IN_TUPLE))
            })
        if (!Skip(TokenKind.RPAREN)) {
            DiagExpectedRightDelimiter("(", tupleLit.leftParenPos)
            ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RPAREN])
        }
        tupleLit.rightParenPos = lastToken.Begin()
        tupleLit.end = lastToken.End()
        return tupleLit
    }

    public func ParseTupleLitForParenExprComma(leftParenPos: Position, expr: Expr): TupleLit {
        let tupleLit = TupleLit()
        tupleLit.children.add(expr)
        while (Skip(TokenKind.COMMA)) {
            tupleLit.commaPosVector.add(lastToken.Begin())
            if (Seeing(TokenKind.RPAREN) && tupleLit.children.size > 1) {
                break
            }
            tupleLit.children.add(ParseExpr(ExprKind.EXPR_IN_TUPLE))
        }
        if (!Skip(TokenKind.RPAREN)) {
            DiagExpectedRightDelimiter("(", leftParenPos)
            ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RPAREN])
        }
        tupleLit.leftParenPos = leftParenPos
        tupleLit.rightParenPos = Peek().Begin()
        tupleLit.begin = leftParenPos
        tupleLit.end = lastToken.End()
        return tupleLit
    }

    public func ParseLeftParenExprInKind(ek: ExprKind): Expr {
        let left = Expect(TokenKind.LPAREN, "expected '('")
        if (Skip(TokenKind.RPAREN)) {
            return LitConstExpr(LitConstKind.UNIT, Token(TokenKind.UNIT_LITERAL, "()", left.Begin(), lastToken.End()))
        }
        if (SeeingIdentifierAndTargetOp([TokenKind.COMMA])) {
            return ParseTupleLitForParenExpr(left.Begin())
        }
        let childKind = if (ExprKindEquals(ek, ExprKind.IF_COND_EXPR) ||
            ExprKindEquals(ek, ExprKind.EXPR_IN_IF_COND_TUPLE)) {
            ExprKind.EXPR_IN_IF_COND_TUPLE
        } else if (ExprKindEquals(ek, ExprKind.WHILE_COND_EXPR) ||
            ExprKindEquals(ek, ExprKind.EXPR_IN_WHILE_COND_TUPLE)) {
            ExprKind.EXPR_IN_WHILE_COND_TUPLE
        } else {
            ExprKind.EXPR_IN_TUPLE
        }
        let first = ParseExpr(childKind)
        if (Seeing(TokenKind.COMMA)) {
            return ParseTupleLitForParenExprComma(left.Begin(), first)
        }
        let paren = ParenExpr()
        paren.leftParenPos = left.Begin()
        paren.expr = first
        if (!Skip(TokenKind.RPAREN)) {
            if (!(first is InvalidExpr)) {
                DiagExpectedRightDelimiter("(", left.Begin())
            }
            ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RPAREN])
        }
        paren.rightParenPos = lastToken.Begin()
        paren.begin = left.Begin()
        paren.end = lastToken.End()
        return paren
    }

    public func ParseArrayLitExpr(): Expr {
        let array = ArrayLit()
        array.leftSquarePos = Expect(TokenKind.LSQUARE, "expected '['").Begin()
        array.begin = array.leftSquarePos
        ParseZeroOrMoreSepTrailing(
            { pos: Position => array.commaPosVector.add(pos) },
            { => array.children.add(ParseExpr(ExprKind.EXPR_IN_ARRAY)) },
            TokenKind.RSQUARE)
        if (!Skip(TokenKind.RSQUARE)) {
            DiagExpectedRightDelimiter("[", array.leftSquarePos)
            ConsumeUntilAny([TokenKind.NL, TokenKind.SEMI, TokenKind.RSQUARE])
        }
        array.rightSquarePos = lastToken.Begin()
        array.end = lastToken.End()
        return array
    }
}
