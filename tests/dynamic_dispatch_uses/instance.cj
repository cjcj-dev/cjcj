package dispatch_uses_instance

interface Measured<T> where T <: Measured<T> {
    prop size: Int64
    func compareSize(other: T): Bool { this.size == other.size }
}

class Item <: Measured<Item> {
    public prop size: Int64 { get() { 7 } }
}

func compare(value: Measured<Item>, other: Item): Bool {
    value.compareSize(other)
}

public func entry(): Bool { compare(Item(), Item()) }

main(): Int64 { if (entry()) { 0 } else { 1 } }
