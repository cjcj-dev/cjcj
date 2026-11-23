// Comparable<T>'s `==(this @local?)` overrides Equal<T>'s; listing both must not ask for either.
struct Q <: Comparable<Q> & Equal<Q> & NotEqual<Q> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public func compare(o: Q): Ordering { v.compare(o.v) }
    public operator func ==(o: Q): Bool { v == o.v }
    public operator func !=(o: Q): Bool { !(this == o) }
}

main(): Int64 {
    let r = "${Q(1) == Q(1)} ${Q(1) != Q(2)} ${Q(3) > Q(2)}"
    println(r)
    if (r == "true true true") { 0 } else { 4 }
}
