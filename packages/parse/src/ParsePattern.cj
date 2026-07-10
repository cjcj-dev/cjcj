package cjcj::parse

import std.collection.*
import cjcj::ast.Expr as AstExpr
import cjcj::ast.MemberAccess as AstMemberAccess
import cjcj::ast.RefExpr as AstRefExpr

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
        ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_pattern, token, ConvertToken(token)).Emit()
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
        attributes: ArrayList<Attribute>,
        isVar: Bool,
        inDecl: Bool
    ): Pattern {
        let identifierToken = Peek()
        let identifier = ParseIdentifierFromToken(identifierToken)
        let begin = identifierToken.Begin()
        Next()
        if (Skip(TokenKind.COLON)) {
            let typedPat = TypePattern()
            typedPat.colonPos = lastToken.Begin()
            typedPat.pattern = VarPattern(identifier, isVar)
            typedPat.typeNode = ParseType()
            typedPat.begin = begin
            typedPat.end = if (let Some(ty) <- typedPat.typeNode) { ty.end } else { identifier.End() }
            return typedPat
        }
        if (inDecl) {
            return ParseVarPattern(attributes, identifier, begin, isVar)
        }
        return ParseVarOrEnumPattern(identifier)
    }

    public func ParseVarPattern(
        attributes: ArrayList<Attribute>,
        identifier: SrcIdentifier,
        begin: Position,
        isVar: Bool
    ): VarPattern {
        let ret = VarPattern(identifier, nodePos: begin)
        let decl = ret.varDecl.getOrThrow()
        decl.isVar = isVar
        for (it in attributes) {
            ret.EnableAttr(it)
            decl.EnableAttr(it)
        }
        ret.end = decl.identifier.GetRawEndPos()
        return ret
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
        let refExpr = AstRefExpr()
        refExpr.ref.identifier = first
        refExpr.begin = first.Begin()
        refExpr.end = first.End()
        var constructor: AstExpr = refExpr
        enumPat.begin = first.Begin()
        enumPat.end = first.End()
        ParseEnumPatternTypeArguments(constructor, enumPat)
        while (Skip(TokenKind.DOT)) {
            let dotPos = lastToken.Begin()
            let field = ExpectIdentifierWithPos(enumPat)
            let member = AstMemberAccess()
            member.baseExpr = Some(constructor)
            member.dotPos = dotPos
            member.field = field
            member.begin = constructor.begin
            member.end = field.End()
            member.isPattern = true
            constructor = member
            enumPat.end = field.End()
            ParseEnumPatternTypeArguments(constructor, enumPat)
        }
        enumPat.constructor = Some(constructor)
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

    private func ParseEnumPatternTypeArguments(constructor: AstExpr, enumPat: EnumPattern): Unit {
        if (!Skip(TokenKind.LT)) {
            return
        }
        let leftAnglePos = lastToken.Begin()
        enumPat.leftAnglePos = leftAnglePos
        while (!Seeing(TokenKind.END) && !Seeing(TokenKind.GT)) {
            let typeArg = ParseType()
            enumPat.typeArguments.add(typeArg)
            if (let Some(refExpr) <- (constructor as AstRefExpr)) {
                refExpr.typeArguments.add(typeArg)
            } else if (let Some(member) <- (constructor as AstMemberAccess)) {
                member.typeArguments.add(typeArg)
            }
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
        try (cs = ChainScope(this, tuple)) {
            while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                tuple.patterns.add(ParsePattern(attributes, isVar, inDecl))
                if (Seeing(TokenKind.BITOR)) {
                    DiagOrPattern()
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
                    DiagExpectedRightDelimiter("(", tuple.begin)
                }
                tuple.rightParenPos = lastToken.Begin()
            } else {
                tuple.rightParenPos = lastToken.Begin()
            }
            tuple.rightBracePos = tuple.rightParenPos
            tuple.end = lastToken.End()
            if (!isEnumPatternParams && tuple.patterns.size == 1) {
                DiagExpectedMoreFieldInTuplePattern()
            }
        }
        return tuple
    }
}
