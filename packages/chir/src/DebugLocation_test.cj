package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class DebugLocationTest {
    @TestCase
    public func defaultLocationHasEmptyScope(): Unit {
        @Expect(DebugLocation().GetScopeInfo().isEmpty(), true)
    }

    @TestCase
    public func explicitLocationDefaultsToRootScope(): Unit {
        let loc = DebugLocation("/tmp/source.cj", 1u32, Position(1u32, 2u32), Position(1u32, 3u32))
        let scope = loc.GetScopeInfo()
        @Expect(scope.size, 1)
        @Expect(scope[0], 0)
    }

    @TestCase
    public func locationCopiesScopeInfo(): Unit {
        let source = ArrayList<Int64>([1, 2])
        let loc = DebugLocation(
            "/tmp/source.cj", 1u32, Position(1u32, 2u32), Position(1u32, 3u32), scopeInfo: source)
        source.add(3)

        let copy = loc.GetScopeInfo()
        copy.add(4)
        @Expect(loc.GetScopeInfo().size, 2)
        @Expect(loc.GetScopeInfo()[0], 1)
        @Expect(loc.GetScopeInfo()[1], 2)
    }
}
