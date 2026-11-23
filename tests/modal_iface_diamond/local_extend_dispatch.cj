// Local mode: the I0/I1/I2 shape of local_chain_dispatch reached through extends. X lists both interfaces in one
// extend, Y and Z split them over two extends in opposite orders; every @local? call must run I1's override (11).
interface I0 {
    func foo(): Int64
    func foo(this @local?): Int64 { 10 }
}
interface I1 <: I0 {
    func foo(this @local?): Int64 { 11 }
}
interface I2 <: I0 {}
struct X {}
extend X <: I2 & I1 { public func foo(): Int64 { 5 } }
struct Y {}
extend Y <: I2 { public func foo(): Int64 { 6 } }
extend Y <: I1 {}
struct Z {}
extend Z <: I1 { public func foo(): Int64 { 7 } }
extend Z <: I2 {}

func viaX(x: X @local?): Int64 { x.foo() }
func viaY(x: Y @local?): Int64 { x.foo() }
func viaZ(x: Z @local?): Int64 { x.foo() }

main(): Int64 {
    let r = "${viaX(X())} ${viaY(Y())} ${viaZ(Z())} ${X().foo()} ${Y().foo()} ${Z().foo()}"
    println(r)
    if (r == "11 11 11 5 6 7") { 0 } else { 4 }
}
