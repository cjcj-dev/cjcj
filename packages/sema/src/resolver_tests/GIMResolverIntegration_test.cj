package cjcj::sema.resolver_tests

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cjcj::ast.*
import cjcj::sema.*
import cjcj::compiler_unittest.*

@Test
public class GIMResolverIntegrationTest {
    @TestCase
    public func GenericCallRearrangesToConcreteMember(): Unit {
        let result = CompileResolverSource("""
            interface I { func foo(): Int64 { 1 } }
            class C <: I { public func foo(): Int64 { 2 } }
            func invoke<T>(x: T): Int64 where T <: I { x.foo() }
            main(): Int64 { invoke(C()) }
            """)
        @Assert(result.ok)
        let cls = FindResolverDecl(result, "C")
        let observed = ArrayList<MemberAccess>()
        for (decl in RequireFirstPackage(result).genericInstantiatedDecls) {
            if (decl.identifier.Val() != "invoke") { continue }
            let walker = Walker(decl, visitPre: { node: Node =>
                if (let Some(ma) <- (node as MemberAccess)) {
                    if (ma.field.Val() == "foo") {
                        let target = ma.GetTarget().getOrThrow()
                        let owner = target.outerDecl.getOrThrow()
                        println("RESOLVER_ASSERT call_owner=${owner.identifier.Val()}")
                        @Expect(SameDecl(owner, cls))
                        observed.add(ma)
                    }
                }
                return VisitAction.WALK_CHILDREN
            })
            walker.Walk()
        }
        @Expect(!observed.isEmpty())
    }

    @TestCase
    public func GenericInterfaceCallRecordsImplementationExtend(): Unit {
        let result = CompileResolverSource("""
            interface I { func foo(): Int64 }
            class C<T> {}
            extend<T> C<T> <: I { public func foo(): Int64 { 2 } }
            func invoke<T>(x: T): Int64 where T <: I { x.foo() }
            main(): Int64 { invoke(C<Int64>()) }
            """)
        @Assert(result.ok)
        let observed = ArrayList<MemberAccess>()
        for (decl in RequireFirstPackage(result).genericInstantiatedDecls) {
            if (decl.identifier.Val() != "invoke") { continue }
            let walker = Walker(decl, visitPre: { node: Node =>
                if (let Some(ma) <- (node as MemberAccess)) {
                    if (ma.field.Val() == "foo") {
                        let baseTy = ma.baseExpr.getOrThrow().GetTy().getOrThrow()
                        let used = result.instance.faithfulSemaInstance.getOrThrow().typeManager.GetTyUsedExtends(baseTy)
                        println("RESOLVER_ASSERT recorded_extends=${used.size}")
                        @Expect(!used.isEmpty())
                        observed.add(ma)
                    }
                }
                return VisitAction.WALK_CHILDREN
            })
            walker.Walk()
        }
        @Expect(!observed.isEmpty())
    }
}
