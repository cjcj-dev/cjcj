import std.ref.*

public class StrengthObject {}

public class StrengthHolder {
    public var field: StrengthObject
    public init(value: StrengthObject) { field = value }
}

public func ordinaryField(holder: StrengthHolder, value: StrengthObject): Unit {
    holder.field = value
}

public func arrayElement(value: StrengthObject): Array<StrengthObject> {
    [value]
}

public enum StrengthPayload<T> {
    Empty | Item(T)
}

public func enumPayload<T>(value: T): StrengthPayload<T> { StrengthPayload<T>.Item(value) }

public struct StrengthBoxPayload {
    public let value: StrengthObject
    public init(value: StrengthObject) { this.value = value }
}

public func boxedPayload<T>(value: T): Any { value }

public func weakClear(value: WeakRef<StrengthObject>): Unit { value.clear() }

main() {
    let value = StrengthObject()
    let holder = StrengthHolder(value)
    ordinaryField(holder, value)
    let _ = arrayElement(value)
    let _ = enumPayload<StrengthObject>(value)
    let _ = boxedPayload<StrengthBoxPayload>(StrengthBoxPayload(value))
    weakClear(WeakRef<StrengthObject>(value, EAGER))
}
