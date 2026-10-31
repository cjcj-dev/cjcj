package cjcj::macro_pkg

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ParallelMacroReportsTest {
    @TestCase
    func WireResultContainsOnlyItsCallsReports(): Unit {
        let first = MacroCall(MacroExpandExpr())
        let second = MacroCall(MacroExpandExpr())
        first.deferReports = true
        second.deferReports = true
        first.DiagReport(0, Range(Position(1, 2, 3), Position(1, 2, 4)), "first", "hint-a")
        second.DiagReport(1, Range(Position(1, 2, 3), Position(1, 2, 4)), "second", "hint-b")
        for ((call, message, hint) in [(first, "first", "hint-a"), (second, "second", "hint-b")]) {
            let bytes = ArrayList<UInt8>()
            @Assert(MacroEvalMsgSerializer().SerializeMacroCallResultMsg(call, bytes))
            let reports = ArrayList<Diagnostic>()
            MacroEvalMsgSerializer.DeSerializeDiagsFromResult(reports, bytes)
            @Assert(reports.size == 1)
            @Expect(reports[0].GetErrorMessage(), message)
            @Expect(reports[0].mainHint.str, hint)
        }
    }

    @TestCase
    func DeferredReportPreservesIgnoredSeverities(): Unit {
        let call = MacroCall(MacroExpandExpr())
        call.deferReports = true
        call.DiagReport(2, Range(), "ignored-note", "")
        call.DiagReport(3, Range(), "ignored-hint", "")
        let bytes = ArrayList<UInt8>()
        @Assert(MacroEvalMsgSerializer().SerializeMacroCallResultMsg(call, bytes))
        let reports = ArrayList<Diagnostic>()
        MacroEvalMsgSerializer.DeSerializeDiagsFromResult(reports, bytes)
        @Expect(reports.isEmpty(), true)
    }
}
