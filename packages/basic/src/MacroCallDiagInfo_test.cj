package cjcj::basic

import std.unittest.*
import std.unittest.testmacro.*

private func makeMacroCallInfo(): MacroCallDiagInfo {
    let info = MacroCallDiagInfo()
    info.macroCallBegin = Position(1, 5, 1)
    info.macroCallEnd = Position(1, 5, 9)
    info.new2macroCallPosMap.put(40u32, Position(331, 9, 3))
    info.new2macroCallPosMap.put(60u32, Position(331, 9, 10))
    return info
}

private func expectMacroPosition(actual: Position, expected: Position): Unit {
    @Expect(actual.fileID, expected.fileID)
    @Expect(actual.line, expected.line)
    @Expect(actual.column, expected.column)
}

@Test
class MacroCallDiagInfoTest {
    @TestCase
    func originalSourceRangeRemainsOrdered(): Unit {
        let info = makeMacroCallInfo()
        let begin = info.MapPos(Position(1, 103, 20))
        let end = info.MapPos(Position(1, 105, 14), isLowerBound: true)
        expectMacroPosition(begin, Position(1, 103, 20))
        expectMacroPosition(end, Position(1, 105, 14))
        @Expect(begin <= end, true)
        expectMacroPosition(info.MapPos(Position(7, 5, 40)), Position(7, 5, 40))
    }

    @TestCase
    func repackedTokensStillMap(): Unit {
        let info = makeMacroCallInfo()
        expectMacroPosition(info.MapPos(Position(1, 5, 40)), Position(331, 9, 3))
        expectMacroPosition(info.MapPos(Position(1, 5, 45)), Position(1, 5, 45))
        expectMacroPosition(info.MapPos(Position(1, 5, 50), isLowerBound: true), Position(331, 9, 13))
    }

    @TestCase
    func currentFileLowerBoundDoesNotCrossLines(): Unit {
        let info = MacroCallDiagInfo()
        info.macroCallBegin = Position(1, 5, 1)
        info.isCurFile = true
        info.new2macroCallPosMap.put(Position(5, 40).Hash32(), Position(331, 9, 3))
        info.new2macroCallPosMap.put(Position(5, 60).Hash32(), Position(331, 9, 10))
        expectMacroPosition(info.MapPos(Position(1, 5, 50), isLowerBound: true), Position(331, 9, 13))
        expectMacroPosition(info.MapPos(Position(1, 103, 45), isLowerBound: true), Position(1, 103, 45))
    }
}
