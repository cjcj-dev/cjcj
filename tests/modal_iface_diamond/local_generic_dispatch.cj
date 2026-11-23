// Local mode, generic interfaces: G1<T> overrides G0<T>'s modal default, G2<T> <: G0<T> does not. A plain struct,
// a generic struct and a generic class listing G2 first must all run G1's override (21), never G0's (20).
interface G0<T> {
    func bar(x: T): Int64
    func bar(this @local?, x: T): Int64 { 20 }
}
interface G1<T> <: G0<T> {
    func bar(this @local?, x: T): Int64 { 21 }
}
interface G2<T> <: G0<T> {}
struct P <: G2<Int64> & G1<Int64> { public func bar(x: Int64): Int64 { x } }
struct R<T> <: G2<T> & G1<T> { public func bar(x: T): Int64 { 1 } }
class Q<T> <: G2<T> & G1<T> {
    public init() {}
    public func bar(x: T): Int64 { 2 }
}

func viaP(p: P @local?): Int64 { p.bar(3) }
func viaR(r: R<Int64> @local?): Int64 { r.bar(3) }
func viaQ(q: Q<String> @local?, w: String): Int64 { q.bar(w) }

main(): Int64 {
    let word = "s"
    let r = "${viaP(P())} ${viaR(R<Int64>())} ${viaQ(Q<String>(), word)} ${P().bar(3)} ${R<Int64>().bar(3)} ${Q<String>().bar(word)}"
    println(r)
    if (r == "21 21 21 3 1 2") { 0 } else { 4 }
}
