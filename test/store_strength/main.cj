import std.ref.*

public class StrengthObject {}

public class StrengthHolder {
    public var _value: StrengthObject
    public init(value: StrengthObject) { _value = value }
}

public func ordinaryField(holder: StrengthHolder, value: StrengthObject): Unit {
    holder._value = value
}

public func arrayElement(value: StrengthObject): Array<StrengthObject> {
    [value]
}

public enum StrengthPayload<T> {
    Empty | Item(T)
}

public func enumPayload<T>(value: T): StrengthPayload<T> { StrengthPayload<T>.Item(value) }

public func boxedPayload(value: StrengthObject): Any { Some(value) }

public func weakClear(value: WeakRef<StrengthObject>): Unit { value.clear() }

main() {
    let value = StrengthObject()
    let holder = StrengthHolder(value)
    ordinaryField(holder, value)
    let _ = arrayElement(value)
    let _ = enumPayload<StrengthObject>(value)
    let _ = boxedPayload(value)
    weakClear(WeakRef<StrengthObject>(value, EAGER))
}
