package cjcj::parse

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::basic.{DiagCategory, DiagKindRefactor}

// Upstream 293cf32a, unittests/Parse/ParserTest.cpp:329-417.
@Test
class ParserTestClassRecovery {
    @TestCase
    func invalidInheritanceSeparator(): Unit {
        let headers = [
            "class C <: I1, I2", "class C <: I1, I2, I3", "class C <: I1 I2",
            "class C <: I1,\nI2", "class C <: I1 & I2"
        ]
        let bodies = ["{}", "{\nlet value: Int64 = 1\nfunc member(): Unit { if (true) {} }\n}"]
        for (header in headers) {
            for (body in bodies) {
                let sm = SourceManager()
                let diag = DiagnosticEngine()
                let file = Parser(header + " " + body + "\nfunc after(): Unit {}", diag, sm).ParseTopLevel()
                let brokenHeader = !header.contains("&")
                let diagnostics = diag.GetCategoryDiagnostic(DiagCategory.PARSE)
                @Expect(diagnostics.size, if (brokenHeader) { 1 } else { 0 })
                if (brokenHeader && !diagnostics.isEmpty()) {
                    @Expect(diagnostics[0].rKind, DiagKindRefactor.parse_expected_left_brace)
                }
                @Expect(file.decls.size, 2)
                let cd = (file.decls[0] as ClassDecl).getOrThrow()
                let parsedBody = cd.body.getOrThrow()
                println("CLASS_RECOVERY_TARGET header=${header} members=${parsedBody.decls.size}")
                @Expect(parsedBody.TestAttr(Attribute.IS_BROKEN), brokenHeader)
                @Expect(parsedBody.leftCurlPos.IsZero(), false)
                @Expect(parsedBody.rightCurlPos.IsZero(), false)
                @Expect(parsedBody.end, parsedBody.rightCurlPos + 1)
                @Expect(parsedBody.decls.size, if (body == "{}") { 0 } else { 2 })
                if (parsedBody.decls.size == 2) {
                    @Expect(parsedBody.decls[0].identifier.Val(), "value")
                    @Expect(parsedBody.decls[1].identifier.Val(), "member")
                    @Expect(refEq(parsedBody.decls[1].outerDecl.getOrThrow(), cd), true)
                }
                if (file.decls.size >= 2) {
                    @Expect(file.decls[1].astKind, ASTKind.FUNC_DECL)
                    @Expect(file.decls[1].identifier.Val(), "after")
                }
            }
        }
    }

    @TestCase
    func missingBodyPreservesNextDeclaration(): Unit {
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let file = Parser("class C <: I1, I2\nfunc after(): Unit {}", diag, sm).ParseTopLevel()
        let diagnostics = diag.GetCategoryDiagnostic(DiagCategory.PARSE)
        @Expect(diagnostics.size, 1)
        @Expect(diagnostics[0].rKind, DiagKindRefactor.parse_expected_left_brace)
        @Expect(file.decls.size, 2)
        @Expect(file.decls[0].astKind, ASTKind.CLASS_DECL)
        @Expect(file.decls[1].astKind, ASTKind.FUNC_DECL)
        @Expect(file.decls[1].identifier.Val(), "after")
        println("CLASS_RECOVERY_CONTROL missing body preserves after")
    }

    @TestCase
    func missingClosingBraceStillDiagnosed(): Unit {
        for (code in ["class C <: I1, I2 {", "class C <: I1, I2 { func member(): Unit {}"]) {
            let sm = SourceManager()
            let diag = DiagnosticEngine()
            let file = Parser(code, diag, sm).ParseTopLevel()
            let diagnostics = diag.GetCategoryDiagnostic(DiagCategory.PARSE)
            var left = 0
            var right = 0
            for (diagnostic in diagnostics) {
                if (diagnostic.rKind == DiagKindRefactor.parse_expected_left_brace) { left++ }
                if (diagnostic.rKind == DiagKindRefactor.parse_expected_right_delimiter) { right++ }
            }
            println("CLASS_RECOVERY_CLOSING_TARGET left=${left} right=${right}")
            @Expect(diagnostics.size, 2)
            @Expect(left, 1)
            @Expect(right, 1)
            @Expect(file.decls[0].astKind, ASTKind.CLASS_DECL)
        }
    }
}
