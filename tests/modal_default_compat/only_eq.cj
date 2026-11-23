// == / != on String, Int64 and a user struct that only implements the plain `==`; the std
// Equatable/NotEqual it inherits from also declares `@local!` / `@local?` receiver overloads.
struct P <: Equatable<P> {
    let v: Int64
    init(v: Int64) { this.v = v }
    public operator func ==(o: P): Bool { v == o.v }
}

func differs<T>(a: T, b: T): Bool where T <: Equatable<T> { a != b }

main(): Int64 {
    let a = "x"
    let b = "y"
    let ne: NotEqual<P> = P(1)
    let r = "${a == b} ${a != b} ${P(1) != P(2)} ${P(3) == P(3)} ${1 != 2} ${differs(P(4), P(4))} ${ne != P(1)}"
    println(r)
    if (r == "false true true true true false false") { 0 } else { 4 }
}
