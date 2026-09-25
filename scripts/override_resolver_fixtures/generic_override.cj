package resolver_fixture
interface I { func foo(): Int64 { 1 } }
class C <: I { public func foo(): Int64 { 2 } }
func invoke<T>(x: T): Int64 where T <: I { x.foo() }
main(): Int64 { invoke(C()) }
