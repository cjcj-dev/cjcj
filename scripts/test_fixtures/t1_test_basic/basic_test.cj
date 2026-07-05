package basictest

import std.unittest.*
import std.unittest.testmacro.*

@Test
class BasicSuite {
    @TestCase
    func testAddition() {
        @Assert(1 + 1 == 2)
    }

    @TestCase
    func testString() {
        @Assert("a" + "b", "ab")
    }
}
