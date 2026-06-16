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
        if (SeeingIdentifierLike()) {
            let idTok = Peek()
            let id = ParseIdentifierFromToken(idTok)
            Next()
            if (Seeing(TokenKind.LPAREN)) {
                let enumPat = EnumPattern()
                enumPat.constructor = id
                enumPat.begin = id.Begin()
                enumPat.leftParenPos = Expect(TokenKind.LPAREN, "expected '('").Begin()
                while (!Seeing(TokenKind.END) && !Seeing(TokenKind.RPAREN)) {
                    enumPat.patterns.add(ParsePattern(attributes, isVar, inDecl))
                    if (!Skip(TokenKind.COMMA)) { break }
                }
                enumPat.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after enum pattern").Begin()
                enumPat.end = enumPat.rightParenPos + 1
                return enumPat
            }
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

    public func ParseTuplePattern(isEnumPatternParams: Bool, attributes: ArrayList<Attribute>, isVar: Bool, inDecl: Bool): TuplePattern {
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
