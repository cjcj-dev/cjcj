package dispatch_uses_instance

public interface Measured<T> where T <: Measured<T> {
    prop size: Int64
    func compareSize(other: T): Bool { this.size == other.size }
}

public class Item <: Measured<Item> {
    public prop size: Int64 { get() { 7 } }
}

public func entry(value: Measured<Item>, other: Item): Bool {
    value.compareSize(other)
}
