package cjcj::sema.resolver_tests

import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::sema.*
import cjcj::compiler_unittest.*

@Test
public class OverrideFunctionResolverTest {
    @TestCase
    public func CacheLifecycleMissHitAndReset(): Unit {
        let result = CompileResolverSource("""
            interface I1 { func foo(): Int64 { 1 } }
            class A <: I1 { public func foo(): Int64 { 2 } }
            main(): Int64 { 0 }
            """)
        @Assert(result.ok)
        let baseTy = FindResolverDecl(result, "A").GetTy().getOrThrow()
        let resolver = OverrideFunctionResolver(result.instance.faithfulSemaInstance.getOrThrow().typeManager)
        OverrideFunctionResolver.ClearCache()
        // Nonfatal: a cut must still execute the post-population reset assertion.
        @Expect(OverrideFunctionResolver.instTy2MembersCache.isEmpty())
        let first = resolver.GetInstMemberFuncWithInstTy(baseTy, "foo")
        @Assert(!first.isEmpty())
        @Expect(OverrideFunctionResolver.instTy2MembersCache.contains(ResolverCacheKey(baseTy.objectId, "foo")))
        let second = resolver.GetInstMemberFuncWithInstTy(baseTy, "foo")
        @Expect(first.size, second.size)
        for ((fd, tys) in first) {
            @Assert(second.contains(fd))
            @Expect(tys.size, second.get(fd).getOrThrow().size)
        }
        OverrideFunctionResolver.ClearCache()
        println("RESOLVER_ASSERT reset_empty=${OverrideFunctionResolver.instTy2MembersCache.isEmpty()}")
        @Expect(OverrideFunctionResolver.instTy2MembersCache.isEmpty())
        let third = resolver.GetInstMemberFuncWithInstTy(baseTy, "foo")
        @Expect(!OverrideFunctionResolver.instTy2MembersCache.isEmpty())
        @Expect(first.size, third.size)
        for ((fd, tys) in first) {
            @Assert(third.contains(fd))
            @Expect(tys.size, third.get(fd).getOrThrow().size)
        }
    }

    @TestCase
    public func CandidateSetHasNoDuplicateEntries(): Unit {
        let result = CompileResolverSource("""
            interface I1 { func foo(): Int64 { 1 } }
            interface I2 <: I1 { func foo(): Int64 { 2 } }
            class A {}
            extend A <: I1 {}
            extend A <: I2 {}
            main(): Int64 { 0 }
            """)
        @Assert(result.ok)
        let resolver = OverrideFunctionResolver(result.instance.faithfulSemaInstance.getOrThrow().typeManager)
        let baseTy = FindResolverDecl(result, "A").GetTy().getOrThrow()
        OverrideFunctionResolver.ClearCache()
        let first = resolver.GetInstMemberFuncWithInstTy(baseTy, "foo")
        @Assert(!first.isEmpty())
        let second = resolver.GetInstMemberFuncWithInstTy(baseTy, "foo")
        println("RESOLVER_ASSERT dedup_entries=${first.size}/${second.size}")
        @Expect(first.size, second.size)
        for ((fd, tys) in first) {
            @Expect(!tys.isEmpty())
            @Assert(second.contains(fd))
            @Expect(tys.size, second.get(fd).getOrThrow().size)
        }
    }

    @TestCase
    public func GetMatchedFuncInstTyReturnsValidTy(): Unit {
        let result = CompileResolverSource("""
            interface I<T> { func f(a: T): T }
            class C <: I<Int64> { public func f(a: Int64): Int64 { a } }
            main(): Int64 { 0 }
            """)
        @Assert(result.ok)
        let cls = FindResolverDecl(result, "C")
        let target = FindResolverFunc(FindResolverDecl(result, "I"), "f")
        let concrete = FindResolverFunc(cls, "f")
        let baseTy = cls.GetTy().getOrThrow()
        let resolver = OverrideFunctionResolver(result.instance.faithfulSemaInstance.getOrThrow().typeManager)
        let funcs = resolver.GetInstMemberFuncWithInstTy(baseTy, "f")
        let key = concrete
        @Assert(funcs.contains(key))
        let candidate = (key, funcs.get(key).getOrThrow())
        @Assert(!candidate[1].isEmpty())
        let matchedTy = resolver.GetMatchedFuncInstTyByGivenTarget(candidate, target, baseTy)
        println("RESOLVER_ASSERT matched_valid=${Ty.IsTyCorrect(matchedTy)} matched_func=${matchedTy.IsFunc()}")
        @Expect(Ty.IsTyCorrect(matchedTy))
        @Expect(matchedTy.IsFunc())
    }
}
