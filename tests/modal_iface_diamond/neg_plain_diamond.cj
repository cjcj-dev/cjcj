// Negative control: the plain default `!=(other: T)` of Equatable<T> reached through Comparable<T> and
// Equatable<T> is still a "must be implemented" diagnostic, exactly as with an official std.
struct P <: Comparable<P> & Equatable<P> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public func compare(o: P): Ordering { v.compare(o.v) }
    public operator func ==(o: P): Bool { v == o.v }
}

main(): Int64 { if (P(1) != P(2)) { 0 } else { 1 } }
