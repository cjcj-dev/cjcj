package cangjie_compiler::basic

import std.unittest.*
import std.unittest.testmacro.*

private class LSPDiagnosticHandlerTest <: DiagnosticHandler {
    public var lastMessage: String = ""

    public init(diag: DiagnosticEngine) {
        super(diag, DiagHandlerKind.LSP_HANDLER)
    }

    public override func HandleDiagnose(myDiag: Diagnostic): Unit {
        lastMessage = myDiag.errorMessage
        if (myDiag.diagSeverity == DiagSeverity.DS_ERROR) {
            diag.IncreaseErrorCount(myDiag.diagCategory)
        } else if (myDiag.diagSeverity == DiagSeverity.DS_WARNING) {
            diag.IncreaseWarningCount(myDiag.diagCategory)
        }
    }
}

@Test
class EngineTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/EngineTest.cpp:72 TEST(EngineTest, Register1)
    @TestCase
    func register1(): Unit {
        let diag = DiagnosticEngine()
        let handler = LSPDiagnosticHandlerTest(diag)
        diag.RegisterHandler(handler)
        @Expect(diag.GetErrorCount(), 0u64)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/EngineTest.cpp:99 TEST(EngineTest, HandlerFilter)
    @TestCase
    func handlerFilter(): Unit {
        let diag = DiagnosticEngine()
        let handler = LSPDiagnosticHandlerTest(diag)
        diag.RegisterHandler(handler)
        diag.DiagnoseRefactor(
            DiagKindRefactor.parse_expected_name,
            Position(0u64, 1, 1),
            arguments: ["test name", "test02", "test03"]
        ).Emit()
        diag.DiagnoseRefactor(
            DiagKindRefactor.parse_expected_name,
            Position(0u64, 1, 1),
            arguments: ["test name", "test02", "test03"]
        ).Emit()
        @Expect(diag.GetErrorCount(), 2u64)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/EngineTest.cpp:316 TEST(EngineTest, OldDiagKindDefGuard)
    @TestCase
    func oldDiagKindDefGuard(): Unit {
        @Expect(DiagKindIndex(DiagKind.chir_diag_end), 15)
        @Expect(DiagKindIndex(DiagKind.macro_expand_diag_end), 57)
        @Expect(DiagKindIndex(DiagKind.sema_diag_end), 287)
    }

    // See compiler_unittest/src/PortDeferred.cj for apiTest, apiTest2, apiTest4, and the Windows ShowColorTest branch.
}

@When[os != "Windows"]
@Test
class ShowColorTest {
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/EngineTest.cpp:270 #ifdef __unix__ TEST(EngineTest, ShowColorTest)
    @TestCase
    func showColorTest(): Unit {
        let sm = SourceManager()
        let fileID = sm.AddSource("test.cj", "")
        let diag = DiagnosticEngine()
        diag.SetSourceManager(sm)
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.parse_unmatched_right_delimiter,
            Position(fileID, 1, 1),
            arguments: [""]
        )
        let enableColorOut = DiagnosticEmitter(builder.diagnostic, false, true, sm).Render()
        @Expect(enableColorOut.startsWith("\u{1b}[31m"), true)
        let disableColorOut = DiagnosticEmitter(builder.diagnostic, true, true, sm).Render()
        @Expect(disableColorOut.contains("\u{1b}[31m"), false)
    }
}
