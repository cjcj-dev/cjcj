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
        if (SeeingAny([TokenKind.LSQUARE, TokenKind.RSQUARE])) {
            diag.DiagnoseRefactor(
                DiagKindRefactor.lex_unknown_start_of_token,
                slash.Begin(),
                "unknown start of token: ${slash.Value()}").Emit()
            tokens.add(slash)
            Next()
            return
        }
        tokens.add(slash)
        Next()
    }

    private func ParseQuoteDollarInterpolation(qe: QuoteExpr): Unit {
        let token = Peek()
        let rawText = token.Value()
        let rawIdentifier = if (rawText.size > 1) { rawText[1..] } else { "" }
        let isRaw = IsRawIdentifier(rawIdentifier)
        let value = if (isRaw) { ParseNameFromRawIdentifier(rawIdentifier) } else { rawIdentifier }
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
        EnterQuoteInterpolateMod()
        skipNL = true
        // 空 $() 时短路返回 InvalidExpr 而不进 ParseExpr→ParseAtom: selfhost ParseAtom 的 invalid
        // 路径会 Next() 消费 RPAREN(C++ GetInvalidExprInAtom 不消费 lookahead), 不短路会吞掉右括号
        // 导致 Expect(RPAREN) 失败+token 失同步。保留与 C++ ParseQuote.cpp:47 等价的同步语义。
        let parsedExpr = if (Seeing(TokenKind.RPAREN) || Seeing(TokenKind.END)) {
            DiagExpectedExpression()
            InvalidExpr(Peek().Begin())
        } else {
            ParseExpr()
        }
        CheckMacroExprRules(dollar, Token(TokenKind.DOT), parsedExpr)
        skipNL = false
        for (kind in [
            ASTKind.INVALID_EXPR, ASTKind.RETURN_EXPR, ASTKind.WHILE_EXPR, ASTKind.DO_WHILE_EXPR,
            ASTKind.FOR_IN_EXPR, ASTKind.THROW_EXPR, ASTKind.TRY_EXPR, ASTKind.JUMP_EXPR
        ]) {
            if (parsedExpr.astKind == kind) {
                diag.DiagnoseRefactor(
                    DiagKindRefactor.parse_invalid_quote_dollar_expr,
                    dollar.Begin(),
                    "invalid expression after the operator '$'").Emit()
                break
            }
        }
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
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expect_escape_dollar_token, Peek().Begin()).Emit()
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
            let lineBreakToken = if (Seeing(TokenKind.NL)) { Peek() } else { lastToken }
            ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_line_break, lineBreakToken).Emit()
            ret.isBroken = true
        }
        SkipBlank(TokenKind.NL)
        if (Skip(TokenKind.LPAREN)) {
            ret.leftParenPos = lastToken.Begin()
            ParseQuoteTokens(ret)
            ret.rightParenPos = Expect(TokenKind.RPAREN, "expected ')' after quote expression").Begin()
        } else {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_paren, Peek(), ConvertToken(Peek())).Emit()
            ret.isBroken = true
        }
        ret.end = lastToken.End()
        ExitQuoteExprMod()
        return ret
    }
}
