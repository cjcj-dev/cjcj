package cjcj::basic

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

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/EngineTest.cpp:112 TEST(EngineTest, apiTest)
    @TestCase
    func apiTest(): Unit {
        let diag = DiagnosticEngine()
        let code = #"
    main(argc:int, argv!:string="123") {
        var a = 1
        var b = """
        cangjie
"""
        var c = a + b
        return 0
    }
"#
        let expectedOut = #"error: expected test name test1, found test2
 ==> test.cj:7:13:
  |<s>
2 |       main(argc:int, argv!:string="123") {
  |  _____________~
3 | |         var a = 1
  | |        ~    ~~~~~ test
  | |________|
  |<10s>
4 |           var b = """
  |   ...
7 |           var c = a + b
  |               ^ expected test3 name here
  |<s>
note: this is a note test
 ==> test.cj:3:9:
  |<s>
3 |           var a = 1
  |  _________^
4 | |         var b = """
  | |________^
  |<s>
  # help: this is a note help test
note: this is a note test
 ==> test.cj:4:17:
  |<s>
4 |           var b = """
  |  _________________^
5 | |         cangjie
6 | | """
  | |___^
  |<s>
  # help: this is a note help test number 2

"#.replace("<10s>", "          ").replace("<s>", " ")
        let sm = SourceManager()
        let fileID = sm.AddSource("test.cj", code)
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.parse_expected_name,
            Position(fileID, 7, 13),
            arguments: ["test name", "test1", "test2"]
        )
        builder.AddMainHintArguments("test3 name")
        builder.AddHint(MakeRange(Position(fileID, 3, 13), Position(fileID, 3, 18)), arguments: ["test"])
        builder.AddHint(MakeRange(Position(fileID, 2, 13), Position(fileID, 3, 9)), arguments: ["this is other hint"])

        let sub1 = SubDiagnostic(MakeRange(Position(fileID, 3, 9), Position(fileID, 4, 9)), "this is a note test")
        let noteHelp1 = DiagHelp("this is a note help test")
        sub1.AddHelp(noteHelp1)
        builder.AddNote(sub1)

        let sub2 = SubDiagnostic(MakeRange(Position(fileID, 4, 17), Position(fileID, 6, 4)), "this is a note test")
        let noteHelp2 = DiagHelp("this is a note help test number 2")
        sub2.AddHelp(noteHelp2)
        builder.AddNote(sub2)

        @Expect(DiagnosticEmitter(builder.diagnostic, true, true, sm).Render(), expectedOut)
    }

    // C++ anchor: /root/cj_build/cangjie_compiler/unittests/Basic/EngineTest.cpp:189 TEST(EngineTest, apiTest2)
    @TestCase
    func apiTest2(): Unit {
        let diag = DiagnosticEngine()
        let code = #"
    main(argc:int,argv!:string="123") { var a = 1 + 2 * 3 }
"#
        let expectedOut = #"error: expected test name test1, found test2
 ==> test.cj:2:10:
  |<s>
2 |     main(argc:int,argv!:string="123") { var a = 1 + 2 * 3 }
  |          ^   ~    ~     ~ this is other hint
  |          |        |
  |          |        test
  |          |
  |          expected test3 name here
  |<s>
note: this is a note test
 ==> test.cj:2:9:
  |<s>
2 |     main(argc:int,argv!:string="123") { var a = 1 + 2 * 3 }
  |         ^<s>
  |<s>

"#.replace("<s>", " ")
        let sm = SourceManager()
        let fileID = sm.AddSource("test.cj", code)
        let builder = diag.DiagnoseRefactor(
            DiagKindRefactor.parse_expected_name,
            Position(fileID, 2, 10),
            arguments: ["test name", "test1", "test2"]
        )
        builder.AddMainHintArguments("test3 name")
        builder.AddHint(MakeRange(Position(fileID, 2, 19), Position(fileID, 2, 20)), arguments: ["test"])
        builder.AddHint(MakeRange(Position(fileID, 2, 25), Position(fileID, 2, 26)),
            arguments: ["this is other hint"])
        builder.AddHint(MakeRange(Position(fileID, 2, 14), Position(fileID, 2, 15)))

        let sub1 = SubDiagnostic(MakeRange(Position(fileID, 2, 9), Position(fileID, 2, 9)), "this is a note test")
        builder.AddNote(sub1)

        @Expect(DiagnosticEmitter(builder.diagnostic, true, true, sm).Render(), expectedOut)
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
        builder.Emit()
    }
}
