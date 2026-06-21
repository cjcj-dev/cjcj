struct S <: Comparable<S> {
    let id: Int64

    public init(id: Int64) {
        this.id = id
    }

    public func compare(rhs: S): Ordering {
        if (id < rhs.id) {
            return Ordering.LT
        }
        if (rhs.id < id) {
            return Ordering.GT
        }
        return Ordering.EQ
    }
}

class Box<T> where T <: Comparable<T> {
    let value: T

    public init(value: T) {
        this.value = value
    }

    public func answer(): Int64 {
        return 7
    }
}

main() {
    let box = Box<S>(S(1))
    println(box.answer())
}
