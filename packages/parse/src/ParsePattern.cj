package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func ParsePattern(): Pattern {
        return ParsePattern(ArrayList<Attribute>(), false, false)
    }

    public func ParsePattern(attributes: ArrayList<Attribute>, isVar: Bool, inDecl: Bool): Pattern {
        if (SeeingConstPatternStart()) {
            return ParseConstPattern()
        }
        if (Skip(TokenKind.WILDCARD)) {
            let wildcardBegin = lastToken.Begin()
            if (Skip(TokenKind.COLON)) {
                return ParseTypePattern(wildcardBegin)
            }
            return WildcardPattern(wildcardBegin)
        }
        if (Seeing(TokenKind.LPAREN)) {
            return ParseTuplePattern(false, attributes, isVar, inDecl)
        }
        if (SeeingIdentifierAndTargetOp([TokenKind.LPAREN, TokenKind.LT, TokenKind.DOT])) {
            return ParseEnumPattern(attributes, isVar, inDecl)
        }
        if (SeeingIdentifierLike()) {
            return ParseTypePatternOrVarOrEnumPattern(attributes, isVar, inDecl)
        }
        let token = Peek()
        diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, token.Begin(), "expected pattern")
        Next()
        return InvalidPattern(token.Begin())
    }

    private func SeeingConstPatternStart(): Bool {
        return SeeingLiteral() || Seeing(TokenKind.SUB) || Seeing([TokenKind.LPAREN, TokenKind.RPAREN])
    }

    public func ParseConstPattern(): ConstPattern {
        let constPat = ConstPattern()
        constPat.begin = Peek().Begin()
        constPat.literal = if (Seeing([TokenKind.LPAREN, TokenKind.RPAREN])) {
            ParseSplitUnitLiteral()
        } else if (Seeing(TokenKind.SUB)) {
            ParseNegativeLiteral()
        } else {
            ParseLitConst()
        }
        if (let Some(expr) <- constPat.literal) {
            constPat.end = expr.end
        } else {
            constPat.end = constPat.begin
            constPat.isBroken = true
        }
        return constPat
    }

    private func ParseSplitUnitLiteral(): Expr {
        let left = Expect(TokenKind.LPAREN, "expected '('")
        let right = Expect(TokenKind.RPAREN, "expected ')' after unit literal")
        return LitConstExpr(LitConstKind.UNIT, Token(TokenKind.UNIT_LITERAL, "()", left.Begin(), right.End()))
    }

    public func ParseTypePattern(begin: Position): TypePattern {
        let typePat = TypePattern()
        typePat.pattern = WildcardPattern(begin)
        typePat.colonPos = lastToken.Begin()
        typePat.typeNode = ParseType()
        typePat.begin = begin
        typePat.end = if (let Some(ty) <- typePat.typeNode) { ty.end } else { begin + 1 }
        return typePat
    }

    public func ParseTypePatternOrVarOrEnumPattern(
        _: ArrayList<Attribute>,
        isVar: Bool,
        inDecl: Bool
    ): Pattern {
        let identifierToken = Peek()
        let identifier = ParseIdentifierFromToken(identifierToken)
        Next()
        if (Skip(TokenKind.COLON)) {
            let typedPat = TypePattern()
            typedPat.colonPos = lastToken.Begin()
            typedPat.pattern = VarPattern(identifier, isVar)
            typedPat.typeNode = ParseType()
            typedPat.begin = identifier.Begin()
            typedPat.end = if (let Some(ty) <- typedPat.typeNode) { ty.end } else { identifier.End() }
            return typedPat
        }
        if (inDecl) {
            return VarPattern(identifier, isVar)
        }
        return ParseVarOrEnumPattern(identifier)
    }

    public func ParseVarOrEnumPattern(identifier: SrcIdentifier): VarOrEnumPattern {
        let varOrEnum = VarOrEnumPattern(identifier)
        varOrEnum.begin = identifier.Begin()
        varOrEnum.end = identifier.End()
        return varOrEnum
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

    public func ParseTuplePattern(isEnumPatternParams: Bool, attributes: ArrayList<Attribute>, isVar: Bool, inDecl: Bool): TuplePattern {
        let tuple = TuplePattern()
        tuple.leftParenPos = Expect(TokenKind.LPAREN, "expected '('").Begin()
        tuple.leftBracePos = tuple.leftParenPos
        tuple.begin = tuple.leftParenPos
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
            tuple.patterns.add(ParsePattern(attributes, isVar, inDecl))
            if (Seeing(TokenKind.BITOR)) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.PARSE_ERROR,
                    Peek().Begin(),
                    "or-patterns are not allowed inside tuple patterns")
                ConsumeUntilAny([TokenKind.COMMA, TokenKind.RPAREN], targetTokenConsumed: false)
            }
            if (Skip(TokenKind.COMMA)) {
                tuple.commaPosVector.add(lastToken.Begin())
            } else {
                break
            }
        }
        if (!Skip(TokenKind.RPAREN)) {
            var hasBrokenChild = false
            for (tupleChild in tuple.patterns) {
                if (tupleChild.isBroken) {
                    hasBrokenChild = true
                    break
                }
            }
            if (!hasBrokenChild) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.UNTERMINATED_DELIMITER,
                    tuple.leftParenPos,
                    "expected ')' after tuple pattern")
            }
            tuple.rightParenPos = lastToken.Begin()
        } else {
            tuple.rightParenPos = lastToken.Begin()
        }
        tuple.rightBracePos = tuple.rightParenPos
        tuple.end = lastToken.End()
        if (!isEnumPatternParams && tuple.patterns.size == 1) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.PARSE_ERROR,
                tuple.begin,
                "tuple pattern must contain at least two fields")
        }
        return tuple
    }
}
