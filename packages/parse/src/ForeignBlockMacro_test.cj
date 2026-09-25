package cjcj::parse

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::basic.{DiagCategory, DiagKindRefactor}

private func hasModifier(modifiers: ArrayList<Modifier>, kind: TokenKind): Bool {
    for (modifier in modifiers) {
        if (modifier.modifier == kind) {
            return true
        }
    }
    return false
}

private func foreignModifierLine(modifiers: ArrayList<Modifier>): Int64 {
    for (modifier in modifiers) {
        if (modifier.modifier == TokenKind.FOREIGN) {
            return modifier.begin.line
        }
    }
    return 0
}

@Test
class ParserTestNativeForeignBlock {
    @TestCase
    func macroCallsInForeignBlock(): Unit {
        let cases = [
            "foreign { @Pass(func first(): Unit) }",
            "foreign { @Pass func first(): Unit }",
            "foreign { @Outer @Inner func first(): Unit }",
            "private foreign { @Pass(var first: Int32) }",
            "foreign { @Pass(func first(): Unit)\n @Pass func second(): Unit }"
        ]
        for (code in cases) {
            let sm = SourceManager()
            let diag = DiagnosticEngine()
            let file = Parser(code, diag, sm).ParseTopLevel()
            let diagnostics = diag.GetCategoryDiagnostic(DiagCategory.PARSE)
            @Expect(diagnostics.size, 0)
            @Expect(file.decls.isEmpty(), false)
            for (decl in file.decls) {
                let callNode = (decl as MacroExpandDecl).getOrThrow()
                println("TARGET_ASSERT_EXECUTED name=macroCallsInForeignBlock beginLine=${callNode.begin.line} beginCol=${callNode.begin.column} atLine=${callNode.invocation.atPos.line} atCol=${callNode.invocation.atPos.column} hasForeign=${hasModifier(callNode.modifiers, TokenKind.FOREIGN)}")
                @Expect(callNode.begin, callNode.invocation.atPos)
                @Expect(hasModifier(callNode.modifiers, TokenKind.FOREIGN), true)
            }
        }
    }

    @TestCase
    func macroExpansionInheritsForeignBlockModifiers(): Unit {
        let cases = [
            "foreign {\n    @Pass(func first(): Unit\n        func second(): Int32\n        var value: Int32)\n}",
            "private foreign {\n    @Pass(var first: Int32\n        var second: Int32\n        var value: Int32)\n}"
        ]
        let names = ["first", "second", "value"]
        for (code in cases) {
            let sm = SourceManager()
            let diag = DiagnosticEngine()
            let file = Parser(code, diag, sm).ParseTopLevel()
            @Expect(diag.GetErrorCount(), 0u64)
            @Expect(file.decls.size, 1)
            let callNode = (file.decls[0] as MacroExpandDecl).getOrThrow()
            let expansion = Parser(callNode.invocation.args.toArray(), diag, sm)
            let nodes = expansion.ParseNodes(ScopeKind.TOPLEVEL, callNode, modifiers: callNode.modifiers)
            @Expect(diag.GetErrorCount(), 0u64)
            @Expect(nodes.size, 3)
            let blockLine = foreignModifierLine(file.decls[0].modifiers)
            let expectPrivate = code.startsWith("private")
            for (idx in 0..nodes.size) {
                let decl = (nodes[idx] as Decl).getOrThrow()
                let hasForeign = decl.TestAttr(Attribute.FOREIGN)
                println("TARGET_ASSERT_EXECUTED name=macroExpansionInheritsForeignBlockModifiers ident=${decl.identifier.Val()} hasForeign=${hasForeign} isPrivate=${decl.TestAttr(Attribute.PRIVATE)} beginLine=${decl.begin.line} blockLine=${blockLine}")
                @Expect(decl.identifier.Val(), names[idx])
                @Expect(hasForeign, true)
                @Expect(decl.TestAttr(Attribute.PRIVATE), expectPrivate)
                @Expect(decl.begin.line > blockLine, true)
            }
        }
    }

    @TestCase
    func macroExpansionOutsideForeignHasNoForeignAttr(): Unit {
        let code = "@Pass(func first(): Unit\n    func second(): Int32)\n"
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let file = Parser(code, diag, sm).ParseTopLevel()
        @Expect(diag.GetErrorCount(), 0u64)
        let callNode = (file.decls[0] as MacroExpandDecl).getOrThrow()
        let expansion = Parser(callNode.invocation.args.toArray(), diag, sm)
        let nodes = expansion.ParseNodes(ScopeKind.TOPLEVEL, callNode, modifiers: callNode.modifiers)
        @Expect(nodes.size, 2)
        for (node in nodes) {
            let decl = (node as Decl).getOrThrow()
            println("TARGET_ASSERT_EXECUTED name=macroExpansionOutsideForeignHasNoForeignAttr ident=${decl.identifier.Val()} foreign=${decl.TestAttr(Attribute.FOREIGN)}")
            @Expect(decl.TestAttr(Attribute.FOREIGN), false)
        }
    }

    @TestCase
    func foreignBlockProducedByMacroExpansion(): Unit {
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let parsed = Parser("@Pass(func dummy(): Unit)", diag, sm).ParseTopLevel()
        let callNode = (parsed.decls[0] as MacroExpandDecl).getOrThrow()
        let expandDiag = DiagnosticEngine()
        let expandSm = SourceManager()
        let nodes = Parser("foreign {\n    func first(): Unit\n}\n", expandDiag, expandSm).ParseNodes(
            ScopeKind.TOPLEVEL, callNode)
        let hasForeign = if (nodes.size == 1) {
            if (let Some(decl) <- (nodes[0] as Decl)) { decl.TestAttr(Attribute.FOREIGN) } else { false }
        } else {
            false
        }
        println("TARGET_ASSERT_EXECUTED name=foreignBlockProducedByMacroExpansion errors=${expandDiag.GetErrorCount()} nodes=${nodes.size} hasForeign=${hasForeign}")
        @Expect(expandDiag.GetErrorCount(), 0u64)
        @Expect(nodes.size, 1)
        @Expect(hasForeign, true)
    }

    @TestCase
    func rejectExplicitModifiersBeforeMacroCall(): Unit {
        let cases = [
            "foreign @Pass(func first(): Unit)",
            "public @Pass(func first(): Unit)",
            "foreign { public @Pass(func first(): Unit) }",
            "foreign { unsafe @Pass(func first(): Unit) }"
        ]
        for (code in cases) {
            let sm = SourceManager()
            let diag = DiagnosticEngine()
            let _ = Parser(code, diag, sm).ParseTopLevel()
            let diagnostics = diag.GetCategoryDiagnostic(DiagCategory.PARSE)
            let kind = if (diagnostics.size == 1) { diagnostics[0].rKind } else { DiagKindRefactor.lex_diag_begin }
            let matched = kind == DiagKindRefactor.parse_expected_no_modifier
            println("TARGET_ASSERT_EXECUTED name=rejectExplicitModifiersBeforeMacroCall size=${diagnostics.size} matched=${matched}")
            @Expect(diagnostics.size, 1)
            @Expect(kind, DiagKindRefactor.parse_expected_no_modifier)
        }
    }
}
