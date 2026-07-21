package cjcj::utils

import std.unittest.*
import std.unittest.testmacro.*

@Test
class TaskQueueTest {
    @TestCase
    func taskResultGetConsumesValue(): Unit {
        let result = TaskResult<Int64>()
        result.complete(42)

        @Expect(result.get(), 42)

        var secondGetThrew = false
        try {
            let _ = result.get()
        } catch (_: Exception) {
            secondGetThrew = true
        }
        @Expect(secondGetThrew, true)
    }
}
