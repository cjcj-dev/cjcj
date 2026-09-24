package nested_generic_payload

public struct PayloadPoint<T> {
    public let x: T
    init(x: T) { this.x = x }
}

public struct PayloadBox<T> {
    public let coords: PayloadPoint<T>
    init(x: T) { this.coords = PayloadPoint<T>(x) }
    public func nestedPayloadRead(): T { this.coords.x }
    public func singlePayloadRead(): PayloadPoint<T> { this.coords }
}

public func instantiatePayloadRead(): Int64 {
    let box = PayloadBox<Int64>(42)
    return box.nestedPayloadRead()
}

public func headedPayloadRead<T>(box: PayloadBox<T>): T { box.coords.x }
