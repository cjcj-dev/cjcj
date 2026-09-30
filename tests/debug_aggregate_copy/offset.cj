package debug_copy

public struct Offset<T> {
    public let o: UInt32
    public init() { o = 0u32 }
    public init(o: UInt32) { this.o = o }
    public func Union(): Offset<Any> { return Offset<Any>(o) }
    public func IsNull(): Bool { return o == 0u32 }
}

public func check(): UInt32 {
    let a = Offset<Int64>(0x12345678u32)
    let b = a.Union()
    if (a.IsNull() || b.IsNull() || !Offset<Any>().IsNull()) { return 0u32 }
    return b.o
}
