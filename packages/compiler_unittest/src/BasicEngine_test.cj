package cangjie_compiler::compiler_unittest

import cangjie_compiler::basic.{
    DiagHandlerKind, DiagSeverity, Diagnostic, DiagnosticEngine, DiagnosticHandler, SourceManager
}
import cangjie_compiler::parse.Parser
import std.unittest.*
import std.unittest.testmacro.*

// C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/EngineTest.cpp:33 class LSPDiagnosticHandlerTest
private class LSPDiagnosticHandlerTest <: DiagnosticHandler {
    public var lastMessage: String = ""

    public init(diag: DiagnosticEngine) {
        super(diag, DiagHandlerKind.LSP_HANDLER)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/EngineTest.cpp:41 LSPDiagnosticHandlerTest::HandleDiagnose
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
    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/EngineTest.cpp:79 TEST(EngineTest, Handle1)
    @TestCase
    func handle1(): Unit {
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        diag.SetSourceManager(sm)
        let handler = LSPDiagnosticHandlerTest(diag)
        let code = "\n" +
            "    packag demo\n" +
            "    main(argc:int, argv!:string=\"123\") {\n" +
            "    let a:int=40\n" +
            "    let b = 2 ** -a\n" +
            "    print((a+3*b, (a+3) *b))\n" +
            "    }\n"
        diag.RegisterHandler(handler)
        let parser = Parser(code, diag, sm)
        let _ = parser.ParseTopLevel()
        @Expect(handler.lastMessage, "expected declaration, found 'packag'")
    }
}
