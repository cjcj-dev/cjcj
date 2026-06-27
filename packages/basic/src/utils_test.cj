package cangjie_compiler::basic

import std.unittest.*
import std.unittest.testmacro.*

private func expectArray(actual: Array<String>, expected: Array<String>): Unit {
    @Expect(actual.size, expected.size)
    var idx: Int64 = 0
    while (idx < expected.size && idx < actual.size) {
        @Expect(actual[idx], expected[idx])
        idx++
    }
}

@Test
class UtilsTest {
    @TestCase
    func getHashTest(): Unit {
        @Expect(GetHash("hello world"), 5577293430985752569u64)
    }

    @TestCase
    func joinStringsTest(): Unit {
        @Expect(JoinStrings(["hello"], ","), "hello")
        @Expect(JoinStrings(["hello", "hello"], "|"), "hello|hello")
        @Expect(JoinStrings([""], ""), "")
    }

    @TestCase
    func stringSplitTest(): Unit {
        expectArray(SplitString("a\nab\nabc\n", "\n"), ["a", "ab", "abc", ""])
        expectArray(SplitString("a;ab;abc", ";"), ["a", "ab", "abc"])
    }

    @TestCase
    func splitLinesTest0(): Unit {
        let res = ["", "", "", ""]
        let case1Ret = SplitLines("\n\n\n")
        let case2Ret = SplitLines("\r\r\r")
        let case3Ret = SplitLines("\r\n\r\n\r\n")
        let case4Ret = SplitLines("\n\r\r\n")
        expectArray(case1Ret, res)
        @Expect(case2Ret.size, 1)
        expectArray(case3Ret, res)
        @Expect(case4Ret.size, 3)
        @Expect(case2Ret[0], "\r\r\r")
        @Expect(case4Ret[0], "")
        @Expect(case4Ret[1], "\r")
        @Expect(case4Ret[2], "")
    }

    @TestCase
    func splitLinesTest1(): Unit {
        let res = ["a", "ab", "abc", ""]
        expectArray(SplitLines("a\nab\nabc\n"), res)
        let case2Ret = SplitLines("a\rab\rabc\r")
        expectArray(SplitLines("a\r\nab\r\nabc\r\n"), res)
        let case4Ret = SplitLines("a\nab\rabc\r\n")
        @Expect(case2Ret.size, 1)
        @Expect(case4Ret.size, 3)
        @Expect(case2Ret[0], "a\rab\rabc\r")
        @Expect(case4Ret[0], "a")
        @Expect(case4Ret[1], "ab\rabc")
        @Expect(case4Ret[2], "")
    }

    @TestCase
    func splitLinesTest2(): Unit {
        let res = ["a", "ab", "abc", "a"]
        expectArray(SplitLines("a\nab\nabc\na"), res)
        let case2Ret = SplitLines("a\rab\rabc\ra")
        expectArray(SplitLines("a\r\nab\r\nabc\r\na"), res)
        let case4Ret = SplitLines("a\nab\rabc\r\na")
        @Expect(case2Ret.size, 1)
        @Expect(case4Ret.size, 3)
        @Expect(case2Ret[0], "a\rab\rabc\ra")
        @Expect(case4Ret[0], "a")
        @Expect(case4Ret[1], "ab\rabc")
        @Expect(case4Ret[2], "a")
    }

    @TestCase
    func splitLinesTest3(): Unit {
        let res = ["", "ab", "abc", "a"]
        expectArray(SplitLines("\nab\nabc\na"), res)
        let case2Ret = SplitLines("\rab\rabc\ra")
        expectArray(SplitLines("\r\nab\r\nabc\r\na"), res)
        let case4Ret = SplitLines("\nab\rabc\r\na")
        @Expect(case2Ret.size, 1)
        @Expect(case4Ret.size, 3)
        @Expect(case2Ret[0], "\rab\rabc\ra")
        @Expect(case4Ret[0], "")
        @Expect(case4Ret[1], "ab\rabc")
        @Expect(case4Ret[2], "a")
    }
}
