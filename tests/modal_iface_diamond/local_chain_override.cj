// Local mode: I2 overrides I1's modal default and S lists I2 first. Sema keeps the more specific default
// (I2's, 8) as the member, as Comparable<T>'s `==(this @local?)` is over Equal<T>'s; the plain foo keeps its rule.
interface I1 {
    func foo(): Int64
    func foo(this @local?): Int64 { 7 }
}
interface I2 <: I1 {
    func foo(): Int64 { 2 }
    func foo(this @local?): Int64 { 8 }
}
struct S <: I2 & I1 {}

func viaLocal(s: S @local?): Int64 { s.foo() }

main(): Int64 {
    let r = "${S().foo()} ${viaLocal(S())}"
    println(r)
    if (r == "2 8") { 0 } else { 4 }
}
