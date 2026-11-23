// The shape of cjcj utils' UnicodeCharRange: a plain struct listing Comparable<T> and Equatable<T> and
// writing compare, == and != itself. With a --local-mode-api std, Equatable<T>'s `!=(this @local!)` and
// `!=(this @local?)` defaults reach the struct through both supertypes; they are one declaration each.
struct R <: Comparable<R> & Equatable<R> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public func compare(o: R): Ordering { v.compare(o.v) }
    public operator func ==(o: R): Bool { v == o.v }
    public operator func !=(o: R): Bool { !(this == o) }
}

main(): Int64 {
    let r = "${R(1) != R(2)} ${R(3) == R(3)} ${R(1) < R(2)} ${R(5).compare(R(4)) == Ordering.GT}"
    println(r)
    if (r == "true true true true") { 0 } else { 4 }
}
