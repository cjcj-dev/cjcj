package mocktest

import std.unittest.*
import std.unittest.testmacro.*
import std.unittest.mock.*
import std.unittest.mock.mockmacro.*

public open class Service {
    public open func value(): Int64 {
        return 1
    }
}

@Test
class MockSuite {
    @TestCase
    func testMocked() {
        // Creating a mock exercises the sema TestManager mock hooks
        // (PrepareToMock marks MOCK_SUPPORTED; HandleCreateMock collects createMock
        // calls and MockSupportManager generates the '$ToMock' accessors).
        let m = mock<Service>()
        @On(m.value()).returns(42)
        @Assert(m.value(), 42)
    }
}
