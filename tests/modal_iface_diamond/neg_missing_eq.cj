// Negative control: Equatable<T> alone without the abstract `==` is still rejected.
struct E <: Equatable<E> {
    let v: Int64
    init(v: Int64) { this.v = v }
}

main(): Int64 { if (E(1) != E(2)) { 0 } else { 1 } }
