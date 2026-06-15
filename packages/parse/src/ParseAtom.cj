package cangjie_compiler::parse

import std.collection.*

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
        if (SeeingLiteral()) { return ParseLitConst() }
        if (Seeing(TokenKind.LET)) { return ParseLetPattern(ek) }
        if (Seeing([TokenKind.UNSAFE, TokenKind.LCURL])) { return ParseUnsafeBlock() }
        if (Seeing(TokenKind.VARRAY)) { return ParseVArrayExpr() }
        if (SeeingPrimitiveTypeAndLParen()) { return ParseTypeConvExpr() }
        if (SeeingPrimitiveTypeAndDot()) {
            let token = Peek()
            Next()
            return PrimitiveTypeExpr(token)
        }
        if (Seeing(TokenKind.IDENTIFIER) || Seeing(TokenKind.PACKAGE_IDENTIFIER) || Seeing(TokenKind.THIS) || Seeing(TokenKind.SUPER)) {
            return ParseRefExpr(ek)
        }
        if (Seeing(TokenKind.WILDCARD)) {
            let token = Peek()
            Next()
            return WildcardExpr(token.Begin())
        }
        if (Seeing(TokenKind.LPAREN)) { return ParseLeftParenExpr() }
        if (Seeing(TokenKind.LSQUARE)) { return ParseArrayLitExpr() }
        if (Seeing(TokenKind.LCURL)) { return ParseBlock(ScopeKind.FUNC_BODY) }
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
        if (Seeing(TokenKind.AT) || Seeing(TokenKind.AT_EXCL)) { return ParseMacroExprOrLambdaExpr() }
        let token = Peek()
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected expression")
        Next()
        return InvalidExpr(token.Begin())
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
        } else if (token.kind == TokenKind.MULTILINE_STRING) {
            LitConstKind.MULTILINE_STRING
        } else if (token.kind == TokenKind.MULTILINE_RAW_STRING) {
            LitConstKind.MULTILINE_RAW_STRING
        } else {
            LitConstKind.STRING
        }
        Next()
        return LitConstExpr(kind, token)
    }

    public func ParseTypeConvExpr(): Expr {
        let token = Peek()
        let ret = TypeConvExpr()
        let primitive = PrimitiveType(token.Value(), token.kind, token.Begin(), token.End())
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
        ret.begin = Peek().Begin()
        ret.typeNode = ParseVarrayType()
        ret.isValueArray = true
        if (!Skip(TokenKind.LPAREN)) {
            if (!Seeing(TokenKind.LCURL)) {
                diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '(' or trailing lambda after VArray type")
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
        return ret
    }

    public func ParseRefExpr(): RefExpr {
        return ParseRefExpr(ExprKind.ALL)
    }

    public func ParseRefExpr(ek: ExprKind): RefExpr {
        let id = ParseIdentifierFromToken(Peek())
        Next()
        let expr = RefExpr(id)
        if (Seeing(TokenKind.LT)) {
            let parsed = ParseTypeArguments(ek)
            if (parsed[0]) {
                for (ty in parsed[1]) { expr.typeArguments.add(ty) }
                if (!expr.typeArguments.isEmpty()) { expr.end = expr.typeArguments[expr.typeArguments.size - 1].end }
            }
        }
        return expr
    }

    public func ParseTypeArguments(): (Bool, ArrayList<Type>) {
        return ParseTypeArguments(ExprKind.UNKNOWN_EXPR)
    }

    public func ParseTypeArguments(ek: ExprKind): (Bool, ArrayList<Type>) {
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
        let left = Expect(TokenKind.LPAREN, "expected '('")
        if (Skip(TokenKind.RPAREN)) {
            return LitConstExpr(LitConstKind.UNIT, Token(TokenKind.UNIT_LITERAL, "()", left.Begin(), lastToken.End()))
        }
        let first = ParseExpr(ExprKind.EXPR_IN_TUPLE)
        if (Skip(TokenKind.COMMA)) {
            let tuple = TupleLit()
            tuple.leftParenPos = left.Begin()
            tuple.begin = left.Begin()
            tuple.children.add(first)
            tuple.commaPosVector.add(lastToken.Begin())
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                tuple.children.add(ParseExpr(ExprKind.EXPR_IN_TUPLE))
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
