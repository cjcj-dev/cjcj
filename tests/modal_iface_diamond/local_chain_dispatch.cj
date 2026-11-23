// Local mode: every ancestor gives its @local? foo a distinct result, so the executed implementation is visible.
// I1 overrides I0's modal default, I2 <: I0 does not. Whatever order the supertypes are written in, a struct call
// and a class call must both run I1's override (11), never I0's (10), and keep the plain foo of each type.
interface I0 {
    func foo(): Int64
    func foo(this @local?): Int64 { 10 }
}
interface I1 <: I0 {
    func foo(this @local?): Int64 { 11 }
}
interface I2 <: I0 {}
struct D12 <: I1 & I2 { public func foo(): Int64 { 1 } }
struct D21 <: I2 & I1 { public func foo(): Int64 { 3 } }
struct C01 <: I0 & I1 { public func foo(): Int64 { 1 } }
struct C10 <: I1 & I0 { public func foo(): Int64 { 1 } }
class K <: I2 & I1 {
    public init() {}
    public func foo(): Int64 { 4 }
}

func viaD12(x: D12 @local?): Int64 { x.foo() }
func viaD21(x: D21 @local?): Int64 { x.foo() }
func viaC01(x: C01 @local?): Int64 { x.foo() }
func viaC10(x: C10 @local?): Int64 { x.foo() }
func viaK(x: K @local?): Int64 { x.foo() }

main(): Int64 {
    let r = "${viaD12(D12())} ${viaD21(D21())} ${viaC01(C01())} ${viaC10(C10())} ${viaK(K())} ${D21().foo()} ${K().foo()}"
    println(r)
    if (r == "11 11 11 11 11 3 4") { 0 } else { 4 }
}
