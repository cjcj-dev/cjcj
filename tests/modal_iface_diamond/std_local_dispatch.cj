// Local mode, --local-mode-api std. Comparable<T>'s `==(this @local?)` overrides Equal<T>'s and calls
// `compare(this @local?)`; Equatable<T>'s `!=(this @local?)` overrides NotEqual<T>'s and calls `==(this @local?)`.
// The std stubs throw naming their operator, so the printed name shows which ancestor ran: E/F must reach
// Comparable's `==` ("cmp", not Equal's "eq"), N/M must reach Equatable's `!=` ("eq", not NotEqual's "ne") in either
// supertype order. G implements `compare(this @local?)` modulo 10, so Comparable's `==` returns true for 1 vs 11.
struct E <: Equatable<E> & Comparable<E> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public func compare(o: E): Ordering { v.compare(o.v) }
    public operator func ==(o: E): Bool { v == o.v }
    public operator func !=(o: E): Bool { !(this == o) }
}
struct F <: Comparable<F> & Equatable<F> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public func compare(o: F): Ordering { v.compare(o.v) }
    public operator func ==(o: F): Bool { v == o.v }
    public operator func !=(o: F): Bool { !(this == o) }
}
struct G <: Equatable<G> & Comparable<G> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public func compare(o: G): Ordering { v.compare(o.v) }
    public func compare(this @local?, o: G @local?): Ordering { (v % 10).compare(o.v % 10) }
    public operator func ==(o: G): Bool { v == o.v }
    public operator func !=(o: G): Bool { !(this == o) }
}
struct N <: NotEqual<N> & Equatable<N> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public operator func ==(o: N): Bool { v == o.v }
}
struct M <: Equatable<M> & NotEqual<M> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public operator func ==(o: M): Bool { v == o.v }
}

func which(e: Exception): String {
    if (e.message.contains("'compare'")) { "cmp" } else if (e.message.contains("'=='")) { "eq" } else if (e.message.contains("'!='")) { "ne" } else { "other" }
}
func eqE(a: E @local?, b: E @local?): String { try { "${a == b}" } catch (e: Exception) { which(e) } }
func eqF(a: F @local?, b: F @local?): String { try { "${a == b}" } catch (e: Exception) { which(e) } }
func eqG(a: G @local?, b: G @local?): String { try { "${a == b}" } catch (e: Exception) { which(e) } }
func neN(a: N @local?, b: N @local?): String { try { "${a != b}" } catch (e: Exception) { which(e) } }
func neM(a: M @local?, b: M @local?): String { try { "${a != b}" } catch (e: Exception) { which(e) } }

main(): Int64 {
    let r = "${eqE(E(1), E(1))} ${eqF(F(1), F(1))} ${neN(N(1), N(1))} ${neM(M(1), M(1))} ${eqG(G(1), G(11))} ${E(1) == E(1)} ${N(1) != N(2)}"
    println(r)
    if (r == "cmp cmp eq eq true true true") { 0 } else { 4 }
}
