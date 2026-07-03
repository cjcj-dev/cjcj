package cangjie_compiler::compiler_unittest

import cangjie_compiler::basic.{DiagCategory, DiagnosticEngine, GetSpaceBeforeTarget, Position, SourceManager}
import cangjie_compiler::parse.Parser
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ErrorMessageTest {
    @TestCase
    func MassageTest(): Unit {
        let columnMap = HashMap<String, Int64>()
        columnMap.add("/*中中中*/ aaa 2\n", 15)
        columnMap.add("\t/*中*/ aaa 2\n", 15)
        columnMap.add("/*Ａ Ｂ Ｃ Ｄ Ｅ Ｆ Ｇ Ｈ Ｉ Ｊ Ｋ Ｌ Ｍ Ｎ Ｏ Ｐ Ｑ Ｒ Ｓ Ｔ Ｕ Ｖ Ｗ Ｘ Ｙ Ｚ*/ aaa 2\n", 86)
        columnMap.add("/*∀ ∁ ∂ ∃ ∄ ∅ ∆ ∇ ∈ ∉ ∊ ∋ ∌ ∍ ∎ ∏ ∐ ∑ − ∓ ∔ ∕  ∗ °  √ ∛ ∜*/ aaa 2\n", 64)
        columnMap.add("/*እው ሰላም ነው. እንዴት ነህ?*/ aaa 2\n", 28)
        columnMap.add("/**Je t’aime*/ aaa 2\n", 19)
        columnMap.add("/*Σ΄αγαπώ (Se agapo)*/ aaa 2\n", 27)
        columnMap.add("/*你好。 你好吗？*/ aaa 2\n", 24)
        columnMap.add("/*愛してる*/ aaa 2\n", 17)
        columnMap.add("/*사랑해 (Saranghae)*/ aaa 2\n", 27)
        columnMap.add("/*Я тебя люблю (Ya tebya liubliu)*/ aaa 2\n", 40)
        columnMap.add("/* ?*/ aaa 2\n", 11)
        columnMap.add("/*நீங்கள் எப்படி இருக்கிறீர்கள்?*/ aaa 2\n", 31)
        columnMap.add("/*ਤੁਸੀਂ ਕਿਵੇਂ ਹੋ?*/ aaa 2\n", 19)
        columnMap.add("/*👩  <200d>🔬  */ aaa 2\n", 21)
        columnMap.add("/*𝓽𝓱𝓲𝓼 𝓲𝓼 𝓬𝓸𝓸𝓵*/ aaa 2\n", 21)
        columnMap.add("/*(-■_■)*/ aaa 2\n", 15)
        columnMap.add("/*(☞ﾟ∀ﾟ)☞*/ aaa 2\n", 16)
        columnMap.add("/*         */ aaa 2\n", 18)
        columnMap.add("/*／人 ◕ ‿‿ ◕ 人＼*/ aaa 2\n", 25)
        columnMap.add("/*▣ ■ □ ▢ ◯ ▲ ▶ ► ▼ ◆ ◢ ◣ ◤ ◥*/ aaa 2\n", 36)
        columnMap.add("/*₁₂₃₄*/ aaa 2\n", 13)
        columnMap.add("/*Μένω στους Παξούς*/ aaa 2\n", 26)

        var code = "func test() {\n"
        for ((source, _) in columnMap) {
            code += source
        }
        code += "}\n"

        let sm = SourceManager()
        let diag = DiagnosticEngine()
        diag.SetSourceManager(sm)
        let fileID = sm.AddSource("ErrorMessageTest.cj", code)
        let parser = Parser(fileID, code, diag, sm)
        let _ = parser.ParseTopLevel()

        let ds = diag.GetCategoryDiagnostic(DiagCategory.PARSE)
        @Expect(ds.isEmpty(), false)
        for (diagnostic in ds) {
            let begin = diagnostic.GetBegin()
            let source = sm.GetContentBetween(begin.fileID, Position(begin.line, 1), Position(begin.line, Int64.Max))
            if (columnMap.contains(source)) {
                let printColumn = GetSpaceBeforeTarget(source, diagnostic.mainHint.range.begin.column)
                @Expect(printColumn.size, columnMap.get(source).getOrThrow())
            }
        }
    }
}
