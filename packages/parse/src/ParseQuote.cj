package cangjie_compiler::parse

import std.collection.*

extend ParserImpl {
    public func EnterQuoteExprMod(): Unit {
        lexer.EnterQuoteMod()
    }

    public func ExitQuoteExprMod(): Unit {
        lexer.ExitQuoteMod()
    }

    public func EnterQuoteInterpolateMod(): Unit {
        lexer.EnterNormalMod()
    }

    public func ExitQuoteInterpolateMod(): Unit {
        lexer.ExitNormalMod()
    }

    private func GenerateTokenPart(qe: QuoteExpr, tokens: ArrayList<Token>): Unit {
        if (tokens.isEmpty()) {
            return
        }
        let part = TokenPart(tokens)
        qe.exprs.add(part)
        tokens.clear()
    }

    private func ParseQuoteEscapeToken(tokens: ArrayList<Token>): Unit {
        let slash = Peek()
        Next()
        if (SeeingAny(GetEscapeTokenKinds())) {
            let token = Peek()
            tokens.add(Token(token.kind, token.Value(), slash.Begin(), token.End()))
            Next()
            return
        }
        tokens.add(slash)
    }

    private func ParseQuoteDollarInterpolation(qe: QuoteExpr): Unit {
        let token = Peek()
        let rawText = token.Value()
        let rawIdentifier = if (rawText.size > 1) { rawText[1..] } else { "" }
        var value = rawIdentifier
        var isRaw = false
        if (rawIdentifier.size >= 2 && rawIdentifier[0] == b'`' && rawIdentifier[rawIdentifier.size - 1] == b'`') {
            value = rawIdentifier[1..(rawIdentifier.size - 1)]
            isRaw = true
        }
        let ident = SrcIdentifier(value, rawIdentifier, token.Begin() + 1, token.End(), isRaw)
        let ref = RefExpr(ident)
        ref.isQuoteDollar = true
        qe.exprs.add(ref)
        Next()
    }

    private func ParseQuoteDollarInterpolationWithParen(qe: QuoteExpr): Unit {
        let dollar = Expect(TokenKind.DOLLAR, "expected '$'")
        let dollarPos = dollar.Begin()
        let leftParen = Expect(TokenKind.LPAREN, "expected '(' after '$'")
        let oldSkipNL = skipNL
        EnterQuoteInterpolateMod()
        skipNL = true
        let parsedExpr = if (Seeing(TokenKind.RPAREN) || Seeing(TokenKind.END)) {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected expression in quote interpolation")
            InvalidExpr(Peek().Begin())
        } else {
            ParseExpr()
        }
        skipNL = oldSkipNL
        ExitQuoteInterpolateMod()
        let wrapper = ParenExpr()
        wrapper.expr = parsedExpr
        wrapper.begin = dollarPos
        wrapper.leftParenPos = leftParen.Begin()
        wrapper.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after quote interpolation").Begin()
        wrapper.end = wrapper.rightParenPos + 1
        qe.exprs.add(wrapper)
    }

    private func ParseQuoteTokens(qe: QuoteExpr): Unit {
        let tokens = ArrayList<Token>()
        var depth: Int64 = 1
        while (!Seeing(TokenKind.END) && depth > 0) {
            if (Seeing(TokenKind.RPAREN)) {
                depth--
                if (depth == 0) {
                    break
                }
                let token = Peek()
                tokens.add(token)
                Next()
                continue
            }
            if (Seeing(TokenKind.ILLEGAL) && Peek().Value() == "\\") {
                ParseQuoteEscapeToken(tokens)
                continue
            }
            if (Seeing([TokenKind.DOLLAR, TokenKind.LPAREN], skipNewline: false)) {
                GenerateTokenPart(qe, tokens)
                ParseQuoteDollarInterpolationWithParen(qe)
                continue
            }
            if (Seeing(TokenKind.DOLLAR_IDENTIFIER)) {
                GenerateTokenPart(qe, tokens)
                ParseQuoteDollarInterpolation(qe)
                continue
            }
            if (Seeing(TokenKind.LPAREN)) {
                depth++
            } else if (Seeing(TokenKind.DOLLAR)) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.EXPECTED_TOKEN,
                    Peek().Begin(),
                    "expected escaped dollar token or quote interpolation")
            }
            if (SkipAmbiguousToken() || SkipCombinedDoubleArrow()) {
                tokens.add(lastToken)
                continue
            }
            let token = Peek()
            tokens.add(token)
            Next()
        }
        GenerateTokenPart(qe, tokens)
    }

    public func ParseQuoteExpr(): QuoteExpr {
        let ret = QuoteExpr()
        EnterQuoteExprMod()
        let token = Expect(TokenKind.QUOTE, "expected 'quote'")
        ret.begin = token.Begin()
        ret.quotePos = token.Begin()
        if (newlineSkipped || Seeing(TokenKind.NL)) {
            diag.DiagnoseRefactor(DiagKindRefactor.UNEXPECTED_TOKEN, token.End(), "unexpected line break after quote")
            ret.isBroken = true
        }
        SkipBlank(TokenKind.NL)
        if (Skip(TokenKind.LPAREN)) {
            ret.leftParenPos = lastToken.Begin()
            ParseQuoteTokens(ret)
            ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after quote expression").Begin()
        } else {
            diag.DiagnoseRefactor(DiagKindRefactor.EXPECTED_TOKEN, Peek().Begin(), "expected '(' after quote")
            ret.isBroken = true
        }
        ret.end = lastToken.End()
        ExitQuoteExprMod()
        return ret
    }
}
