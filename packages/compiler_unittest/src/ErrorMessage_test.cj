package cjcj::compiler_unittest

import cjcj::basic.{DiagCategory, DiagnosticEngine, GetSpaceBeforeTarget, Position, SourceManager}
import cjcj::parse.Parser
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ErrorMessageTest {
    @TestCase
    func MassageTest(): Unit {
        let columnMap: Array<(String, Int64)> = [
            ("/*中中中*/ aaa 2\n", 15),
            ("\t/*中*/ aaa 2\n", 15),
            ("/*Ａ Ｂ Ｃ Ｄ Ｅ Ｆ Ｇ Ｈ Ｉ Ｊ Ｋ Ｌ Ｍ Ｎ Ｏ Ｐ Ｑ Ｒ Ｓ Ｔ Ｕ Ｖ Ｗ Ｘ Ｙ Ｚ*/ aaa 2\n", 86),
            ("/*∀ ∁ ∂ ∃ ∄ ∅ ∆ ∇ ∈ ∉ ∊ ∋ ∌ ∍ ∎ ∏ ∐ ∑ − ∓ ∔ ∕  ∗ °  √ ∛ ∜*/ aaa 2\n", 64),
            ("/*እው ሰላም ነው. እንዴት ነህ?*/ aaa 2\n", 28),
            ("/**Je t’aime*/ aaa 2\n", 19),
            ("/*Σ΄αγαπώ (Se agapo)*/ aaa 2\n", 27),
            ("/*你好。 你好吗？*/ aaa 2\n", 24),
            ("/*愛してる*/ aaa 2\n", 17),
            ("/*사랑해 (Saranghae)*/ aaa 2\n", 27),
            ("/*Я тебя люблю (Ya tebya liubliu)*/ aaa 2\n", 40),
            ("/* ?*/ aaa 2\n", 11),
            ("/*நீங்கள் எப்படி இருக்கிறீர்கள்?*/ aaa 2\n", 31),
            ("/*ਤੁਸੀਂ ਕਿਵੇਂ ਹੋ?*/ aaa 2\n", 19),
            ("/*👩  <200d>🔬  */ aaa 2\n", 21),
            ("/*𝓽𝓱𝓲𝓼 𝓲𝓼 𝓬𝓸𝓸𝓵*/ aaa 2\n", 21),
            ("/*(-■_■)*/ aaa 2\n", 15),
            ("/*(☞ﾟ∀ﾟ)☞*/ aaa 2\n", 16),
            ("/*         */ aaa 2\n", 18),
            ("/*／人 ◕ ‿‿ ◕ 人＼*/ aaa 2\n", 25),
            ("/*▣ ■ □ ▢ ◯ ▲ ▶ ► ▼ ◆ ◢ ◣ ◤ ◥*/ aaa 2\n", 36),
            ("/*₁₂₃₄*/ aaa 2\n", 13),
            ("/*Μένω στους Παξούς*/ aaa 2\n", 26),
        ]
        var code = "func test() {\n"
        for (entry in columnMap) {
            code += entry[0]
        }
        code += "}\n"

        let sm = SourceManager()
        let diag = DiagnosticEngine()
        diag.SetSourceManager(sm)
        let fileID = sm.AddSource("ErrorMessageTest.cj", code)
        let parser = Parser(fileID, code, diag, sm)
        let _ = parser.ParseTopLevel()

        let diagnostics = diag.GetCategoryDiagnostic(DiagCategory.PARSE)
        @Assert(!diagnostics.isEmpty())
        for (diagnostic in diagnostics) {
            let source = sm.GetContentBetween(
                diagnostic.start.fileID,
                Position(diagnostic.start.line, 1),
                Position(diagnostic.start.line, Int64.Max))
            for (entry in columnMap) {
                if (source == entry[0]) {
                    let printColumn = GetSpaceBeforeTarget(source, diagnostic.mainHint.range.begin.column)
                    @Expect(printColumn.size, entry[1])
                }
            }
        }
    }
}
