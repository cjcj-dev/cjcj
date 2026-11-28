package cjcj::ast

import std.unittest.*
import std.unittest.testmacro.*

@Test
public class TypeCheckCacheRetirementTest {
    @TestCase
    public func releaseReplacesGrownMapAndLeavesFreshMapWritable(): Unit {
        let context = ASTContext(Package())
        let old = context.typeCheckCache
        let key = Node()
        old[key] = TypeCheckCache()
        for (_ in 0..256) {
            old[Node()] = TypeCheckCache()
        }
        @Assert(old.capacity >= 257)
        @Assert(old.contains(key))

        context.ReleaseTypeCheckCache()
        @Expect(refEq(context.typeCheckCache, old), false)
        @Expect(context.typeCheckCache.capacity, 0)
        @Expect(context.typeCheckCache.contains(key), false)
        context.typeCheckCache[key] = TypeCheckCache()
        @Expect(context.typeCheckCache.contains(key), true)
    }
}
