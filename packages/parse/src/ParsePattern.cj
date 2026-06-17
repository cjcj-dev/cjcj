package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParsePattern(): Pattern {
        return ParsePattern(ArrayList<Attribute>(), false, false)
    }

    public func ParsePattern(attributes: ArrayList<Attribute>, isVar: Bool, inDecl: Bool): Pattern {
        if (Skip(TokenKind.WILDCARD)) {
            return WildcardPattern(lastToken.Begin())
        }
        if (Seeing(TokenKind.LPAREN)) {
            return ParseTuplePattern(false, attributes, isVar, inDecl)
        }
        if (SeeingLiteral() || Seeing(TokenKind.SUB)) {
            let constPat = ConstPattern()
            constPat.literal = if (Seeing(TokenKind.SUB)) { ParseNegativeLiteral() } else { ParseLitConst() }
            if (let Some(expr) <- constPat.literal) {
                constPat.begin = expr.begin
                constPat.end = expr.end
            }
            return constPat
        }
        if (SeeingIdentifierAndTargetOp([TokenKind.LPAREN, TokenKind.LT, TokenKind.DOT])) {
            return ParseEnumPattern(attributes, isVar, inDecl)
        }
        if (SeeingIdentifierLike()) {
            let idTok = Peek()
            let id = ParseIdentifierFromToken(idTok)
            Next()
            let varPat = VarPattern(id, isVar)
            if (Skip(TokenKind.COLON)) {
                let typePat = TypePattern()
                typePat.pattern = varPat
                typePat.colonPos = lastToken.Begin()
                typePat.typeNode = ParseType()
                typePat.begin = varPat.begin
                if (let Some(ty) <- typePat.typeNode) { typePat.end = ty.end }
                return typePat
            }
            return varPat
        }
        let token = Peek()
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected pattern")
        Next()
        return InvalidPattern(token.Begin())
    }

    public func ParseEnumPattern(attributes: ArrayList<Attribute>, isVar: Bool, inDecl: Bool): EnumPattern {
        let enumPat = EnumPattern()
        let first = ExpectIdentifierWithPos(enumPat)
        enumPat.constructor = first
        enumPat.constructorParts.add(first)
        enumPat.begin = first.Begin()
        enumPat.end = first.End()
        ParseEnumPatternTypeArguments(enumPat)
        while (Skip(TokenKind.DOT)) {
            enumPat.dotPosVector.add(lastToken.Begin())
            let field = ExpectIdentifierWithPos(enumPat)
            enumPat.constructor = field
            enumPat.constructorParts.add(field)
            enumPat.end = field.End()
            ParseEnumPatternTypeArguments(enumPat)
        }
        if (Seeing(TokenKind.LPAREN)) {
            let tuplePattern = ParseTuplePattern(true, attributes, isVar, inDecl)
            enumPat.leftParenPos = tuplePattern.leftParenPos
            enumPat.rightParenPos = tuplePattern.rightParenPos
            for (pattern in tuplePattern.patterns) {
                enumPat.patterns.add(pattern)
            }
            for (commaPos in tuplePattern.commaPosVector) {
                enumPat.commaPosVector.add(commaPos)
            }
            enumPat.end = tuplePattern.end
        }
        return enumPat
    }

    private func ParseEnumPatternTypeArguments(enumPat: EnumPattern): Unit {
        if (!Skip(TokenKind.LT)) {
            return
        }
        enumPat.leftAnglePos = lastToken.Begin()
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.GT)) {
            enumPat.typeArguments.add(ParseType())
            if (!Skip(TokenKind.COMMA)) {
                break
            }
        }
        enumPat.rightAnglePos = Expect(TokenKind.GT, "expected '>' after enum pattern type arguments").Begin()
        enumPat.end = enumPat.rightAnglePos + 1
    }

    public func ParseTuplePattern(_: Bool, attributes: ArrayList<Attribute>, isVar: Bool, inDecl: Bool): TuplePattern {
        let tuple = TuplePattern()
        tuple.leftParenPos = Expect(TokenKind.LPAREN, "expected '('").Begin()
        tuple.begin = tuple.leftParenPos
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
            tuple.patterns.add(ParsePattern(attributes, isVar, inDecl))
            if (Skip(TokenKind.COMMA)) {
                tuple.commaPosVector.add(lastToken.Begin())
            } else {
                break
            }
        }
        tuple.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after tuple pattern").Begin()
        tuple.end = tuple.rightParenPos + 1
        return tuple
    }
}
