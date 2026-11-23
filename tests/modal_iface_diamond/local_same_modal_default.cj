// Local mode: one modal default declared once (I1's `foo(this @local?)`) and reached through I2 and I1.
interface I1 {
    func foo(): Int64
    func foo(this @local?): Int64 { 7 }
}
interface I2 <: I1 {
    func foo(): Int64 { 2 }
}
struct S <: I2 & I1 {}

func viaLocal(s: S @local?): Int64 { s.foo() }

main(): Int64 {
    let r = "${S().foo()} ${viaLocal(S())}"
    println(r)
    if (r == "2 7") { 0 } else { 4 }
}
