package cjcj::chir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class DebugLocationTest {
    @TestCase
    public func emptyAndRootScopesUseCanonicalStorage(): Unit {
        let empty = DebugLocation()
        let begin = Position(1u32, 2u32)
        let end = Position(1u32, 3u32)
        let root = DebugLocation("source.cj", 1u32, begin, end)
        let explicitRoot = DebugLocation("source.cj", 1u32, begin, end, scopeInfo: ArrayList<Int64>([0]))
        @Expect(empty.GetStoredScope().isNone(), true)
        @Expect(refEq(root.GetStoredScope().getOrThrow(), explicitRoot.GetStoredScope().getOrThrow()), true)
        let copy = root.GetScopeInfo()
        copy[0] = 99
        @Expect(explicitRoot.GetScopeInfo()[0], 0)
        @Expect(root.ToString(), "loc: \"source.cj\"-1-2, scope: 0")
    }

    @TestCase
    public func scopeReplacementPreservesLocationAndWireSemantics(): Unit {
        let begin = Position(1u32, 2u32)
        let end = Position(1u32, 3u32)
        let root = DebugLocation("source.cj", 1u32, begin, end)
        var loc = root
        let source = ArrayList<Int64>([7, 8])
        loc.SetScopeInfo(source)
        source[0] = 99
        @Expect(loc == root)
        @Expect(!(loc != root))
        @Expect(root.GetScopeInfo()[0], 0)
        @Expect(loc.ToString(), "loc: \"source.cj\"-1-2, scope: 7-8")
        let payload = CHIRSerializeDebugLocation(loc)
        @Expect(CHIRParseDebugLocation(payload).ToString(), loc.ToString())
        loc.SetScopeInfo(ArrayList<Int64>(0))
        @Expect(loc.GetStoredScope().isNone(), true)
        @Expect(CHIRParseDebugLocation(CHIRSerializeDebugLocation(loc)).GetScopeInfo().isEmpty(), true)
    }

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
