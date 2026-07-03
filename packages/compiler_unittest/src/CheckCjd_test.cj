package cangjie_compiler::compiler_unittest

import cangjie_compiler::basic.{DiagCategory, DiagKindRefactor, Diagnostic, DiagnosticEngine, SourceManager}
import cangjie_compiler::frontend.{CompileStage, CompileStageIndex}
import cangjie_compiler::option.GlobalOptions
import cangjie_compiler::parse.Parser
import cangjie_compiler::utils.{CJC_ASSERT, FileUtil, ProfileRecorder, TriggerPointSetter}
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private let projectPath: String = "/root/cj_build/cangjie_compiler"

@When[os == "Windows"]
private let srcPath: String = projectPath + "\\unittests\\Parse\\ParseCangjieFiles\\"

@When[os != "Windows"]
private let srcPath: String = projectPath + "/unittests/Parse/ParseCangjieFiles/"

private func FormatCjdCheckResult(diag: DiagnosticEngine): ArrayList<Diagnostic> {
    let diags = ArrayList<Diagnostic>()
    for (diagnostic in diag.GetCategoryDiagnostic(DiagCategory.OTHER)) {
        diags.add(diagnostic)
    }
    for (diagnostic in diag.GetCategoryDiagnostic(DiagCategory.LEX)) {
        diags.add(diagnostic)
    }
    for (diagnostic in diag.GetCategoryDiagnostic(DiagCategory.PARSE)) {
        diags.add(diagnostic)
    }
    return diags
}

private func CheckCjd(cjdFilePath: String): ArrayList<Diagnostic> {
    let diags = ArrayList<Diagnostic>()
    try (recorder = ProfileRecorder("CheckCjd", "CheckCjd")) {
        try (iceSetter = TriggerPointSetter(CompileStageIndex(CompileStage.PARSE))) {
            let diag = DiagnosticEngine()
            let sm = SourceManager()
            diag.SetSourceManager(sm)
            diag.SetDisableWarning(true)
            diag.SetIsEmitter(false)
            let failedReason = Box<String>("")
            let _ = GlobalOptions.ValidateInputFilePath(
                cjdFilePath,
                DiagKindRefactor.driver_invalid_source_file,
                diag
            )
            let driverDiags = diag.GetCategoryDiagnostic(DiagCategory.OTHER)
            if (!driverDiags.isEmpty()) {
                for (diagnostic in FormatCjdCheckResult(diag)) {
                    diags.add(diagnostic)
                }
            } else {
                let content = FileUtil.ReadFileContent(cjdFilePath, failedReason)
                CJC_ASSERT(content.isSome())
                let text = content.getOrThrow()
                let fileID = sm.AddSource(cjdFilePath, text)
                let parser = Parser(fileID, text, diag, sm, attachComment: false, parseDeclFile: true)
                let _ = parser.ParseTopLevel()
                for (diagnostic in FormatCjdCheckResult(diag)) {
                    diags.add(diagnostic)
                }
            }
        }
    }
    return diags
}

@Test
class CheckCjdTest {
    @TestCase
    func TwoErrors(): Unit {
        let src = FileUtil.JoinPath(srcPath, "twoerrors.cj.d")
        let diags = CheckCjd(src)
        @Assert(diags.size == 2)
        @Expect(diags[0].rKind, DiagKindRefactor.lex_unterminated_single_line_string)
        @Expect(diags[1].rKind, DiagKindRefactor.parse_expected_one_of_identifier_or_pattern)
    }

    @TestCase
    func Good(): Unit {
        let src = FileUtil.JoinPath(srcPath, "good.cj.d")
        let diags = CheckCjd(src)
        @Assert(diags.size == 0)
    }
}
