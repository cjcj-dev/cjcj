package cjcj::parse

import std.collection.*
import cjcj::ast.CreateRefExpr

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
        Skip(TokenKind.ILLEGAL)
        if (SeeingAny(GetEscapeTokenKinds())) {
            let begin = lastToken.Begin()
            let token = Peek()
            tokens.add(Token(token.kind, token.Value(), begin, token.End()))
        } else if (SeeingAny([TokenKind.LSQUARE, TokenKind.RSQUARE])) {
            let builder = diag.DiagnoseRefactor(
                DiagKindRefactor.lex_unknown_start_of_token,
                lastToken.Begin(),
                lastToken.Value())
            builder.AddMainHintArguments(lastToken.Value())
            builder.Emit()
            tokens.add(lastToken)
        } else {
            tokens.add(lastToken)
        }
    }

    private func ParseQuoteDollarInterpolation(qe: QuoteExpr): Unit {
        let token = Peek()
        let rawText = token.Value()
        let rawIdentifier = if (rawText.size > 1) { rawText[1..] } else { "" }
        let isRaw = IsRawIdentifier(rawIdentifier)
        let value = if (isRaw) { ParseNameFromRawIdentifier(rawIdentifier) } else { rawIdentifier }
        let ident = SrcIdentifier(value, token.Begin(), token.End(), isRaw)
        let ref = CreateRefExpr(ident, None, token.Begin(), ArrayList<Type>())
        ref.begin = ref.begin + 1
        ref.end = token.End()
        ref.isQuoteDollar = true
        qe.exprs.add(ref)
    }

    private func ParseQuoteDollarInterpolationWithParen(qe: QuoteExpr): Unit {
        let dollar = Peek()
        Skip(TokenKind.DOLLAR)
        let dollarPos = lastToken.Begin()
        Skip(TokenKind.LPAREN)
        let leftParenPos = lastToken.Begin()
        skipNL = true
        let parsedExpr = ParseExpr()
        CheckMacroExprRules(dollar, Token(TokenKind.DOT), parsedExpr)
        skipNL = false
        for (kind in [
            ASTKind.INVALID_EXPR, ASTKind.RETURN_EXPR, ASTKind.WHILE_EXPR, ASTKind.DO_WHILE_EXPR,
            ASTKind.FOR_IN_EXPR, ASTKind.THROW_EXPR, ASTKind.TRY_EXPR, ASTKind.JUMP_EXPR
        ]) {
            if (parsedExpr.astKind == kind) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_invalid_quote_dollar_expr, dollar).Emit()
                break
            }
        }
        let wrapper = ParenExpr()
        wrapper.expr = parsedExpr
        wrapper.begin = dollarPos
        wrapper.leftParenPos = leftParenPos
        wrapper.rightParenPos = Peek().Begin()
        wrapper.end = Peek().End()
        qe.exprs.add(wrapper)
        if (!Seeing(TokenKind.RPAREN)) {
            DiagExpectedRightDelimiter("(", dollar.Begin())
        }
    }

    private func ParseQuoteTokens(qe: QuoteExpr): Unit {
        let tokens = ArrayList<Token>()
        var depth: Int64 = if (Seeing(TokenKind.RPAREN)) { 0 } else { 1 }
        while (depth > 0) {
            if (Seeing(TokenKind.END)) {
                break
            }
            if (Seeing(TokenKind.ILLEGAL) && Peek().Value() == "\\") {
                ParseQuoteEscapeToken(tokens)
            } else if (Seeing([TokenKind.DOLLAR, TokenKind.LPAREN])) {
                GenerateTokenPart(qe, tokens)
                ParseQuoteDollarInterpolationWithParen(qe)
            } else if (Seeing(TokenKind.DOLLAR_IDENTIFIER)) {
                GenerateTokenPart(qe, tokens)
                ParseQuoteDollarInterpolation(qe)
            } else {
                if (Seeing(TokenKind.LPAREN)) {
                    depth++
                } else if (Seeing(TokenKind.DOLLAR)) {
                    ParseDiagnoseRefactor(DiagKindRefactor.parse_expect_escape_dollar_token, Peek().Begin()).Emit()
                }
                if (SkipAmbiguousToken() || SkipCombinedDoubleArrow()) {
                    tokens.add(lastToken)
                    if (Seeing(TokenKind.RPAREN)) {
                        depth--
                    }
                    continue
                }
                let token = Peek()
                tokens.add(token)
            }
            Next()
            if (Seeing(TokenKind.RPAREN)) {
                depth--
            }
        }
        GenerateTokenPart(qe, tokens)
    }

    public func ParseQuoteExpr(): QuoteExpr {
        let ret = QuoteExpr()
        ret.begin = lastToken.Begin()
        ret.quotePos = lastToken.Begin()
        skipNL = false
        if (Skip(TokenKind.NL) || newlineSkipped) {
            ParseDiagnoseRefactor(DiagKindRefactor.parse_unexpected_line_break, lastToken).Emit()
            ret.hasBroken = true
        }
        SkipBlank(TokenKind.NL)
        if (Skip(TokenKind.LPAREN)) {
            ret.leftParenPos = lastToken.Begin()
            ParseQuoteTokens(ret)
            if (!Skip(TokenKind.RPAREN)) {
                DiagExpectedRightDelimiter("(", ret.leftParenPos)
            }
            ret.rightParenPos = lastToken.Begin()
        } else {
            if (!ret.hasBroken) {
                ParseDiagnoseRefactor(DiagKindRefactor.parse_expected_left_paren, Peek(), ConvertToken(Peek())).Emit()
            }
        }
        skipNL = true
        ret.end = lastToken.End()
        return ret
    }
}
