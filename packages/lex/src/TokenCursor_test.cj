package cjcj::lex

import cjcj::basic.{Position, DiagnosticEngine, SourceManager}
import std.unittest.*
import std.unittest.testmacro.*

@Test
class TokenCursorContractTest {
    @TestCase
    func resetReplaysUnchangedCompoundTokens(): Unit {
        for ((kind, value) in [(TokenKind.COALESCING, "??"), (TokenKind.GE, ">="),
            (TokenKind.RSHIFT, ">>"), (TokenKind.RSHIFT_ASSIGN, ">>=")]) {
            let begin = Position(0u64, 1, 1)
            let original = Token(kind, value, begin, begin + value.size)
            let lexer = Lexer([original], DiagnosticEngine(), SourceManager())
            lexer.SetResetPoint()
            let firstPass = lexer.GetTokens()
            lexer.Reset()
            let secondPass = lexer.GetTokens()
            @Expect(firstPass.size, value.size)
            @Expect(secondPass.size, firstPass.size)
            for (index in 0..secondPass.size) {
                @Expect(secondPass[index].kind == firstPass[index].kind, true)
                @Expect(secondPass[index].Value(), firstPass[index].Value())
                @Expect(secondPass[index].Begin() == begin + index, true)
                @Expect(secondPass[index].End() == begin + index + 1, true)
            }
            @Expect(lexer.GetCurrentToken(), 1)
        }
    }

    @TestCase
    func resetRestoresPartiallySplitTokenAndLookahead(): Unit {
        let begin = Position(0u64, 1, 1)
        let lexer = Lexer([Token(TokenKind.RSHIFT_ASSIGN, ">>=", begin, begin + 3)],
            DiagnosticEngine(), SourceManager())
        @Expect(lexer.Next().kind == TokenKind.GT, true)
        @Expect(lexer.GetCurrentToken(), 0)
        lexer.LookAhead(1)
        lexer.SetResetPoint()
        let firstPass = lexer.GetTokens()
        lexer.Reset()
        let secondPass = lexer.GetTokens()
        @Expect(firstPass.size, 2)
        @Expect(secondPass.size, 2)
        @Expect(secondPass[0].kind == TokenKind.GT, true)
        @Expect(secondPass[1].kind == TokenKind.ASSIGN, true)
        @Expect(secondPass[0].Begin() == begin + 1, true)
        @Expect(secondPass[1].End() == begin + 3, true)
        @Expect(lexer.GetCurrentToken(), 1)
    }

    @TestCase
    func constructorExpansionKeepsInputTokenIndices(): Unit {
        let begin = Position(0u64, 1, 1)
        for (value in ["??", ">>", ">>=", ">="]) {
            let lexer = Lexer([Token(TokenKind.IDENTIFIER, value, begin, begin + value.size),
                Token(TokenKind.IDENTIFIER, "x", begin + value.size, begin + value.size + 1)],
                DiagnosticEngine(), SourceManager())
            lexer.LookAhead(value.size + 1)
            for (index in 0..value.size) {
                @Expect(lexer.GetCurrentToken(), 0)
                let _ = lexer.Next()
                @Expect(lexer.GetLastTokenStart(), 0)
            }
            @Expect(lexer.GetCurrentToken(), 1)
            @Expect(lexer.Next().Value(), "x")
            @Expect(lexer.GetCurrentToken(), 2)
        }
    }

    @TestCase
    func implicitEndUsesLastTokenEnd(): Unit {
        let begin = Position(3u64, 2, 4)
        let end = Position(3u64, 4, 7)
        let lexer = Lexer([Token(TokenKind.STRING_LITERAL, "first\nlast", begin, end)],
            DiagnosticEngine(), SourceManager())
        let _ = lexer.Next()
        @Expect(lexer.Next().Begin() == end, true)
        @Expect(lexer.Next().End() == end, true)
        @Expect(lexer.GetCurrentToken(), 1)
    }

    @TestCase
    func resetDoesNotDuplicateComments(): Unit {
        let lexer = Lexer("/*before*/ a /*after*/ b", DiagnosticEngine(), SourceManager())
        @Expect(lexer.Next().kind == TokenKind.COMMENT, true)
        lexer.SetResetPoint()
        let _ = lexer.GetTokens()
        lexer.Reset()
        let _ = lexer.GetTokens()
        let comments = lexer.GetComments()
        @Expect(comments.size, 2)
        @Expect(comments[0].Value(), "/*before*/")
        @Expect(comments[1].Value(), "/*after*/")
    }

    @TestCase
    func lookaheadTracksOriginsAcrossSkippedComments(): Unit {
        let diag = DiagnosticEngine()
        let sm = SourceManager()
        let input = Lexer("a /* comment */ b", diag, sm, splitAmbi: false).GetTokens()
        @Expect(input.size, 3)
        let lexer = Lexer(input, diag, sm)
        lexer.LookAhead(2)
        @Expect(lexer.GetCurrentToken(), 0)
        @Expect(lexer.Next().Value(), "a")
        @Expect(lexer.GetLastTokenStart(), 0)
        @Expect(lexer.GetCurrentToken(), 2)
        @Expect(lexer.Next().Value(), "b")
        @Expect(lexer.GetLastTokenStart(), 2)
        @Expect(lexer.GetCurrentToken(), 3)
    }
}
