// Local mode: I2 overrides I1's modal default and S lists both. The more specific default (I2's, 8) is the
// member, as Comparable<T>'s `==(this @local?)` is over Equal<T>'s; the plain foo keeps its own rule.
interface I1 {
    func foo(): Int64
    func foo(this @local?): Int64 { 7 }
}
interface I2 <: I1 {
    func foo(): Int64 { 2 }
    func foo(this @local?): Int64 { 8 }
}
struct S <: I2 & I1 {}
struct T <: I1 & I2 {}

func viaLocal(s: S @local?): Int64 { s.foo() }
func viaLocalT(t: T @local?): Int64 { t.foo() }

main(): Int64 {
    let r = "${S().foo()} ${viaLocal(S())} ${T().foo()} ${viaLocalT(T())}"
    println(r)
    if (r == "2 8 2 8") { 0 } else { 4 }
}
