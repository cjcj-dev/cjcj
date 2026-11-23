// Same as unicode_shape with the supertypes listed in the other order, on a class.
class C <: Equatable<C> & Comparable<C> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public func compare(o: C): Ordering { v.compare(o.v) }
    public operator func ==(o: C): Bool { v == o.v }
    public operator func !=(o: C): Bool { !(this == o) }
}

func differs<T>(a: T, b: T): Bool where T <: Equatable<T> { a != b }

main(): Int64 {
    let r = "${C(1) != C(1)} ${differs(C(1), C(2))} ${C(2) >= C(2)}"
    println(r)
    if (r == "false true true") { 0 } else { 4 }
}
