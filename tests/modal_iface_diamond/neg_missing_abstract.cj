// Negative control: an abstract member that is really missing (compare) is still required, and the
// modal `!=` defaults add nothing to the report.
struct M <: Comparable<M> & Equatable<M> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public operator func ==(o: M): Bool { v == o.v }
    public operator func !=(o: M): Bool { !(this == o) }
}

main(): Int64 { if (M(1) != M(2)) { 0 } else { 1 } }
