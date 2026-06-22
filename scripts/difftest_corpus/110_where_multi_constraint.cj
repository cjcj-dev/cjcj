interface Named {
    func name(): String
}

class Key <: Hashable & Named {
    let value: Int64

    public init(value: Int64) {
        this.value = value
    }

    public func hashCode(): Int64 {
        return value
    }

    public func name(): String {
        return "key"
    }
}

class Item <: Hashable & Named {
    let value: Int64

    public init(value: Int64) {
        this.value = value
    }

    public func hashCode(): Int64 {
        return value + 10
    }

    public func name(): String {
        return "item"
    }
}

func mix<T1, T2>(left: T1, right: T2): Int64 where T1 <: Hashable & Named, T2 <: Hashable & Named {
    return 7
}

class PairBox<T1, T2> where T1 <: Hashable & Named, T2 <: Hashable & Named {
    let left: T1
    let right: T2

    public init(left: T1, right: T2) {
        this.left = left
        this.right = right
    }

    public func score(): Int64 {
        return 11
    }
}

struct PairStruct<T1, T2> where T1 <: Hashable, T2 <: Hashable {
    let left: T1
    let right: T2

    public init(left: T1, right: T2) {
        this.left = left
        this.right = right
    }

    public func score(): Int64 {
        return 13
    }
}

func single<T>(value: T): Int64 where T <: Hashable {
    return 17
}

main() {
    let k = Key(1)
    let i = Item(2)
    let box = PairBox<Key, Item>(k, i)
    let st = PairStruct<Key, Item>(k, i)
    println(mix<Key, Item>(k, i) + box.score() + st.score() + single<Key>(k))
}
