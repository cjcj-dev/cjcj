package dual

import std.unittest.*
import std.unittest.testmacro.*

func add(a: Int64, b: Int64): Int64 {
    return a + b
}

main(): Int64 {
    println(add(2, 3))
    return 0
}

@Test
class DualSuite {
    @TestCase
    func testAdd() {
        @Assert(add(2, 3), 5)
    }
}
