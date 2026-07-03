package cangjie_compiler::parse

import std.collection.*
import cangjie_compiler::basic.StringConvertor

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
        if (Seeing(TokenKind.LCURL)) { return ParseLambdaExpr() }
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
        let token = Peek()
        DiagExpectedExpression()
        Next()
        return InvalidExpr(token.Begin())
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
        ret.leftParenPos = Expect(TokenKind.LPAREN, "expected '(' after primitive type").Begin()
        ret.expr = ParseExpr()
        ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after type conversion expression").Begin()
        ret.end = ret.rightParenPos + 1
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
            ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after VArray arguments").Begin()
            ret.end = ret.rightParenPos + 1
        }
        return ret
    }

    public func ParseRefExpr(): RefExpr {
        return ParseRefExpr(ExprKind.ALL)
    }

    public func ParseRefExpr(ek: ExprKind): RefExpr {
        let id = ParseIdentifierFromToken(Peek())
        Next()
        let expr = RefExpr(id)
        if (Seeing(TokenKind.LT) && LooksLikeTypeArguments()) {
            let parsed = ParseTypeArguments(ek)
            if (parsed[0]) {
                for (ty in parsed[1]) { expr.typeArguments.add(ty) }
                if (!expr.typeArguments.isEmpty()) { expr.end = expr.typeArguments[expr.typeArguments.size - 1].end }
            }
        }
        return expr
    }

    // Disambiguate a `<` immediately following a reference/member identifier: is it the start of a
    // generic type-argument list (`f<Int64>(...)`) or the binary less-than operator (`i < 10`)?
    //
    // The streaming parser has no cheap backtracking, so we scan the upcoming tokens (without
    // consuming them) starting just after the `<` and require that they form a balanced, well-formed
    // type-argument list: every token up to the matching `>` must be one that can legally appear
    // inside a type argument (an identifier, a primitive-type keyword, `.`/`::`/`,`, the function-type
    // punctuation `(`/`)`/`->`, the array brackets `[`/`]`, `&`, `?`, `This`, `Unit`, nested `<`/`>`).
    // The moment we see a token that cannot appear there (an integer literal, an arithmetic/relational
    // operator, `=`, `{`, `;`, a newline-terminated end, etc.) before the brackets balance, we know the
    // `<` is the less-than operator and return false so the caller leaves it for the binary-expression
    // parser. This is exactly the case `while (i < 10)` / `if (s < n)` that previously mis-parsed as a
    // generic instantiation and aborted the whole parse with "expected type".
    func LooksLikeTypeArguments(): Bool {
        // depth counts open angle brackets; the leading `<` (current Peek) is depth 1.
        var depth: Int64 = 1
        var idx: Int64 = 1
        // Cap the scan so a runaway `<` without a closer cannot read the whole file.
        let limit: Int64 = 256
        while (idx <= limit) {
            let ahead = lexer.LookAheadSkipNL(idx)
            if (ahead.size < idx) {
                // Ran out of tokens before balancing -> not a type-argument list.
                return false
            }
            let kind = ahead[idx - 1].kind
            if (kind == TokenKind.LT) {
                depth++
            } else if (kind == TokenKind.GT) {
                depth--
                if (depth == 0) {
                    return true
                }
            } else if (kind == TokenKind.RSHIFT) {
                // `>>` closes two nested angle brackets at once (e.g. `Array<Array<Int>>`).
                depth -= 2
                if (depth <= 0) {
                    return true
                }
            } else if (!IsTypeArgInnerToken(kind)) {
                return false
            }
            idx++
        }
        return false
    }

    // Tokens that may legally appear inside a generic type-argument list (excluding the angle brackets
    // themselves, which are handled by the depth counter in LooksLikeTypeArguments).
    func IsTypeArgInnerToken(kind: TokenKind): Bool {
        if (IsPackageIdentifierOrContextualKeyword(kind)) {
            return true
        }
        return match (kind) {
            case TokenKind.DOT => true
            case TokenKind.DOUBLE_COLON => true
            case TokenKind.COMMA => true
            case TokenKind.LPAREN => true
            case TokenKind.RPAREN => true
            case TokenKind.LSQUARE => true
            case TokenKind.RSQUARE => true
            case TokenKind.ARROW => true
            case TokenKind.BITAND => true
            case TokenKind.QUEST => true
            case TokenKind.THISTYPE => true
            case TokenKind.UNIT => true
            case TokenKind.NOTHING => true
            // Primitive type keywords.
            case TokenKind.INT8 => true
            case TokenKind.INT16 => true
            case TokenKind.INT32 => true
            case TokenKind.INT64 => true
            case TokenKind.INTNATIVE => true
            case TokenKind.UINT8 => true
            case TokenKind.UINT16 => true
            case TokenKind.UINT32 => true
            case TokenKind.UINT64 => true
            case TokenKind.UINTNATIVE => true
            case TokenKind.FLOAT16 => true
            case TokenKind.FLOAT32 => true
            case TokenKind.FLOAT64 => true
            case TokenKind.RUNE => true
            case TokenKind.BOOLEAN => true
            case _ => false
        }
    }

    public func ParseTypeArguments(): (Bool, ArrayList<Type>) {
        return ParseTypeArguments(ExprKind.UNKNOWN_EXPR)
    }

    public func ParseTypeArguments(_: ExprKind): (Bool, ArrayList<Type>) {
        let out = ArrayList<Type>()
        if (!Skip(TokenKind.LT)) {
            return (false, out)
        }
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.GT)) {
            out.add(ParseType())
            if (!Skip(TokenKind.COMMA)) { break }
        }
        Expect(TokenKind.GT, "expected '>' after type arguments")
        return (true, out)
    }

    public func ParseLeftParenExpr(): Expr {
        return ParseLeftParenExprInKind(ExprKind.ALL)
    }

    public func ParseLeftParenExprInKind(ek: ExprKind): Expr {
        let left = Expect(TokenKind.LPAREN, "expected '('")
        if (Skip(TokenKind.RPAREN)) {
            return LitConstExpr(LitConstKind.UNIT, Token(TokenKind.UNIT_LITERAL, "()", left.Begin(), lastToken.End()))
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
        if (Skip(TokenKind.COMMA)) {
            let tuple = TupleLit()
            tuple.leftParenPos = left.Begin()
            tuple.begin = left.Begin()
            tuple.children.add(first)
            tuple.commaPosVector.add(lastToken.Begin())
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                tuple.children.add(ParseExpr(childKind))
                if (Skip(TokenKind.COMMA)) {
                    tuple.commaPosVector.add(lastToken.Begin())
                } else {
                    break
                }
            }
            tuple.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after tuple literal").Begin()
            tuple.end = tuple.rightParenPos + 1
            return tuple
        }
        let paren = ParenExpr()
        paren.leftParenPos = left.Begin()
        paren.expr = first
        paren.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after expression").Begin()
        paren.begin = left.Begin()
        paren.end = paren.rightParenPos + 1
        return paren
    }

    public func ParseArrayLitExpr(): Expr {
        let array = ArrayLit()
        array.leftSquarePos = Expect(TokenKind.LSQUARE, "expected '['").Begin()
        array.begin = array.leftSquarePos
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RSQUARE)) {
            array.children.add(ParseExpr(ExprKind.EXPR_IN_ARRAY))
            if (Skip(TokenKind.COMMA)) {
                array.commaPosVector.add(lastToken.Begin())
            } else {
                break
            }
        }
        array.rightSquarePos = Expect(TokenKind.RSQUARE, "expected ']' after array literal").Begin()
        array.end = array.rightSquarePos + 1
        return array
    }
}
