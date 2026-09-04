// Tracked AS1 interior source: the generic mut wrapper copies a field whose
// base is the containing heap object.
struct Pair<T> {
    var left: T
    var right: T

    public init(left: T, right: T) {
        this.left = left
        this.right = right
    }

    public mut func replace(left: T, right: T): Unit {
        this.left = left
        this.right = right
    }
}

class Holder {
    var pair = Pair<Int64>(1, 2)

    public func update(): Unit {
        pair.replace(3, 4)
    }
}

main() {
    let holder = Holder()
    holder.update()
    if (holder.pair.left != 3 || holder.pair.right != 4) {
        throw Exception("bad tracked managed payload copy")
    }
}
