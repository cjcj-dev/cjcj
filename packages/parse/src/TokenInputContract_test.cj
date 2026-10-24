package cjcj::parse

import cjcj::lex.Lexer as ContractLexer
import cjcj::ast.{VisitAction, Walker, StringKindIndex}
import cjcj::basic.{DiagCategory, DiagKindRefactor}
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private func expectContractJString(expr: Expr): Unit {
    let literal = (expr as LitConstExpr).getOrThrow()
    @Expect(literal.kind == LitConstKind.JSTRING, true)
    @Expect(StringKindIndex(literal.stringKind) == StringKindIndex(StringKind.JSTRING), true)
    @Expect(literal.rawString, #"${1}"#)
    @Expect(literal.stringValue, #"${1}"#)
    @Expect(literal.siExpr.isNone(), true)
}

private func expectContractCoalescing(expr: Expr): Unit {
    let binaryCount = [0]
    let refCount = [0]
    let hasCoalescing = [false]
    let hasLessThan = [false]
    Walker(expr, visitPre: { node: Node =>
        if (let Some(binary) <- (node as BinaryExpr)) {
            binaryCount[0]++
            hasCoalescing[0] = hasCoalescing[0] || binary.op == TokenKind.COALESCING
            hasLessThan[0] = hasLessThan[0] || binary.op == TokenKind.LT
        }
        if (let Some(_) <- (node as RefExpr)) {
            refCount[0]++
        }
        return VisitAction.WALK_CHILDREN
    }).Walk()
    @Expect(binaryCount[0], 2)
    @Expect(refCount[0], 3)
    @Expect(hasCoalescing[0], true)
    @Expect(hasLessThan[0], true)
}

@Test
class TokenInputContractTest {
    @TestCase
    func jStringDoesNotEnterInterpolationThroughTextOrTokens(): Unit {
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let code = #"J"${1}""#
        expectContractJString(Parser(code, diag, sm).ParseExprLibast())
        let tokens = ContractLexer(code, diag, sm, splitAmbi: false).GetTokens()
        expectContractJString(Parser(tokens, diag, sm).ParseExprLibast())
        @Expect(diag.GetErrorCount(), 0u64)

        // The ordinary string still has interpolation; do not disable it globally.
        let ordinary = (Parser(#""${1}""#, diag, sm).ParseExprLibast() as LitConstExpr).getOrThrow()
        @Expect(ordinary.siExpr.isSome(), true)
        @Expect(diag.GetErrorCount(), 0u64)
    }

    @TestCase
    func failedGenericProbePreservesCoalescingInMacroTokens(): Unit {
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let code = "a < b ?? c"
        expectContractCoalescing(Parser(code, diag, sm).ParseExprLibast())
        let tokens = ContractLexer(code, diag, sm, splitAmbi: false).GetTokens()
        @Expect(tokens.size, 5)
        @Expect(tokens[3].kind == TokenKind.COALESCING, true)
        let parser = Parser(tokens, diag, sm)
        expectContractCoalescing(parser.ParseExprLibast())
        @Expect(parser.Seeing(TokenKind.END), true)
        @Expect(parser.GetProcessedTokens(), tokens.size)
        @Expect(diag.GetErrorCount(), 0u64)
    }

    @TestCase
    func prefixCountUsesInputTokensWithAndWithoutExplicitEnd(): Unit {
        for (tail in [">>", ">>=", ">=", "??", "x"]) {
            for (withEnd in [false, true]) {
                let sm = SourceManager()
                let diag = DiagnosticEngine()
                let original = ContractLexer("1, " + tail, diag, sm, splitAmbi: false).GetTokens()
                let tokens = ArrayList<Token>()
                tokens.add(all: original)
                if (withEnd) {
                    let end = original[original.size - 1].End()
                    tokens.add(Token(TokenKind.END, "", end, end))
                }
                let parser = Parser(tokens.toArray(), diag, sm)
                let expr = (parser.ParseExprLibast() as LitConstExpr).getOrThrow()
                @Expect(expr.stringValue, "1")
                // Same post-parse separator handling as CJ_AST_ParseExpr.
                while (parser.Skip(TokenKind.NL) || parser.Skip(TokenKind.SEMI)) {}
                @Expect(parser.GetProcessedTokens(), 1)
                @Expect(parser.Peek().kind == TokenKind.COMMA, true)
                @Expect(parser.GetProcessedTokens(), 1)
                @Expect(diag.GetErrorCount(), 0u64)
            }
        }
    }

    @TestCase
    func explicitEndIsNotReportedAsConsumedInput(): Unit {
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let lexer = ContractLexer("1", diag, sm, splitAmbi: false)
        let literal = lexer.Next()
        let end = lexer.Next()
        let parser = Parser([literal, end], diag, sm)
        let _ = parser.ParseExprLibast()
        @Expect(parser.Seeing(TokenKind.END), true)
        @Expect(parser.GetProcessedTokens(), 1)
        @Expect(diag.GetErrorCount(), 0u64)
    }

    @TestCase
    func failedGenericProbePreservesParenthesizedShift(): Unit {
        let code = "a < (b >> c)"
        for (fromTokens in [false, true]) {
            let sm = SourceManager()
            let diag = DiagnosticEngine()
            let tokens = ContractLexer(code, diag, sm, splitAmbi: false).GetTokens()
            let parser = if (fromTokens) { Parser(tokens, diag, sm) } else { Parser(code, diag, sm) }
            let outer = (parser.ParseExprLibast() as BinaryExpr).getOrThrow()
            @Expect(outer.op == TokenKind.LT, true)
            let paren = (outer.rightExpr.getOrThrow() as ParenExpr).getOrThrow()
            let inner = (paren.expr.getOrThrow() as BinaryExpr).getOrThrow()
            @Expect(inner.op == TokenKind.RSHIFT, true)
            @Expect(parser.Seeing(TokenKind.END), true)
            @Expect(diag.GetErrorCount(), 0u64)
        }
    }

    @TestCase
    func typeFragmentCountStopsBeforeCompoundToken(): Unit {
        for (tail in [">>", ">>=", ">=", "??", ","]) {
            let sm = SourceManager()
            let diag = DiagnosticEngine()
            let tokens = ContractLexer("Int64 " + tail + " x", diag, sm, splitAmbi: false).GetTokens()
            let parser = Parser(tokens, diag, sm)
            @Expect(parser.ParseType().astKind == ASTKind.PRIMITIVE_TYPE, true)
            @Expect(parser.GetProcessedTokens(), 1)
            @Expect(diag.GetErrorCount(), 0u64)
        }
    }

    @TestCase
    func backquotedImportKeepsEveryPackageNameSegment(): Unit {
        for (name in ["foo-bar", "foo.bar", "foo bar", "foo-bar.baz qux", "plain"]) {
            let sm = SourceManager()
            let diag = DiagnosticEngine()
            let file = Parser("import `" + name + "`.*", diag, sm).ParseTopLevel()
            @Expect(file.imports.size, 1)
            let content = file.imports[0].content
            @Expect(content.prefixPaths.size, 1)
            @Expect(content.prefixPaths[0], name)
            @Expect(content.GetImportedPackageName(), name)
            @Expect(diag.GetErrorCount(), 0u64)
        }
    }

    @TestCase
    func enumConstructorAnnotationsAreValidatedAfterTransfer(): Unit {
        for (constructor in ["A", "A(Int64)"]) {
            let diag = DiagnosticEngine()
            let file = Parser("enum E { @C " + constructor + " }", diag, SourceManager()).ParseTopLevel()
            @Expect(file.decls.size, 1)
            let enumDecl = (file.decls[0] as EnumDecl).getOrThrow()
            @Expect(enumDecl.constructors.size, 1)
            @Expect(enumDecl.constructors[0].annotations.size, 1)
            var unexpectedAnnoCount: Int64 = 0
            for (diagnostic in diag.GetCategoryDiagnostic(DiagCategory.PARSE)) {
                if (diagnostic.rKind == DiagKindRefactor.parse_unexpected_anno_on) {
                    unexpectedAnnoCount++
                }
            }
            @Expect(unexpectedAnnoCount, 1)
            @Expect(diag.GetErrorCount(), 1u64)
            let control = DiagnosticEngine()
            let _ = Parser("enum E { " + constructor + " }", control, SourceManager()).ParseTopLevel()
            @Expect(control.GetErrorCount(), 0u64)
        }
    }

    @TestCase
    func normalizedIdentifierOperatorKeepsFragmentCount(): Unit {
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let original = ContractLexer("a < b ?? c", diag, sm, splitAmbi: false).GetTokens()
        var operatorToken = original[3]
        operatorToken.kind = TokenKind.IDENTIFIER
        original[3] = operatorToken
        let parser = Parser(original, diag, sm)
        expectContractCoalescing(parser.ParseExprLibast())
        @Expect(parser.Seeing(TokenKind.END), true)
        @Expect(parser.GetProcessedTokens(), original.size)
        @Expect(diag.GetErrorCount(), 0u64)
    }

    @TestCase
    func nestedLiteralContentsMatchThroughTextAndTokens(): Unit {
        for (content in ["{", "}", #"${"#, "\"", "/* } */", "// {", "\\"]) {
            for (literal in ["#\"" + content + "\"#", "##\"" + content + "\"##", "J\"" + content.replace("\\", "\\\\").replace("\"", "\\\"") + "\""]) {
                let interpolation = #"${"# + literal + "}"
                for (code in ["\"" + interpolation + "\"", "'" + interpolation + "'", "\"\"\"\n" + interpolation + "\n\"\"\""]) {
                for (fromTokens in [false, true]) {
                    let diag = DiagnosticEngine()
                    let sm = SourceManager()
                    let tokens = ContractLexer(code, diag, sm, splitAmbi: false).GetTokens()
                    @Expect(tokens.size, 1)
                    @Expect(tokens[0].kind == (if (code.startsWith("\"\"\"")) { TokenKind.MULTILINE_STRING } else { TokenKind.STRING_LITERAL }), true)
                    let parser = if (fromTokens) { Parser(tokens, diag, sm) } else { Parser(code, diag, sm) }
                    let outer = (parser.ParseExprLibast() as LitConstExpr).getOrThrow()
                    let nestedCount = [0]
                    Walker(outer.siExpr.getOrThrow(), visitPre: { node: Node =>
                        if (let Some(nested) <- (node as LitConstExpr)) {
                            if (StringKindIndex(nested.stringKind) == StringKindIndex(StringKind.MULTILINE_RAW) || StringKindIndex(nested.stringKind) == StringKindIndex(StringKind.JSTRING)) {
                                @Expect(nested.stringValue, content)
                                @Expect(nested.siExpr.isNone(), true)
                                nestedCount[0]++
                            }
                        }
                        return VisitAction.WALK_CHILDREN
                    }).Walk()
                    @Expect(nestedCount[0], 1)
                    @Expect(parser.Seeing(TokenKind.END), true)
                    @Expect(diag.GetErrorCount(), 0u64)
                }
                }
            }
        }
    }

    @TestCase
    func singleHashRawStringDoesNotInterpolateItsContents(): Unit {
        let code = ##""${#"${"#}""##
        let diag = DiagnosticEngine()
        let sm = SourceManager()
        let tokens = ContractLexer(code, diag, sm, splitAmbi: false).GetTokens()
        @Expect(tokens.size, 1)
        let literal = (Parser(tokens, diag, sm).ParseExprLibast() as LitConstExpr).getOrThrow()
        let rawCount = [0]
        Walker(literal.siExpr.getOrThrow(), visitPre: { node: Node =>
            if (let Some(raw) <- (node as LitConstExpr)) {
                if (StringKindIndex(raw.stringKind) == StringKindIndex(StringKind.MULTILINE_RAW)) {
                    @Expect(raw.stringValue, #"${"#)
                    @Expect(raw.delimiterNum, 1u64)
                    rawCount[0]++
                }
            }
            return VisitAction.WALK_CHILDREN
        }).Walk()
        @Expect(rawCount[0], 1)
        @Expect(diag.GetErrorCount(), 0u64)
    }

    @TestCase
    func rawStringInsideInterpolationReachesParser(): Unit {
        let code = ###""${##"x"##}""###
        for (fromTokens in [false, true]) {
            let sm = SourceManager()
            let diag = DiagnosticEngine()
            let tokens = ContractLexer(code, diag, sm, splitAmbi: false).GetTokens()
            @Expect(tokens.size, 1)
            @Expect(tokens[0].kind == TokenKind.STRING_LITERAL, true)
            let parser = if (fromTokens) { Parser(tokens, diag, sm) } else { Parser(code, diag, sm) }
            let literal = (parser.ParseExprLibast() as LitConstExpr).getOrThrow()
            let interpolation = literal.siExpr.getOrThrow()
            let rawCount = [0]
            Walker(interpolation, visitPre: { node: Node =>
                if (let Some(raw) <- (node as LitConstExpr)) {
                    if (StringKindIndex(raw.stringKind) == StringKindIndex(StringKind.MULTILINE_RAW)) {
                        @Expect(raw.stringValue, "x")
                        @Expect(raw.delimiterNum, 2u64)
                        rawCount[0]++
                    }
                }
                return VisitAction.WALK_CHILDREN
            }).Walk()
            @Expect(rawCount[0], 1)
            @Expect(parser.Seeing(TokenKind.END), true)
            @Expect(diag.GetErrorCount(), 0u64)
        }
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let _ = ContractLexer(###""${##"x}""###, diag, sm).GetTokens()
        @Expect(diag.GetErrorCount() > 0u64, true)
    }
}
