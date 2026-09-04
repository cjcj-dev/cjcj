// Whole AS1 object source: an erased reference-bearing receiver is copied by
// the object-level generic assignment path rather than the native payload ABI.
struct Pair<T> {
    var left: T
    var right: T

    public init(value: T) {
        left = value
        right = value
    }

    public mut func replace(value: T): Unit {
        left = value
        right = value
    }
}

class Holder<T> {
    var pair: Pair<T>

    public init(value: T) {
        pair = Pair<T>(value)
    }

    public func update(value: T): Unit {
        pair.replace(value)
    }
}

main() {
    let holder = Holder<String>("before")
    holder.update("after")
    if (holder.pair.left != "after" || holder.pair.right != "after") {
        throw Exception("bad whole managed payload copy")
    }
}
